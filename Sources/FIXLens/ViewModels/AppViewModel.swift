import SwiftUI
import AppKit

// MARK: - View mode

enum ViewMode {
    /// Today's file, < 10 MB — full in-memory load + kqueue tailing.
    case live
    /// Old file or ≥ 10 MB — lightweight summary index, FileHandle for detail reads.
    case analysis
    /// Pasted text — full in-memory load, no tailing.
    case paste
}

// MARK: - Scroll notification

extension Notification.Name {
    static let scrollToBottom = Notification.Name("FIXLens.scrollToBottom")
}

// MARK: - AppViewModel

@Observable
@MainActor
final class AppViewModel {

    // MARK: - Unified display state

    /// Full message objects — populated in live/paste mode only.
    private(set) var allMessages: [FIXMessage] = []

    /// Lightweight summaries — populated in all modes; the table always uses this.
    private(set) var allSummaries: [FIXMessageSummary] = []

    /// Filtered subset of allSummaries shown in the timeline.
    private(set) var displayedSummaries: [FIXMessageSummary] = []

    // MARK: - Selection & detail

    var selectedMessageID: FIXMessage.ID? = nil {
        didSet {
            guard viewMode == .analysis else { return }
            loadDetailTask?.cancel()
            guard selectedMessageID != nil else { loadedDetailMessage = nil; return }
            loadDetailTask = Task { await loadDetailForSelectedSummary() }
        }
    }

    /// Full detail message: computed from allMessages (live/paste) or loaded async (analysis).
    var selectedMessage: FIXMessage? {
        guard let id = selectedMessageID else { return nil }
        if viewMode == .analysis { return loadedDetailMessage }
        return allMessages.first { $0.id == id }
    }

    private(set) var loadedDetailMessage: FIXMessage? = nil
    private(set) var isLoadingDetail = false
    @ObservationIgnored private var loadDetailTask: Task<Void, Never>?

    // MARK: - Parse / filter progress

    var rawInput: String = ""
    var parseProgress: Double = 0
    var isParsing: Bool = false
    var isFiltering: Bool = false
    var isDictionaryLoaded: Bool = false
    var errorMessage: String? = nil

    // MARK: - Filter state

    var showAdminMessages: Bool = false { didSet { scheduleFilter() } }
    var searchText: String = ""      { didSet { scheduleFilter() } }
    var filterMsgType: String? = nil    { didSet { scheduleFilter() } }
    var filterSide: String? = nil       { didSet { scheduleFilter() } }
    var filterStatus: String? = nil     { didSet { scheduleFilter() } }
    var filterTradesOnly: Bool = false  { didSet { scheduleFilter() } }

    // MARK: - File / mode state

    var sourceFilename: String? = nil
    private(set) var viewMode: ViewMode = .paste

    // MARK: - Tailing state (live mode only)

    private(set) var isTailing: Bool = false
    private(set) var tailingPaused: Bool = false
    private(set) var tailFileGone: Bool = false
    var autoScroll: Bool = false

    // MARK: - Private

    private(set) var dictionary: FIXDictionary = .empty

    @ObservationIgnored private var filterTask: Task<Void, Never>?
    @ObservationIgnored private var tailWatcher: FileTailWatcher?
    /// Raw byte accumulator for the tail parser. Buffers bytes until a complete
    /// newline-terminated line is available, avoiding silent data loss when a
    /// kernel read ends mid-UTF-8 sequence.
    @ObservationIgnored private var tailRawBuffer: Data = Data()

    @ObservationIgnored private var sourceURL: URL? = nil
    @ObservationIgnored private var isSecurityScoped = false
    @ObservationIgnored private var analysisFileHandle: FileHandleActor? = nil
    @ObservationIgnored private var detectedDelimiter: FIXDelimiter = .pipe

    // MARK: - Derived

    var hasActiveFilters: Bool {
        !searchText.isEmpty || filterMsgType != nil || filterSide != nil || filterStatus != nil || filterTradesOnly
    }

    var filterSummary: String {
        let total = allSummaries.count
        guard total > 0 else { return "" }
        let shown = displayedSummaries.count
        if shown == total { return "\(total) messages" }
        return "\(shown) of \(total)"
    }

