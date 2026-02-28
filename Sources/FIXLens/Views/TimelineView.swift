import SwiftUI

struct TimelineView: View {
    @Bindable var viewModel: AppViewModel
    @AppStorage("fixlens.columns") private var columnsRaw: String = ColumnRegistry.defaultEnabled
    /// Local selection state decouples the Table's NSTableView from the @Observable
    /// viewModel, preventing reentrant NSTableView delegate calls when the selection
    /// binding write triggers an immediate @Observable notification during the
    /// NSTableView selection-change callback.
    @State private var selection: FIXMessage.ID?

    private var cols: Set<String> {
        Set(columnsRaw.split(separator: ",").map(String.init))
    }

    var body: some View {
        let messages = viewModel.displayedMessages

        VStack(spacing: 0) {
            // ── Header bar ────────────────────────────────────────────────
            HStack(spacing: 8) {
                Image(systemName: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                    .foregroundStyle(.secondary)
                Text("Timeline")
                    .font(.subheadline)
                    .bold()
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.bar)

            Divider()

            // Progress bar (during parse)
            if viewModel.isParsing {
                ProgressView(value: viewModel.parseProgress)
                    .progressViewStyle(.linear)
                    .frame(height: 2)
                    .padding(.horizontal, 0)
            }

            // Filter bar (when messages exist or filters are active)
            if !viewModel.allMessages.isEmpty || viewModel.hasActiveFilters {
                FilterBarView(viewModel: viewModel)
                Divider()
            }

            // ── Content ───────────────────────────────────────────────────
            if messages.isEmpty {
                emptyState
            } else {
                Table(messages, selection: $selection) {

                    // ── Always visible ────────────────────────────────────
                    TableColumn("Time") { (msg: FIXMessage) in
                        Text(msg.formattedTime)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(msg.category.color)
                    }
                    .width(min: 65, ideal: 90)

                    TableColumn("Type") { msg in
                        Text(msg.msgTypeName)
                            .bold()
                            .lineLimit(1)
                            .foregroundStyle(msg.category.color)
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
                        TableColumn("Symbol") { msg in
                            Text(msg.symbol ?? "")
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
                // Sync local selection → viewModel (user clicked a row)
                .onChange(of: selection) { _, newID in
                    viewModel.selectedMessageID = newID
                }
                // Sync viewModel → local selection (external reset, e.g. clear/new file)
                .onChange(of: viewModel.selectedMessageID) { _, newID in
                    if selection != newID { selection = newID }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Empty state

    @ViewBuilder
    private var emptyState: some View {
        if viewModel.allMessages.isEmpty {
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
