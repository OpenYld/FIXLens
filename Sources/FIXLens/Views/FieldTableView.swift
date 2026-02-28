import SwiftUI

struct FieldTableView: View {
    let message: FIXMessage?
    @State private var selectedFieldID: FIXField.ID? = nil

    var body: some View {
        if let msg = message {
            Table(msg.fields, selection: $selectedFieldID) {
                TableColumn("Tag") { field in
                    Text(String(field.tag))
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .width(min: 35, ideal: 42, max: 55)

                TableColumn("Name") { field in
                    Text(field.name)
                        .bold()
                }
                .width(min: 80, ideal: 130)

                TableColumn("Value") { field in
                    Text(field.rawValue)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                }
                .width(min: 70, ideal: 140)

                TableColumn("Description") { field in
                    Text(field.description ?? "")
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                .width(min: 90, ideal: 220)
            }
            .tableStyle(.inset)
            .onChange(of: msg.id) { selectedFieldID = nil }
        } else {
            ContentUnavailableView(
                "Select a Message",
                systemImage: "list.bullet.rectangle",
                description: Text("Click any row in the timeline to inspect its fields.")
            )
        }
    }
}
