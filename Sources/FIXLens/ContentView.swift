import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var viewModel = AppViewModel()
    @State private var isFileImporterPresented = false
    @State private var isColumnPickerPresented = false
    @State private var isDragTargeted = false
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

            // ── Message count (informational) ─────────────────────────────
            ToolbarItem(placement: .automatic) {
                if !viewModel.filterSummary.isEmpty {
                    Text(viewModel.filterSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            // ── Live mode controls (only visible while tailing) ───────────
            ToolbarItemGroup(placement: .automatic) {
                if viewModel.viewMode == .live {
                    Divider()

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
            }

            // ── Persistent view controls ──────────────────────────────────
            ToolbarItemGroup(placement: .automatic) {
                Divider()

                Button {
                    isColumnPickerPresented.toggle()
                } label: {
                    Label("Columns", systemImage: "table.badge.more")
                }
                .help("Choose which columns to display")
                .popover(isPresented: $isColumnPickerPresented, arrowEdge: .bottom) {
                    ColumnPickerView()
                }

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

                Toggle(isOn: $viewModel.showLocalTime) {
                    Label(
                        viewModel.showLocalTime ? "Local Time" : "UTC Time",
                        systemImage: viewModel.showLocalTime ? "clock" : "globe"
                    )
                }
                .toggleStyle(.button)
                .help("Toggle timeline between UTC and local PC time")
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

        // MARK: - File drop (whole window)
        .onDrop(of: [.fileURL], isTargeted: $isDragTargeted) { providers in
            guard let provider = providers.first else { return false }
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
                let url: URL? = {
                    if let data = item as? Data { return URL(dataRepresentation: data, relativeTo: nil) }
                    if let nsurl = item as? NSURL { return nsurl as URL }
                    return nil
                }()
                guard let url else { return }
                Task { @MainActor in await viewModel.loadFromURL(url) }
            }
            return true
        }
        .overlay {
            if isDragTargeted {
                ZStack {
                    Color.accentColor.opacity(0.12)
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Color.accentColor, lineWidth: 3)
                        .padding(16)
                    VStack(spacing: 12) {
                        Image(systemName: "doc.badge.plus")
                            .font(.system(size: 52))
                        Text("Drop FIX Log File")
                            .font(.title2.bold())
                    }
                    .foregroundStyle(Color.accentColor)
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)
            }
        }

        // MARK: - Dock-icon / Finder open
        .onReceive(NotificationCenter.default.publisher(for: .openFileRequest)) { note in
            guard let url = note.object as? URL else { return }
            Task { await viewModel.loadFromURL(url) }
        }

        // MARK: - Startup
        .task {
            await viewModel.loadDictionary()
        }
        .focusedSceneValue(\.appViewModel, viewModel)
    }
}
