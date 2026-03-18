import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var viewModel = AppViewModel()
    @State private var isFileImporterPresented = false
    @State private var isColumnPickerPresented = false
    /// Starts narrow to force HSplitView's initial position, then opens up after layout.
    @State private var detailMaxWidth: CGFloat = 300

    var body: some View {
        @Bindable var vm = viewModel

        HSplitView {
            // ── Left: input (file mode hides it), timeline below ──────────
            VStack(spacing: 0) {
                if viewModel.sourceFilename == nil {
                    PasteInputView(viewModel: viewModel)
                        .frame(height: 160)
                }

                TimelineView(viewModel: viewModel)
                    .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(minWidth: 400, maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(NSColor.windowBackgroundColor))

            // ── Right: detail panel, always present, full window height ───
            DetailView(message: viewModel.selectedMessage, isLoading: viewModel.isLoadingDetail)
                .frame(minWidth: 200, idealWidth: 280, maxWidth: detailMaxWidth, maxHeight: .infinity)
                .background(Color(NSColor.controlBackgroundColor))
                .onAppear {
                    // After initial layout (detail starts at ≤300pt), open the
                    // max so the user can drag it wider without fighting the cap.
                    DispatchQueue.main.async { detailMaxWidth = 560 }
                }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(viewModel.sourceFilename ?? "FIXLens")
        .searchable(text: $vm.searchText, placement: .toolbar, prompt: "Search messages…")

        // MARK: - Toolbar
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isFileImporterPresented = true
                } label: {
                    Label("Open Log File", systemImage: "folder")
                }
                .help("Open a FIX log file (⌘O)")
            }

            ToolbarItemGroup(placement: .automatic) {
                if !viewModel.filterSummary.isEmpty {
                    Text(viewModel.filterSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                // ── Live mode controls ────────────────────────────────────
                if viewModel.viewMode == .live {
                    // Pause / resume tailing
                    Button {
                        if viewModel.tailingPaused {
                            viewModel.resumeTailing()
                        } else {
                            viewModel.pauseTailing()
                        }
                    } label: {
                        Label(
                            viewModel.tailingPaused ? "Resume Tail" : "Pause Tail",
                            systemImage: viewModel.tailingPaused ? "play.circle" : "pause.circle"
                        )
                    }
                    .help(viewModel.tailingPaused
                          ? "Resume watching file for new messages"
                          : "Pause watching file for new messages")
                    .disabled(viewModel.tailFileGone)

                    // Auto-scroll toggle
                    Toggle(isOn: Binding(
                        get: { viewModel.autoScroll },
                        set: { viewModel.autoScroll = $0 }
                    )) {
                        Label(
                            "Auto-scroll",
                            systemImage: viewModel.autoScroll
                                ? "arrow.down.to.line"
                                : "arrow.down.to.line.compact"
                        )
                    }
                    .toggleStyle(.button)
                    .help(viewModel.autoScroll
                          ? "Auto-scroll is on — new messages scroll into view (click to disable)"
                          : "Auto-scroll is off — click to scroll to new messages automatically")
                }

                // Column chooser
                Button {
                    isColumnPickerPresented.toggle()
                } label: {
                    Label("Columns", systemImage: "table.badge.more")
                }
                .help("Choose which columns to display")
                .popover(isPresented: $isColumnPickerPresented, arrowEdge: .bottom) {
                    ColumnPickerView()
                }

                // Show/hide admin
                Toggle(isOn: Binding(
                    get: { viewModel.showAdminMessages },
                    set: { viewModel.showAdminMessages = $0 }
                )) {
                    Label(
                        viewModel.showAdminMessages ? "Hide Admin" : "Show Admin",
                        systemImage: viewModel.showAdminMessages ? "eye.slash" : "eye"
                    )
                }
                .toggleStyle(.button)
                .help("Toggle admin messages (Heartbeats, Logon/Logout, etc.)")
                .disabled(viewModel.allSummaries.isEmpty)
            }
        }

        // MARK: - File importer
        .fileImporter(
            isPresented: $isFileImporterPresented,
            allowedContentTypes: [.text, .plainText, .data],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    Task { await viewModel.loadFromURL(url) }
                }
            case .failure(let error):
                viewModel.errorMessage = error.localizedDescription
            }
        }

        // MARK: - Error alert
        .alert(
            "Error",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            ),
            presenting: viewModel.errorMessage
        ) { _ in
            Button("OK") { viewModel.errorMessage = nil }
        } message: { msg in
            Text(msg)
        }

        // MARK: - Startup
        .task {
            await viewModel.loadDictionary()
        }
        .focusedSceneValue(\.appViewModel, viewModel)
    }
}
