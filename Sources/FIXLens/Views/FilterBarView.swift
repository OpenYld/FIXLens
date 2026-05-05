import SwiftUI

struct FilterBarView: View {
    @Bindable var viewModel: AppViewModel

    var body: some View {
        HStack(spacing: 6) {
            // MsgType picker
            Picker("Type", selection: $viewModel.filterMsgType) {
                Text("All Types").tag(String?.none)
                if !viewModel.availableMsgTypes.isEmpty {
                    Divider()
                    ForEach(viewModel.availableMsgTypes, id: \.type) { item in
                        Text(item.name).tag(String?.some(item.type))
                    }
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .accessibilityLabel("Filter by message type")
            .frame(maxWidth: 130)

            // Side picker
            Picker("Side", selection: $viewModel.filterSide) {
                Text("All Sides").tag(String?.none)
                Divider()
                Text("Buy").tag(String?.some("1"))
                Text("Sell").tag(String?.some("2"))
                Text("Sell Short").tag(String?.some("5"))
                Text("Sell Short Exempt").tag(String?.some("6"))
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .accessibilityLabel("Filter by side")
            .frame(maxWidth: 95)

            // Status picker
            Picker("Status", selection: $viewModel.filterStatus) {
                Text("All Status").tag(String?.none)
                Divider()
                Text("New").tag(String?.some("0"))
                Text("Partial Fill").tag(String?.some("1"))
                Text("Filled").tag(String?.some("2"))
                Text("Canceled").tag(String?.some("4"))
                Text("Replaced").tag(String?.some("5"))
                Text("Rejected").tag(String?.some("8"))
                Text("Pending New").tag(String?.some("A"))
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .accessibilityLabel("Filter by order status")
            .frame(maxWidth: 110)

            Toggle(isOn: $viewModel.filterTradesOnly) {
                Label("Trades", systemImage: "arrow.left.arrow.right.circle.fill")
            }
            .toggleStyle(.button)
            .font(.caption)
            .tint(.teal)
            .help("Show only fills, trade corrections, and trade cancels (ExecType F/G/H)")

            Spacer()

            // Active filter count + clear
            if viewModel.hasActiveFilters {
                Button(action: { viewModel.clearFilters() }) {
                    Label("Clear Filters", systemImage: "xmark.circle.fill")
                }
                .buttonStyle(.borderless)
                .labelStyle(.titleAndIcon)
                .font(.caption)
                .foregroundStyle(.secondary)
                .help("Clear all filters")
            }

            if viewModel.isFiltering {
                ProgressView()
                    .scaleEffect(0.5)
                    .frame(width: 16, height: 16)
            }

            Text(viewModel.filterSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.bar)
    }
}
