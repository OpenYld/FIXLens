import SwiftUI
import AppKit

@Observable
@MainActor
final class AppViewModel {

    // MARK: - State

    var rawInput: String = ""

    var allMessages: [FIXMessage] = []

    var displayedMessages: [FIXMessage] = []
    var parseProgress: Double = 0

    var selectedMessageID: FIXMessage.ID? = nil

    var showAdminMessages: Bool = false { didSet { scheduleFilter() } }
    var isParsing: Bool = false
    var isFiltering: Bool = false
    var isDictionaryLoaded: Bool = false
    var errorMessage: String? = nil

    /// Set when content was loaded from a file rather than pasted.
    var sourceFilename: String? = nil

    // Filter state — each didSet triggers scheduleFilter()
    var searchText: String = "" { didSet { scheduleFilter() } }
    var filterMsgType: String? = nil { didSet { scheduleFilter() } }
    var filterSide: String? = nil { didSet { scheduleFilter() } }
    var filterStatus: String? = nil { didSet { scheduleFilter() } }

    // MARK: - Private

    private(set) var dictionary: FIXDictionary = .empty

    @ObservationIgnored private var filterTask: Task<Void, Never>?

    // MARK: - Derived

    var selectedMessage: FIXMessage? {
        guard let id = selectedMessageID else { return nil }
        return allMessages.first { $0.id == id }
    }

    var hasActiveFilters: Bool {
        !searchText.isEmpty || filterMsgType != nil || filterSide != nil || filterStatus != nil
    }

    var filterSummary: String {
        let total = allMessages.count
        guard total > 0 else { return "" }
        let shown = displayedMessages.count
        if shown == total { return "\(total) messages" }
        return "\(shown) of \(total)"
    }

    /// Distinct MsgType values present in allMessages, for the Type filter picker
    var availableMsgTypes: [(type: String, name: String)] {
        var seen = Set<String>()
        return allMessages.compactMap { msg in
            guard let t = msg.msgType, seen.insert(t).inserted else { return nil }
            return (type: t, name: msg.msgTypeName)
        }
        .sorted { $0.name < $1.name }
    }

    // MARK: - Actions

    func clearFilters() {
        searchText = ""
        filterMsgType = nil
        filterSide = nil
        filterStatus = nil
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
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            addToRecentFiles(url)
            sourceFilename = url.lastPathComponent
            rawInput = content.utf8.count < 500_000 ? content : ""
            await runStreamingParse(content)
        } catch {
            errorMessage = "Could not read file: \(error.localizedDescription)"
        }
    }

    func clear() {
        filterTask?.cancel()
        rawInput = ""
        allMessages = []
        displayedMessages = []
        selectedMessageID = nil
        sourceFilename = nil
        parseProgress = 0
        isFiltering = false
        searchText = ""
        filterMsgType = nil
        filterSide = nil
        filterStatus = nil
    }

    // MARK: - Private

    private func addToRecentFiles(_ url: URL) {
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
        var paths = UserDefaults.standard.stringArray(forKey: "fixlens.recentFiles") ?? []
        paths.removeAll { $0 == url.path }
        paths.insert(url.path, at: 0)
        UserDefaults.standard.set(Array(paths.prefix(10)), forKey: "fixlens.recentFiles")
    }

    private func runStreamingParse(_ content: String) async {
        isParsing = true
        parseProgress = 0
        allMessages = []
        displayedMessages = []
        selectedMessageID = nil
        let dict = dictionary
        for await update in FIXParser.stream(content, dictionary: dict) {
            // Update allMessages and displayedMessages as two sequential (non-nested)
            // @Observable mutations so SwiftUI sees a single batched render, not a
            // nested withMutation that triggers reentrant NSTableView delegate calls.
            allMessages.append(contentsOf: update.batch)
            let visible = showAdminMessages
                ? update.batch
                : update.batch.filter { !$0.isAdmin }
            displayedMessages.append(contentsOf: visible)
            parseProgress = update.progress
        }
        isParsing = false
        parseProgress = 1.0
        scheduleFilter()  // apply full active filters after streaming completes
    }

    private func scheduleFilter() {
        filterTask?.cancel()
        let messages = allMessages
        let showAdmin = showAdminMessages
        let search = searchText.lowercased()
        let msgType = filterMsgType
        let side = filterSide
        let status = filterStatus

        isFiltering = true
        filterTask = Task {
            if !search.isEmpty {
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled else { return }
            }
            let result: [FIXMessage] = await Task.detached {
                messages.filter { msg in
                    if !showAdmin && msg.isAdmin { return false }
                    if let t = msgType, msg.msgType != t { return false }
                    if let s = side, msg.side != s { return false }
                    if let st = status, msg.ordStatus != st { return false }
                    if !search.isEmpty {
                        return msg.msgTypeName.lowercased().contains(search)
                            || (msg.symbol?.lowercased().contains(search) ?? false)
                            || (msg.securityID?.lowercased().contains(search) ?? false)
                            || (msg.clOrdID?.lowercased().contains(search) ?? false)
                            || msg.sessionDisplay.lowercased().contains(search)
                    }
                    return true
                }
            }.value
            guard !Task.isCancelled else { return }
            self.displayedMessages = result
            self.isFiltering = false
        }
    }
}
