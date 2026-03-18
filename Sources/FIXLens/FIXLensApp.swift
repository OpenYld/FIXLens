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
                        UserDefaults.standard.removeObject(forKey: "fixlens.recentFiles")
                        NSDocumentController.shared.clearRecentDocuments(nil)
                    }
                }
            }

            Divider()

            Button(viewModel?.sourceFilename != nil ? "Close File" : "Clear") {
                viewModel?.clear()
            }
            .disabled(
                viewModel == nil ||
                (viewModel?.rawInput.isEmpty == true &&
                 viewModel?.allSummaries.isEmpty == true)
            )
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
        }
    }

    private var recentURLs: [URL] {
        let paths = UserDefaults.standard.stringArray(forKey: "fixlens.recentFiles") ?? []
        return paths.compactMap { URL(fileURLWithPath: $0) }
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
    }
}
