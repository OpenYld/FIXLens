import SwiftUI

// MARK: - Column registry

struct ColumnSpec: Identifiable {
    let id: String       // used as AppStorage key fragment
    let title: String
}

enum ColumnRegistry {
    /// Columns that are always visible (cannot be hidden).
    static let fixed: [ColumnSpec] = [
        ColumnSpec(id: "time",    title: "Time"),
        ColumnSpec(id: "type",    title: "Type"),
    ]

    /// Columns the user can toggle on/off.
    // Max 8 here — Table builder supports 10 total, 2 are always-on (Time, Type).
    static let toggleable: [ColumnSpec] = [
        ColumnSpec(id: "session",   title: "Session"),
        ColumnSpec(id: "symbol",    title: "Symbol"),
        ColumnSpec(id: "side",      title: "Side"),
        ColumnSpec(id: "qty",       title: "Qty"),
        ColumnSpec(id: "price",     title: "Price"),
        ColumnSpec(id: "ordStatus", title: "Status"),
        ColumnSpec(id: "summary",   title: "Summary"),
        ColumnSpec(id: "clOrdID",   title: "ClOrdID"),
    ]

    /// Default enabled set (comma-separated IDs).
    static let defaultEnabled = "session,summary,clOrdID"
}

// MARK: - Picker popover

struct ColumnPickerView: View {
    /// Stored as "id1,id2,id3" in UserDefaults.
    @AppStorage("fixlens.columns") private var raw: String = ColumnRegistry.defaultEnabled

    private var enabled: Set<String> {
        Set(raw.split(separator: ",").map(String.init))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Columns")
                .font(.headline)
                .padding([.horizontal, .top], 12)
                .padding(.bottom, 6)

            Divider()

            VStack(alignment: .leading, spacing: 0) {
                // Fixed columns — shown as disabled toggles so the user knows they exist
                ForEach(ColumnRegistry.fixed) { col in
                    Toggle(col.title, isOn: .constant(true))
                        .disabled(true)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                }

                Divider().padding(.vertical, 4)

                // Toggleable columns
                ForEach(ColumnRegistry.toggleable) { col in
                    Toggle(col.title, isOn: Binding(
                        get: { enabled.contains(col.id) },
                        set: { on in
                            var set = enabled
                            if on { set.insert(col.id) } else { set.remove(col.id) }
                            raw = set.sorted().joined(separator: ",")
                        }
                    ))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                }
            }

            Divider()

            Button("Reset to Defaults") {
                raw = ColumnRegistry.defaultEnabled
            }
            .buttonStyle(.borderless)
            .padding(12)
        }
        .frame(width: 190)
    }
}
