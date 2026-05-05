import SwiftUI
import AppKit

struct TimelineView: View {
    @Bindable var viewModel: AppViewModel
    @AppStorage("fixlens.columns") private var columnsRaw: String = ColumnRegistry.defaultEnabled
    /// Local selection state decouples the Table's NSTableView from the @Observable
    /// viewModel, preventing reentrant NSTableView delegate calls when the selection
    /// binding write triggers an immediate @Observable notification during the
    /// NSTableView selection-change callback.
    @State private var selection: FIXMessageSummary.ID?
    /// Tracks whether the table is currently scrolled to (or near) the bottom row.
    /// Auto-scroll only fires when true, so a user reading history is never hijacked.
    @State private var isAtBottom = true
    @Environment(\.colorScheme) private var colorScheme

    private var logoImage: NSImage? {
        let name = colorScheme == .dark ? "logo-white" : "logo-color"
        guard let url = Bundle.module.url(forResource: name, withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }

    private var cols: Set<String> {
        Set(columnsRaw.split(separator: ",").map(String.init))
    }

    var body: some View {
        let summaries = viewModel.displayedSummaries

        VStack(spacing: 0) {
            // ── Header bar ────────────────────────────────────────────────
            HStack(spacing: 8) {
                if viewModel.sourceFilename != nil, let img = logoImage {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 20)
                } else {
                    Image(systemName: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                        .foregroundStyle(.secondary)
                }
                Text("Timeline")
                    .font(.subheadline)
                    .bold()
                Spacer()

                // Mode badge
                if viewModel.isTailing {
                    LiveIndicatorView()
                } else if viewModel.viewMode == .analysis {
                    Label("Analysis", systemImage: "doc.text.magnifyingglass")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.bar)

            Divider()

            // File-gone banner (log rotation / deletion)
            if viewModel.tailFileGone {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("File was removed or rotated — tailing stopped.")
                        .font(.caption)
                    Spacer()
                    Button("Reload") { viewModel.reloadFile() }
                        .font(.caption)
                        .buttonStyle(.borderless)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.orange.opacity(0.12))

                Divider()
            }

            // Progress bar (during parse / index)
            if viewModel.isParsing {
                ProgressView(value: viewModel.parseProgress)
                    .progressViewStyle(.linear)
                    .frame(height: 2)
                    .padding(.horizontal, 0)
            }

            // Filter bar (when messages exist or filters are active)
            if !viewModel.allSummaries.isEmpty || viewModel.hasActiveFilters {
                FilterBarView(viewModel: viewModel)
                Divider()
            }

            // ── Content ───────────────────────────────────────────────────
            if summaries.isEmpty {
                emptyState
            } else {
                Table(summaries, selection: $selection) {

                    // ── Always visible ────────────────────────────────────
                    TableColumn("Time") { (msg: FIXMessageSummary) in
                        Text(msg.displayTime(local: viewModel.showLocalTime))
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(msg.category.color)
                    }
                    .width(min: 65, ideal: 90)

                    TableColumn("Type") { msg in
                        HStack(spacing: 5) {
                            if tradeExecDotColor(msg.execType) != nil {
                                Circle()
                                    .fill(msg.category.color)
                                    .frame(width: 7, height: 7)
                            }
                            Text(msg.msgTypeName)
                                .bold()
                                .lineLimit(1)
                                .foregroundStyle(msg.category.color)
                        }
                        .draggable(viewModel.rawText(for: msg.id) ?? msg.tradingSummary ?? msg.msgTypeName)
                    }
                    .width(min: 80, ideal: 120)

                    // ── Toggleable ────────────────────────────────────────
                    if cols.contains("session") {
                        TableColumn("Session") { msg in
                            Text(msg.sessionDisplay)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .width(min: 80, ideal: 150)
                    }

                    if cols.contains("symbol") {
                        TableColumn("SecurityID") { msg in
                            Text(msg.securityID ?? "")
                                .bold()
                        }
                        .width(min: 50, ideal: 80)
                    }

                    if cols.contains("side") {
                        TableColumn("Side") { msg in
                            Text(msg.sideDisplay ?? msg.side ?? "")
                                .bold()
                                .foregroundStyle(sideColor(msg.side))
                        }
                        .width(min: 40, ideal: 70, max: 80)
                    }

                    if cols.contains("qty") {
                        TableColumn("Qty") { msg in
                            Text(msg.orderQty ?? "")
                                .font(.system(.body, design: .monospaced))
                        }
                        .width(min: 50, ideal: 80)
                    }

                    if cols.contains("price") {
                        TableColumn("Price") { msg in
                            Text(msg.price ?? "")
                                .font(.system(.body, design: .monospaced))
                        }
                        .width(min: 50, ideal: 80)
                    }

                    if cols.contains("ordStatus") {
                        TableColumn("Status") { msg in
                            Text(msg.ordStatusDisplay ?? msg.ordStatus ?? "")
                                .foregroundStyle(statusColor(msg.ordStatus))
                        }
                        .width(min: 70, ideal: 110)
                    }

                    if cols.contains("summary") {
                        TableColumn("Summary") { msg in
                            Text(msg.tradingSummary ?? "")
                                .lineLimit(1)
                                .textSelection(.enabled)
                        }
                        // no width — takes remaining space
                    }

                    if cols.contains("clOrdID") {
                        TableColumn("ClOrdID") { msg in
                            Text(msg.clOrdID ?? "")
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .width(min: 80, ideal: 150)
                    }
                }
                .tableStyle(.inset(alternatesRowBackgrounds: true))
                .onCopyCommand {
                    guard let id = selection,
                          let msg = viewModel.allSummaries.first(where: { $0.id == id }) else { return [] }
                    let text = viewModel.rawText(for: id) ?? msg.tradingSummary ?? msg.msgTypeName
                    return [NSItemProvider(object: text as NSString)]
                }
                .contextMenu(forSelectionType: FIXMessageSummary.ID.self) { ids in
                    if let id = ids.first,
                       let msg = viewModel.allSummaries.first(where: { $0.id == id }) {
                        if let summary = msg.tradingSummary {
                            Button("Copy Summary") { copyToPasteboard(summary) }
                        }
                        if let raw = viewModel.rawText(for: id) {
                            Button("Copy Raw FIX Message") { copyToPasteboard(raw) }
                        }
                        if msg.securityID != nil || msg.clOrdID != nil {
                            Divider()
                        }
                        if let v = msg.securityID {
                            Button("Copy SecurityID: \(v)") { copyToPasteboard(v) }
                        }
                        if let v = msg.clOrdID {
                            Button("Copy ClOrdID: \(v)") { copyToPasteboard(v) }
                        }
                    }
                }
                // Sync local selection → viewModel (user clicked a row)
                .onChange(of: selection) { _, newID in
                    viewModel.selectedMessageID = newID
                }
                // Sync viewModel → local selection (external reset, e.g. clear/new file)
                .onChange(of: viewModel.selectedMessageID) { _, newID in
                    if selection != newID { selection = newID }
                }
                // Inject the scroll position observer so we know when the user
                // manually scrolls away from the bottom (pausing auto-scroll).
                .background(
                    ScrollPositionObserver(isAtBottom: $isAtBottom)
                        .frame(width: 0, height: 0)
                        .allowsHitTesting(false)
                )
                // Fire auto-scroll only when: toggle on + no selection + actually at bottom.
                .onReceive(NotificationCenter.default.publisher(for: .scrollToBottom)) { _ in
                    guard viewModel.autoScroll,
                          viewModel.selectedMessageID == nil,
                          isAtBottom else { return }
                    scrollToBottom()
                }
                // When the auto-scroll toggle is flipped on, jump to the bottom immediately
                // so the user is back at the live edge. This also resets isAtBottom.
                .onChange(of: viewModel.autoScroll) { _, newValue in
                    if newValue { scrollToBottom() }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Scroll helpers

    private func scrollToBottom() {
        guard !viewModel.displayedSummaries.isEmpty,
              let window = NSApp.keyWindow,
              let tableView = findTableView(in: window.contentView) else { return }
        let lastRow = tableView.numberOfRows - 1
        guard lastRow >= 0 else { return }
        tableView.scrollRowToVisible(lastRow)
        isAtBottom = true   // mark immediately; observer will confirm asynchronously
    }

    private func findTableView(in view: NSView?) -> NSTableView? {
        guard let view else { return nil }
        if let tv = view as? NSTableView { return tv }
        for sub in view.subviews {
            if let found = findTableView(in: sub) { return found }
        }
        return nil
    }

    // MARK: - Empty state

    @ViewBuilder
    private var emptyState: some View {
        if viewModel.isParsing {
            VStack(spacing: 10) {
                ProgressView()
                Text(viewModel.viewMode == .analysis ? "Indexing messages…" : "Parsing messages…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.allSummaries.isEmpty {
            ContentUnavailableView(
                "No Messages",
                systemImage: "doc.text.magnifyingglass",
                description: Text("Paste raw FIX text above and press **⌘↩ Parse**, or open a log file with **⌘O**")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.hasActiveFilters {
            ContentUnavailableView(
                "No Matching Messages",
                systemImage: "magnifyingglass",
                description: Text("No messages match the active filters or search.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ContentUnavailableView(
                "Admin Messages Hidden",
                systemImage: "eye.slash",
                description: Text("All messages are admin messages. Enable **Show Admin** in the toolbar to display them.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Color helpers

    private func tradeExecDotColor(_ execType: String?) -> Color? {
        switch execType {
        case "F": return .green
        case "G": return .orange
        case "H": return .red
        default:  return nil
        }
    }

    private func sideColor(_ side: String?) -> Color {
        switch side {
        case "1": return .blue
        case "2": return .red
        case "5", "6": return .orange
        default: return .primary
        }
    }

    private func statusColor(_ status: String?) -> Color {
        switch status {
        case "2": return .green
        case "8": return .red
        case "4": return .orange
        case "1": return .teal
        default: return .primary
        }
    }
}

// MARK: - Scroll position observer

/// A zero-size transparent NSViewRepresentable that locates the enclosing
/// NSScrollView (the one wrapping the Table's NSTableView) and observes its
/// clip-view bounds changes to determine whether the list is scrolled to the
/// bottom row or not.
///
/// `isAtBottom` is set to `false` whenever the user scrolls the table away from
/// the last row, and back to `true` when they scroll down to the end. The
/// auto-scroll mechanism in TimelineView reads this binding before deciding
/// whether to jump to the newest message.
private struct ScrollPositionObserver: NSViewRepresentable {
    @Binding var isAtBottom: Bool

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        view.isHidden = true
        let coordinator = context.coordinator
        // Defer until the view is actually placed in the window hierarchy.
        Task { @MainActor in coordinator.findAndAttach(from: view) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // Keep the binding reference current across SwiftUI re-renders.
        context.coordinator.binding = $isAtBottom
    }

    func makeCoordinator() -> Coordinator { Coordinator(binding: $isAtBottom) }

    // MARK: Coordinator

    @MainActor
    final class Coordinator: NSObject {
        var binding: Binding<Bool>
        private weak var scrollView: NSScrollView?

        init(binding: Binding<Bool>) { self.binding = binding }

        deinit {
            // Safe: selector-based removal only needs `self` as a key, no type issues.
            NotificationCenter.default.removeObserver(self)
        }

        /// Walk the window's view hierarchy to find the NSScrollView that wraps
        /// an NSTableView, then subscribe to its clip-view bounds changes.
        func findAndAttach(from anchorView: NSView) {
            let window = anchorView.window ?? NSApp.keyWindow
            if let sv = findScrollViewWithTable(in: window?.contentView) {
                attach(to: sv)
            } else {
                // Retry — the Table may not be in the hierarchy yet.
                Task { @MainActor [weak self, weak anchorView] in
                    try? await Task.sleep(for: .milliseconds(300))
                    guard let self, let anchor = anchorView else { return }
                    self.findAndAttach(from: anchor)
                }
            }
        }

        private func findScrollViewWithTable(in view: NSView?) -> NSScrollView? {
            guard let view else { return nil }
            if let sv = view as? NSScrollView, sv.documentView is NSTableView { return sv }
            for sub in view.subviews {
                if let found = findScrollViewWithTable(in: sub) { return found }
            }
            return nil
        }

        private func attach(to sv: NSScrollView) {
            scrollView = sv
            // postsBoundsChangedNotifications fires for ALL scroll events —
            // both user-initiated and programmatic — giving us reliable position tracking.
            sv.contentView.postsBoundsChangedNotifications = true
            // Selector-based observation avoids Sendable token capture issues in deinit.
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(boundsChanged),
                name: NSView.boundsDidChangeNotification,
                object: sv.contentView
            )
        }

        @objc private func boundsChanged() {
            guard let sv = scrollView,
                  let docHeight = sv.documentView?.bounds.height else { return }
            let clip = sv.contentView.bounds
            let visibleBottom = clip.origin.y + clip.height
            // 10 pt tolerance handles fractional pixel differences at the very bottom.
            let atBottom = visibleBottom >= docHeight - 10
            if binding.wrappedValue != atBottom {
                binding.wrappedValue = atBottom
            }
        }
    }
}

// MARK: - Live indicator

private struct LiveIndicatorView: View {
    @State private var pulsing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(.green)
                .frame(width: 7, height: 7)
                .scaleEffect(pulsing ? 1.4 : 1.0)
                .animation(
                    reduceMotion ? nil : .easeInOut(duration: 0.9).repeatForever(autoreverses: true),
                    value: pulsing
                )
                .onAppear { if !reduceMotion { pulsing = true } }
            Text("Live")
                .font(.caption)
                .bold()
                .foregroundStyle(.green)
        }
        .accessibilityLabel("Live — tailing file")
    }
}

// MARK: - Pasteboard helper

private func copyToPasteboard(_ string: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(string, forType: .string)
}
