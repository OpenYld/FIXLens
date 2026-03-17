import SwiftUI
import AppKit

struct AboutView: View {
    @Environment(\.colorScheme) private var colorScheme

    private var logoImage: NSImage? {
        let name = colorScheme == .dark ? "logo-white" : "logo-color"
        guard let url = Bundle.module.url(forResource: name, withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }

    var body: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 128, height: 128)

            Text("FIXLens")
                .font(.largeTitle)
                .bold()

            Text("Version 1.0.1")
                .foregroundStyle(.secondary)

            Text("By Hilton Lipschitz and Claude Code")
                .foregroundStyle(.secondary)

            Divider()
                .padding(.horizontal, 16)

            if let img = logoImage {
                Image(nsImage: img)
                    .resizable()
                    .frame(width: 280, height: 78)
                    .padding(.vertical, 4)
            }

            Link("openyld.com", destination: URL(string: "https://openyld.com")!)

            Text("© 2026 OpenYield Inc. All rights reserved.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(32)
        .frame(width: 360)
    }
}
