import SwiftUI

struct PasteInputView: View {
    @Bindable var viewModel: AppViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar bar
            HStack(spacing: 8) {
                Image(systemName: "text.alignleft")
                    .foregroundStyle(.secondary)
                Text("Paste FIX Messages")
                    .font(.subheadline)
                    .bold()

                Spacer()

                if viewModel.isParsing {
                    ProgressView()
                        .controlSize(.small)
                }

                if !viewModel.isDictionaryLoaded {
                    Label("Loading dictionary…", systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button("Clear", systemImage: "xmark.circle") {
                    viewModel.clear()
                }
                .buttonStyle(.borderless)
                .labelStyle(.iconOnly)
                .help("Clear input and results")
                .disabled(viewModel.rawInput.isEmpty && viewModel.allMessages.isEmpty)

                Button("Parse") {
                    viewModel.parseInput()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(viewModel.rawInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                          || viewModel.isParsing
                          || !viewModel.isDictionaryLoaded)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.bar)

            Divider()

            TextEditor(text: $viewModel.rawInput)
                .font(.system(size: 11, design: .monospaced))
                .autocorrectionDisabled()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
