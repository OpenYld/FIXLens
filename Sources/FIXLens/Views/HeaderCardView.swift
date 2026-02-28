import SwiftUI

struct HeaderCardView: View {
    let message: FIXMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {

            // ── Top row: type name + timestamp ────────────────────────────
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(message.msgTypeName)
                        .font(.title2.bold())
                        .foregroundStyle(message.category.color)

                    HStack(spacing: 6) {
                        if let mt = message.msgType {
                            Text("35=\(mt)")
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                        Text(message.category.label)
                            .font(.caption)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(message.category.color.opacity(0.12))
                            .foregroundStyle(message.category.color)
                            .clipShape(Capsule())
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 3) {
                    Text(message.sendingTime ?? "—")
                        .font(.body.monospaced())
                    if let seq = message.seqNum {
                        Text("Seq# \(seq)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Divider()

            // ── Session ───────────────────────────────────────────────────
            LabeledRow(label: "Session", systemImage: "arrow.left.arrow.right") {
                Text(message.sessionDisplay)
                    .font(.body.monospaced())
            }

            // ── Trading fields grid (only if any are present) ─────────────
            let tradingRows = makeTradingRows()
            if !tradingRows.isEmpty {
                Divider()
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), alignment: .leading),
                        GridItem(.flexible(), alignment: .leading),
                        GridItem(.flexible(), alignment: .leading),
                    ],
                    alignment: .leading,
                    spacing: 8
                ) {
                    ForEach(tradingRows) { row in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.label)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(row.value)
                                .font(.body.bold())
                                .foregroundStyle(row.color)
                        }
                    }
                }
            }

            // ── Free-text field ───────────────────────────────────────────
            if let text = message.text {
                Divider()
                Text("\"\(text)\"")
                    .font(.callout.italic())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(.separator, lineWidth: 0.5)
        )
    }

    // MARK: - Trading rows

    private struct TradingRow: Identifiable {
        let id = UUID()
        let label: String
        let value: String
        let color: Color
    }

    private func makeTradingRows() -> [TradingRow] {
        var rows: [TradingRow] = []

        if let v = message.symbol {
            rows.append(TradingRow(label: "Symbol", value: v, color: .primary))
        }
        if let v = message.sideDisplay ?? message.side {
            let c: Color = message.side == "1" ? .blue : (message.side == "2" ? .red : .primary)
            rows.append(TradingRow(label: "Side", value: v, color: c))
        }
        if let v = message.orderQty {
            rows.append(TradingRow(label: "Qty", value: v, color: .primary))
        }
        if let v = message.price {
            rows.append(TradingRow(label: "Price", value: v, color: .primary))
        }
        if let v = message.ordStatusDisplay ?? message.ordStatus {
            let c: Color = message.ordStatus == "2" ? .green : (message.ordStatus == "8" ? .red : .primary)
            rows.append(TradingRow(label: "Status", value: v, color: c))
        }
        if let v = message.clOrdID {
            rows.append(TradingRow(label: "ClOrdID", value: v, color: .secondary))
        }
        if let v = message.execTypeDisplay ?? message.execType {
            rows.append(TradingRow(label: "ExecType", value: v, color: .primary))
        }

        return rows
    }
}

// MARK: - Helper view

private struct LabeledRow<Content: View>: View {
    let label: String
    let systemImage: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(spacing: 8) {
            Label(label, systemImage: systemImage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 90, alignment: .leading)
            content()
            Spacer(minLength: 0)
        }
    }
}
