import SwiftUI

extension MessageCategory {

    /// Foreground text color for timeline rows and badges
    var color: Color {
        switch self {
        case .admin:           return .secondary
        case .newOrder:        return .blue
        case .executionReport: return .teal
        case .cancelRequest:   return .orange
        case .cancelReplace:   return .purple
        case .orderReject:     return .red
        case .allocation:      return .cyan
        case .marketData:      return .indigo
        case .quote:           return .orange
        case .quoteAck:        return .teal
        case .other:           return .primary
        }
    }

    /// Subtle background tint for timeline rows
    var rowTint: Color {
        switch self {
        case .admin:           return Color.gray.opacity(0.04)
        case .newOrder:        return Color.blue.opacity(0.06)
        case .executionReport: return Color.teal.opacity(0.06)
        case .cancelRequest:   return Color.orange.opacity(0.06)
        case .cancelReplace:   return Color.purple.opacity(0.06)
        case .orderReject:     return Color.red.opacity(0.08)
        case .allocation:      return Color.cyan.opacity(0.06)
        case .marketData:      return Color.indigo.opacity(0.05)
        case .quote:           return Color.orange.opacity(0.05)
        case .quoteAck:        return Color.teal.opacity(0.06)
        case .other:           return Color.clear
        }
    }

    /// Short label for badges / chips
    var label: String {
        switch self {
        case .admin:           return "Admin"
        case .newOrder:        return "Order"
        case .executionReport: return "Exec"
        case .cancelRequest:   return "Cancel"
        case .cancelReplace:   return "Replace"
        case .orderReject:     return "Reject"
        case .allocation:      return "Alloc"
        case .marketData:      return "MktData"
        case .quote:           return "Quote"
        case .quoteAck:        return "QuoteAck"
        case .other:           return "Other"
        }
    }
}