    /// Distinct MsgType values present in allSummaries, for the Type filter picker.
    var availableMsgTypes: [(type: String, name: String)] {
        var seen = Set<String>()
        return allSummaries.compactMap { msg in
            guard let t = msg.msgType, seen.insert(t).inserted else { return nil }
            return (type: t, name: msg.msgTypeName)
        }
        .sorted { $0.name < $1.name }
    }

    // MARK: - Actions

    func clearFilters() {
        searchText       = ""
        filterMsgType    = nil
        filterSide       = nil
        filterStatus     = nil
        filterTradesOnly = false
    }

    func loadDictionary() async {
        let dict = await Task.detached(priority: .userInitiated) {
            FIXDictionaryLoader.loadFromBundle()
        }.value
        self.dictionary = dict
        self.isDictionaryLoaded = true
    }

    func parseInput() {
        let input = rawInput
        guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        Task { await runStreamingParse(input) }
    }

    func loadFromURL(_ url: URL) async {
        // Clean up any prior state
        stopTailing()
        releaseSecurityScope()
        if let fh = analysisFileHandle { try? await fh.close() }
        analysisFileHandle = nil
        tailFileGone   = false
        tailRawBuffer  = Data()

        // Determine mode from file attributes
        let attrs = (try? FileManager.default.attributesOfItem(atPath: url.path)) ?? [:]
        let modDate  = attrs[.modificationDate] as? Date ?? .distantPast
        let fileSize = attrs[.size] as? Int ?? 0
        let isToday  = Calendar.current.isDateInToday(modDate)
        let isLive   = isToday && fileSize < 10_000_000

        let accessing = url.startAccessingSecurityScopedResource()

        if isLive {
            await loadLiveMode(url, accessing: accessing)
        } else {
            await loadAnalysisMode(url, accessing: accessing)
        }
    }

    func clear() {
        stopTailing()
        releaseSecurityScope()
        Task { if let fh = analysisFileHandle { try? await fh.close() } }
        analysisFileHandle = nil

        filterTask?.cancel()
        loadDetailTask?.cancel()

        rawInput             = ""
        allMessages          = []
        allSummaries         = []
        displayedSummaries   = []
        selectedMessageID    = nil
        loadedDetailMessage  = nil
        sourceFilename       = nil
        sourceURL            = nil
        viewMode             = .paste
        parseProgress        = 0
        isFiltering          = false
        isParsing            = false
        isTailing            = false
        tailingPaused        = false
        tailFileGone         = false
        autoScroll           = false
        searchText           = ""
        filterMsgType        = nil
        filterSide           = nil
        filterStatus         = nil
        filterTradesOnly     = false
    }

    // MARK: - Tailing control

    func pauseTailing() {
        guard isTailing, !tailingPaused else { return }
        tailWatcher?.pause()
        tailingPaused = true
    }

    func resumeTailing() {
        guard isTailing, tailingPaused else { return }
        tailWatcher?.resume()
        tailingPaused = false
    }

    func reloadFile() {
        guard let url = sourceURL else { return }
        tailFileGone = false
        Task { await loadFromURL(url) }
    }

    // MARK: - Private: file loading

