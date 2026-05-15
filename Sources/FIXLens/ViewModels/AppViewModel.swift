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
    static let scrollToBottom  = Notification.Name("FIXLens.scrollToBottom")
    static let openFileRequest = Notification.Name("FIXLens.openFileRequest")
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

    /// Full detail message: O(1) lookup in live/paste mode, async-loaded in analysis mode.
    var selectedMessage: FIXMessage? {
        guard let id = selectedMessageID else { return nil }
        if viewMode == .analysis { return loadedDetailMessage }
        return messageByID[id]
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

    var showAdminMessages: Bool = UserDefaults.standard.bool(forKey: "fixlens.showAdmin") {
        didSet { UserDefaults.standard.set(showAdminMessages, forKey: "fixlens.showAdmin"); scheduleFilter() }
    }
    var showLocalTime: Bool = UserDefaults.standard.bool(forKey: "fixlens.showLocalTime") {
        didSet { UserDefaults.standard.set(showLocalTime, forKey: "fixlens.showLocalTime") }
    }
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
    var autoScroll: Bool = UserDefaults.standard.bool(forKey: "fixlens.autoScroll") {
        didSet { UserDefaults.standard.set(autoScroll, forKey: "fixlens.autoScroll") }
    }

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
    @ObservationIgnored private(set) var detectedDelimiter: FIXDelimiter = .pipe
    @ObservationIgnored private var tempDecompressedURL: URL? = nil

    /// O(1) lookup tables kept in sync with allMessages / allSummaries.
    @ObservationIgnored private var messageByID:  [UUID: FIXMessage] = [:]
    @ObservationIgnored private var summaryByID:  [UUID: FIXMessageSummary] = [:]

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

    /// Distinct MsgType values present in allSummaries, kept sorted by name.
    /// Updated incrementally as summaries arrive to avoid O(n) scans on every render.
    private(set) var availableMsgTypes: [(type: String, name: String)] = []
    @ObservationIgnored private var seenMsgTypes: Set<String> = []

    private func updateMsgTypeCache(from new: [FIXMessageSummary]) {
        var changed = false
        for s in new {
            guard let t = s.msgType, seenMsgTypes.insert(t).inserted else { continue }
            availableMsgTypes.append((type: t, name: s.msgTypeName))
            changed = true
        }
        if changed { availableMsgTypes.sort { $0.name < $1.name } }
    }

    // MARK: - Actions

    /// Synchronous raw-text lookup — O(1) in live/paste mode.
    /// In analysis mode returns only what is already in memory.
    func rawText(for id: FIXMessage.ID) -> String? {
        if let msg = messageByID[id] { return msg.rawText }
        if loadedDetailMessage?.id == id { return loadedDetailMessage?.rawText }
        return nil
    }

    /// Raw-text lookup for copy operations.
    /// Falls back to an on-demand disk read in analysis mode so the caller
    /// always gets the text regardless of whether the detail is pre-loaded.
    func rawTextForCopy(for id: FIXMessage.ID) async -> String? {
        if let fast = rawText(for: id) { return fast }
        guard viewMode == .analysis, let summary = summaryByID[id] else { return nil }
        return await FIXParser.loadFullMessage(
            summary: summary,
            fileHandle: analysisFileHandle,
            delimiter: detectedDelimiter,
            dictionary: dictionary
        )?.rawText
    }

    /// O(1) summary lookup used by the timeline for copy/context-menu actions.
    func summary(for id: FIXMessageSummary.ID) -> FIXMessageSummary? {
        summaryByID[id]
    }

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
        let isGzip = url.pathExtension.lowercased() == "gz"

        // Clean up any prior state
        stopTailing()
        releaseSecurityScope()
        cleanupTempFile()
        if let fh = analysisFileHandle { try? await fh.close() }
        analysisFileHandle = nil
        tailFileGone   = false
        tailRawBuffer  = Data()

        // Decompress .gz to a temp file, then treat it as a regular (non-live) file.
        let fileURL: URL
        if isGzip {
            isParsing = true
            let accessing = url.startAccessingSecurityScopedResource()
            guard let tempURL = await decompressGzip(url) else {
                if accessing { url.stopAccessingSecurityScopedResource() }
                isParsing = false
                errorMessage = "Could not decompress \(url.lastPathComponent)"
                return
            }
            if accessing { url.stopAccessingSecurityScopedResource() }
            tempDecompressedURL = tempURL
            fileURL = tempURL
            addToRecentFiles(url)
        } else {
            fileURL = url
        }

        // Determine mode from file attributes
        let attrs = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)) ?? [:]
        let modDate  = attrs[.modificationDate] as? Date ?? .distantPast
        let fileSize = attrs[.size] as? Int ?? 0
        // .gz files are never live-tailed — they are static archives
        let isToday  = !isGzip && Calendar.current.isDateInToday(modDate)
        let isLive   = isToday && fileSize < 10_000_000

        let accessing = isGzip ? false : fileURL.startAccessingSecurityScopedResource()

        if isLive {
            await loadLiveMode(fileURL, accessing: accessing)
        } else {
            await loadAnalysisMode(fileURL, accessing: accessing, displayURL: isGzip ? url : nil)
        }
    }

    func clear() {
        stopTailing()
        releaseSecurityScope()
        cleanupTempFile()
        Task { if let fh = analysisFileHandle { try? await fh.close() } }
        analysisFileHandle = nil

        filterTask?.cancel()
        loadDetailTask?.cancel()

        rawInput             = ""
        allMessages          = []
        allSummaries         = []
        displayedSummaries   = []
        availableMsgTypes    = []
        seenMsgTypes         = []
        messageByID          = [:]
        summaryByID          = [:]
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
            let tailOffset: UInt64 = (try? {
                let fh = try FileHandle(forReadingFrom: url)
                defer { try? fh.close() }
                return try fh.seekToEnd()
            }()) ?? 0
            startTailingFile(url: url, startOffset: tailOffset)
        } catch {
            if accessing { url.stopAccessingSecurityScopedResource(); isSecurityScoped = false }
            errorMessage = "Could not read file: \(error.localizedDescription)"
        }
    }

    private func loadAnalysisMode(_ url: URL, accessing: Bool, displayURL: URL? = nil) async {
        isSecurityScoped = accessing
        sourceURL        = displayURL ?? url   // reload via original path (important for .gz)
        sourceFilename   = (displayURL ?? url).lastPathComponent
        viewMode         = .analysis
        rawInput         = ""
        autoScroll       = false

        if displayURL == nil { addToRecentFiles(url) }  // gz already added in loadFromURL

        // Open a persistent FileHandle for on-demand detail reads
        if let fh = try? FileHandle(forReadingFrom: url) {
            analysisFileHandle = FileHandleActor(fileHandle: fh)
        }

        isParsing         = true
        parseProgress     = 0
        allMessages       = []
        allSummaries      = []
        availableMsgTypes = []
        seenMsgTypes      = []
        messageByID       = [:]
        summaryByID       = [:]
        displayedSummaries = []
        selectedMessageID  = nil
        loadedDetailMessage = nil

        for await update in FIXParser.streamAnalysis(fileURL: url, dictionary: dictionary) {
            detectedDelimiter = update.delimiter
            allSummaries.append(contentsOf: update.batch)
            for s in update.batch { summaryByID[s.id] = s }
            updateMsgTypeCache(from: update.batch)
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
        parseProgress     = 0
        allMessages       = []
        allSummaries      = []
        availableMsgTypes = []
        seenMsgTypes      = []
        messageByID       = [:]
        summaryByID       = [:]
        displayedSummaries = []
        selectedMessageID  = nil
        loadedDetailMessage = nil

        let dict = dictionary
        for await update in FIXParser.stream(content, dictionary: dict) {
            let summaries = update.batch.map { FIXMessageSummary(from: $0) }
            allMessages.append(contentsOf: update.batch)
            for m in update.batch { messageByID[m.id] = m }
            allSummaries.append(contentsOf: summaries)
            for s in summaries { summaryByID[s.id] = s }
            updateMsgTypeCache(from: summaries)
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

    private nonisolated static func matchesFilter(
        _ msg: FIXMessageSummary,
        showAdmin: Bool,
        search: String,       // must be pre-lowercased
        msgType: String?,
        side: String?,
        status: String?,
        tradesOnly: Bool
    ) -> Bool {
        if !showAdmin && msg.isAdmin { return false }
        if let t = msgType, msg.msgType   != t  { return false }
        if let s = side,    msg.side      != s  { return false }
        if let st = status, msg.ordStatus != st { return false }
        if tradesOnly, !["F", "G", "H"].contains(msg.execType ?? "") { return false }
        if !search.isEmpty {
            return msg.msgTypeName.lowercased().contains(search)
                || (msg.securityID?.lowercased().contains(search) ?? false)
                || (msg.clOrdID?.lowercased().contains(search) ?? false)
                || msg.sessionDisplay.lowercased().contains(search)
        }
        return true
    }

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
                summaries.filter {
                    AppViewModel.matchesFilter($0, showAdmin: showAdmin, search: search,
                                              msgType: msgType, side: side, status: status,
                                              tradesOnly: tradesOnly)
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
              let summary = summaryByID[id] else {
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
                for m in newMessages { self.messageByID[m.id] = m }
                self.allSummaries.append(contentsOf: newSummaries)
                for s in newSummaries { self.summaryByID[s.id] = s }
                self.updateMsgTypeCache(from: newSummaries)

                // Apply active filters to only the new summaries
                let showAdmin  = self.showAdminMessages
                let search     = self.searchText.lowercased()
                let msgType    = self.filterMsgType
                let side       = self.filterSide
                let status     = self.filterStatus
                let tradesOnly = self.filterTradesOnly

                let newVisible = newSummaries.filter {
                    AppViewModel.matchesFilter($0, showAdmin: showAdmin, search: search,
                                              msgType: msgType, side: side, status: status,
                                              tradesOnly: tradesOnly)
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

    // MARK: - Private: gzip decompression

    private func cleanupTempFile() {
        guard let temp = tempDecompressedURL else { return }
        try? FileManager.default.removeItem(at: temp)
        tempDecompressedURL = nil
    }

    private func decompressGzip(_ url: URL) async -> URL? {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".log")
        return await Task.detached(priority: .userInitiated) {
            do {
                FileManager.default.createFile(atPath: tempURL.path, contents: nil)
                guard let out = FileHandle(forWritingAtPath: tempURL.path) else { return nil }
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: "/usr/bin/gunzip")
                proc.arguments     = ["-c", url.path]
                proc.standardOutput = out
                proc.standardError  = FileHandle.nullDevice
                try proc.run()
                proc.waitUntilExit()
                try out.close()
                return proc.terminationStatus == 0 ? tempURL : nil
            } catch {
                return nil
            }
        }.value
    }

    // MARK: - Recent files

    private func addToRecentFiles(_ url: URL) {
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
    }
}
