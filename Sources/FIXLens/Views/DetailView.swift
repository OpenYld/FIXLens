import SwiftUI

// DetailView is always present in the layout (never swapped out).
// It accepts an optional message so the view tree — and therefore
// all split-pane positions — stay completely stable when the
// timeline selection changes.
struct DetailView: View {
    let message: FIXMessage?
    var isLoading: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // ── Header bar ────────────────────────────────────────────────
            HStack(spacing: 8) {
                Image(systemName: "list.bullet.indent")
                    .foregroundStyle(.secondary)
                Text("Detail")
                    .font(.subheadline)
                    .bold()
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.bar)

            Divider()

            VSplitView {
                // ── Top: field table ──────────────────────────────────────────
                FieldTableView(message: message)
                    .frame(maxWidth: .infinity, minHeight: 200, maxHeight: .infinity)

                // ── Bottom: header summary card ───────────────────────────────
                ScrollView {
                    if let msg = message {
                        HeaderCardView(message: msg)
                            .padding(12)
                    } else {
                        emptyCard
                            .padding(12)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 60, maxHeight: 400)
                .background(.background)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var emptyCard: some View {
        VStack(spacing: 10) {
            if isLoading {
                ProgressView()
                Text("Loading message…")
                    .foregroundStyle(.tertiary)
                    .font(.callout)
            } else {
                Image(systemName: "text.badge.checkmark")
                    .font(.system(size: 32))
                    .foregroundStyle(.quaternary)
                Text("No message selected")
                    .foregroundStyle(.tertiary)
                    .font(.callout)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 100)
    }
}
