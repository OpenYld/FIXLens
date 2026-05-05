import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Focused value key

extension FocusedValues {
    @Entry var appViewModel: AppViewModel? = nil
}

// MARK: - Menu commands

struct FIXLensCommands: Commands {
    @FocusedValue(\.appViewModel) private var viewModel: AppViewModel?
    let openNewWindow: () -> Void
    let openAboutWindow: () -> Void

    var body: some Commands {
        // ── App menu (About) ───────────────────────────────────────────────
        CommandGroup(replacing: .appInfo) {
            Button("About FIXLens") { openAboutWindow() }
        }

        // ── File menu ─────────────────────────────────────────────────────
        CommandGroup(replacing: .newItem) {
            Button("New Window") { openNewWindow() }
                .keyboardShortcut("n", modifiers: .command)

            Divider()

            Button("Open Log File…") {
                openFilePanel()
            }
            .keyboardShortcut("o", modifiers: .command)

            Menu("Open Recent") {
                if recentURLs.isEmpty {
                    Text("No Recent Files")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(recentURLs, id: \.self) { url in
                        Button(url.lastPathComponent) {
                            guard let vm = viewModel else { return }
                            Task { await vm.loadFromURL(url) }
                        }
                    }
                    Divider()
                    Button("Clear Menu") {
                        NSDocumentController.shared.clearRecentDocuments(nil)
                    }
                }
            }

            Divider()

            Button(viewModel?.sourceFilename != nil ? "Close File" : "Clear") {
                viewModel?.clear()
            }
            .keyboardShortcut("w", modifiers: .command)
            .disabled(
                viewModel == nil ||
                (viewModel?.rawInput.isEmpty == true &&
                 viewModel?.allSummaries.isEmpty == true)
            )
        }

        // ── Help menu ─────────────────────────────────────────────────────
        CommandGroup(replacing: .help) {
            Button("FIXLens Help") { openAboutWindow() }
        }

        // ── Edit menu: expose Find shortcut so it's discoverable ─────────
        // SwiftUI's .searchable already responds to ⌘F via the responder chain.
        // This entry makes the shortcut visible so users can discover it.
        CommandGroup(after: .pasteboard) {
            Divider()
            Button("Find…") {
                // .searchable handles focus via the responder chain; no explicit action needed.
            }
            .keyboardShortcut("f", modifiers: .command)
        }

        // ── View menu ─────────────────────────────────────────────────────
        CommandGroup(after: .toolbar) {
            Divider()
            Toggle(
                "Show Admin Messages",
                isOn: Binding(
                    get: { viewModel?.showAdminMessages ?? false },
                    set: { viewModel?.showAdminMessages = $0 }
                )
            )
            .keyboardShortcut("a", modifiers: [.command, .shift])
            .disabled(viewModel?.allSummaries.isEmpty ?? true)
            Toggle(
                "Show Local Time",
                isOn: Binding(
                    get: { viewModel?.showLocalTime ?? false },
                    set: { viewModel?.showLocalTime = $0 }
                )
            )
            .keyboardShortcut("t", modifiers: [.command, .shift])
            .disabled(viewModel?.allSummaries.isEmpty ?? true)
        }
    }

    private var recentURLs: [URL] {
        NSDocumentController.shared.recentDocumentURLs
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    @MainActor
    private func openFilePanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.text, .plainText, .data]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let vm = viewModel else { return }
        Task { await vm.loadFromURL(url) }
    }
}

// MARK: - App delegate (SPM activation fix)

private class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }
        NotificationCenter.default.post(name: .openFileRequest, object: url)
    }
}

// MARK: - App

@main
struct FIXLensApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        WindowGroup("FIXLens", id: "main") {
            ContentView()
        }
        .defaultSize(width: 1300, height: 850)
        .commands {
            FIXLensCommands(
                openNewWindow: { openWindow(id: "main") },
                openAboutWindow: { openWindow(id: "about") }
            )
        }

        Window("About FIXLens", id: "about") {
            AboutView()
        }
        .windowResizability(.contentSize)

        Settings {
            FIXLensSettingsView()
        }
    }
}

// MARK: - Settings view

private struct FIXLensSettingsView: View {
    @AppStorage("fixlens.showLocalTime") private var showLocalTime = false
    @AppStorage("fixlens.showAdmin")     private var showAdmin     = false
    @AppStorage("fixlens.autoScroll")    private var autoScroll    = false

    var body: some View {
        Form {
            Section("Display") {
                Toggle("Show local time (instead of UTC)", isOn: $showLocalTime)
                Toggle("Show admin messages by default", isOn: $showAdmin)
            }
            Section("Live Mode") {
                Toggle("Auto-scroll to newest message", isOn: $autoScroll)
            }
        }
        .formStyle(.grouped)
        .frame(width: 360)
        .padding()
    }
}