    private func loadLiveMode(_ url: URL, accessing: Bool) async {
        isSecurityScoped = accessing
        sourceURL        = url
        sourceFilename   = url.lastPathComponent
        viewMode         = .live
        rawInput         = ""

        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            addToRecentFiles(url)
            let sample = String(content.prefix(2_000))
            detectedDelimiter = FIXParser.detectDelimiter(sample)
            await runStreamingParse(content)

            // Default auto-scroll: on for small initial loads
            autoScroll = allSummaries.count <= 2_000

            // Use current file size as the tail's starting offset to avoid re-parsing
            // content that was already loaded above.
            let tailOffset = (try? FileHandle(forReadingFrom: url).seekToEnd()) ?? UInt64(0)
            startTailingFile(url: url, startOffset: tailOffset)
        } catch {
            if accessing { url.stopAccessingSecurityScopedResource(); isSecurityScoped = false }
            errorMessage = "Could not read file: \(error.localizedDescription)"
        }
    }

    private func loadAnalysisMode(_ url: URL, accessing: Bool) async {
        isSecurityScoped = accessing
        sourceURL        = url
        sourceFilename   = url.lastPathComponent
        viewMode         = .analysis
        rawInput         = ""
        autoScroll       = false

        addToRecentFiles(url)

        // Open a persistent FileHandle for on-demand detail reads
        if let fh = try? FileHandle(forReadingFrom: url) {
            analysisFileHandle = FileHandleActor(fileHandle: fh)
        }

        isParsing      = true
        parseProgress  = 0
        allMessages    = []
        allSummaries   = []
        displayedSummaries = []
        selectedMessageID  = nil
        loadedDetailMessage = nil

        for await update in FIXParser.streamAnalysis(fileURL: url, dictionary: dictionary) {
            detectedDelimiter = update.delimiter
            allSummaries.append(contentsOf: update.batch)
            let visible = showAdminMessages
                ? update.batch
                : update.batch.filter { !$0.isAdmin }
            displayedSummaries.append(contentsOf: visible)
            parseProgress = update.progress
        }

        isParsing     = false
        parseProgress = 1.0
        scheduleFilter()
    }

    // MARK: - Private: paste mode streaming

    private func runStreamingParse(_ content: String) async {
        isParsing          = true
        parseProgress      = 0
        allMessages        = []
        allSummaries       = []
        displayedSummaries = []
        selectedMessageID  = nil
        loadedDetailMessage = nil

        let dict = dictionary
        for await update in FIXParser.stream(content, dictionary: dict) {
            let summaries = update.batch.map { FIXMessageSummary(from: $0) }
            allMessages.append(contentsOf: update.batch)
            allSummaries.append(contentsOf: summaries)
            let visible = showAdminMessages
                ? summaries
                : summaries.filter { !$0.isAdmin }
            displayedSummaries.append(contentsOf: visible)
            parseProgress = update.progress
        }

        isParsing     = false
        parseProgress = 1.0
        scheduleFilter()
    }

    // MARK: - Private: filter

    private func scheduleFilter() {
        filterTask?.cancel()
        let summaries   = allSummaries
        let showAdmin   = showAdminMessages
        let search      = searchText.lowercased()
        let msgType     = filterMsgType
        let side        = filterSide
        let status      = filterStatus
        let tradesOnly  = filterTradesOnly

        isFiltering = true
        filterTask = Task {
            if !search.isEmpty {
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled else { return }
            }
            let result: [FIXMessageSummary] = await Task.detached {
                summaries.filter { msg in
                    if !showAdmin && msg.isAdmin { return false }
                    if let t = msgType, msg.msgType != t { return false }
                    if let s = side,    msg.side    != s { return false }
                    if let st = status, msg.ordStatus != st { return false }
                    if tradesOnly, !["F","G","H"].contains(msg.execType ?? "") { return false }
                    if !search.isEmpty {
                        return msg.msgTypeName.lowercased().contains(search)
                            || (msg.securityID?.lowercased().contains(search) ?? false)
                            || (msg.clOrdID?.lowercased().contains(search) ?? false)
                            || msg.sessionDisplay.lowercased().contains(search)
                    }
                    return true
                }
            }.value
            guard !Task.isCancelled else { return }
            self.displayedSummaries = result
            self.isFiltering = false
        }
    }

    // MARK: - Private: analysis detail loading

    private func loadDetailForSelectedSummary() async {
        guard let id = selectedMessageID,
              let summary = allSummaries.first(where: { $0.id == id }) else {
            loadedDetailMessage = nil
            return
        }
        isLoadingDetail = true
        loadedDetailMessage = await FIXParser.loadFullMessage(
            summary: summary,
            fileHandle: analysisFileHandle,
            delimiter: detectedDelimiter,
            dictionary: dictionary
        )
        isLoadingDetail = false
    }

    // MARK: - Private: tailing

    private func startTailingFile(url: URL, startOffset: UInt64) {
        tailWatcher?.stop()
        isTailing     = true
        tailingPaused = false
        tailFileGone  = false
        tailRawBuffer = Data()

        tailWatcher = FileTailWatcher(
            url: url,
            startingOffset: startOffset,
            onNewData: { [weak self] data in
                guard let self else { return }
                Task { @MainActor in self.processTailData(data) }
            },
            onFileGone: { [weak self] in
                guard let self else { return }
                Task { @MainActor in
                    self.isTailing    = false
                    self.tailFileGone = true
                }
            }
        )
    }

    private func processTailData(_ data: Data) {
        // Accumulate raw bytes so a read that ends mid-UTF-8 sequence never
        // silently discards data. Extract only complete newline-terminated lines.
        tailRawBuffer.append(contentsOf: data)

        let newlineByte = UInt8(0x0A)
        var lines: [String] = []
        var searchFrom = tailRawBuffer.startIndex

        while let nlPos = tailRawBuffer[searchFrom...].firstIndex(of: newlineByte) {
            let lineData = tailRawBuffer[searchFrom..<nlPos]
            if let line = String(data: lineData, encoding: .utf8) {
                lines.append(line)
            }
            searchFrom = tailRawBuffer.index(after: nlPos)
        }

        // Keep bytes after the last newline for the next read
        tailRawBuffer = searchFrom < tailRawBuffer.endIndex
            ? Data(tailRawBuffer[searchFrom...])
            : Data()

        guard !lines.isEmpty else { return }

        let delimiter  = detectedDelimiter
        let dict       = dictionary
        let startIndex = allMessages.count

        Task.detached(priority: .userInitiated) { [lines] in
            var newMessages: [FIXMessage] = []
            for (i, line) in lines.enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty,
                      let rawMsg = FIXParser.extractFIXMessage(from: trimmed),
                      let msg = FIXParser.parseMessage(
                          rawMsg,
                          index: startIndex + i,
                          delimiter: delimiter,
                          dictionary: dict
                      ) else { continue }
                newMessages.append(msg)
            }

            guard !newMessages.isEmpty else { return }

            await MainActor.run {
                let newSummaries = newMessages.map { FIXMessageSummary(from: $0) }
                self.allMessages.append(contentsOf: newMessages)
                self.allSummaries.append(contentsOf: newSummaries)

                // Apply active filters to only the new summaries
                let showAdmin  = self.showAdminMessages
                let search     = self.searchText.lowercased()
                let msgType    = self.filterMsgType
                let side       = self.filterSide
                let status     = self.filterStatus
                let tradesOnly = self.filterTradesOnly

                let newVisible = newSummaries.filter { msg in
                    if !showAdmin && msg.isAdmin { return false }
                    if let t = msgType,  msg.msgType   != t  { return false }
                    if let s = side,     msg.side      != s  { return false }
                    if let st = status,  msg.ordStatus != st { return false }
                    if tradesOnly, !["F","G","H"].contains(msg.execType ?? "") { return false }
                    if !search.isEmpty {
                        return msg.msgTypeName.lowercased().contains(search)
                            || (msg.securityID?.lowercased().contains(search) ?? false)
                            || (msg.clOrdID?.lowercased().contains(search) ?? false)
                            || msg.sessionDisplay.lowercased().contains(search)
                    }
                    return true
                }

                self.displayedSummaries.append(contentsOf: newVisible)

                // Signal auto-scroll if appropriate
                if self.autoScroll && self.selectedMessageID == nil && !newVisible.isEmpty {
                    NotificationCenter.default.post(name: .scrollToBottom, object: nil)
                }
            }
        }
    }

    private func stopTailing() {
        tailWatcher?.stop()
        tailWatcher    = nil
        isTailing      = false
        tailingPaused  = false
        tailRawBuffer  = Data()
    }

    private func releaseSecurityScope() {
        guard isSecurityScoped, let url = sourceURL else { return }
        url.stopAccessingSecurityScopedResource()
        isSecurityScoped = false
    }

    // MARK: - Recent files

    private func addToRecentFiles(_ url: URL) {
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
        var paths = UserDefaults.standard.stringArray(forKey: "fixlens.recentFiles") ?? []
        paths.removeAll { $0 == url.path }
        paths.insert(url.path, at: 0)
        UserDefaults.standard.set(Array(paths.prefix(10)), forKey: "fixlens.recentFiles")
    }
}
