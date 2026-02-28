import SwiftUI
import AppKit

struct AboutView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 128, height: 128)

            Text("FIXLens")
                .font(.largeTitle)
                .bold()

            Text("Version 1.0")
                .foregroundStyle(.secondary)

            Text("By Hilton Lipschitz")
                .foregroundStyle(.secondary)

            Link("openyld.com", destination: URL(string: "https://openyld.com")!)

            Text("© 2025 Hilton Lipschitz. All rights reserved.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(32)
        .frame(width: 320)
    }
}
