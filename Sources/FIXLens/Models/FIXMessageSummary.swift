import Foundation

/// Lightweight summary of a FIX message used as the unified display/filter type
/// for both Live mode (today's small files) and Analysis mode (large/old files).
///
/// In Live mode it is built from a full FIXMessage (byteOffset/byteLength are 0).
/// In Analysis mode it is built directly from raw bytes with a stored file offset,
/// so the full field list can be read on demand without keeping everything in RAM.
struct FIXMessageSummary: Identifiable, Sendable {

    let id: UUID
    let index: Int

    // File position — used in Analysis mode to seek and read the full message.
    // Both are 0 in Live / paste modes.
    let byteOffset: UInt64
    let byteLength: Int

    // Category
    let isAdmin: Bool
    let category: MessageCategory

    // Header fields
    let msgType: String?
    let msgTypeName: String
    let sendingTime: String?
    let seqNum: String?
    let senderCompID: String?
    let targetCompID: String?

    // Trading fields
    let symbol: String?
    let side: String?
    let sideDisplay: String?
    let orderQty: String?
    let price: String?
    let ordStatus: String?
    let ordStatusDisplay: String?
    let clOrdID: String?
    let securityID: String?
    let execType: String?
    let execTypeDisplay: String?
    let text: String?

    // MARK: - Derived display helpers (mirrors FIXMessage)

    var formattedTime: String {
        guard let t = sendingTime else { return "—" }
        if let dash = t.firstIndex(of: "-") {
            return String(t[t.index(after: dash)...])
        }
        return t
    }

    var sessionDisplay: String {
        "\(senderCompID ?? "?") → \(targetCompID ?? "?")"
    }

    var tradingSummary: String? {
        var parts: [String] = []
        if let s = sideDisplay   { parts.append(s) }
        if let q = orderQty      { parts.append(q) }
        if let sym = symbol      { parts.append(sym) }
        if let p = price         { parts.append("@ \(p)") }
        guard !parts.isEmpty else { return nil }
        if let status = ordStatusDisplay ?? ordStatus { parts.append("— \(status)") }
        return parts.joined(separator: " ")
    }
}

// MARK: - Init from FIXMessage

extension FIXMessageSummary {
    init(from message: FIXMessage, byteOffset: UInt64 = 0, byteLength: Int = 0) {
        self.id              = message.id
        self.index           = message.index
        self.byteOffset      = byteOffset
        self.byteLength      = byteLength
        self.isAdmin         = message.isAdmin
        self.category        = message.category
        self.msgType         = message.msgType
        self.msgTypeName     = message.msgTypeName
        self.sendingTime     = message.sendingTime
        self.seqNum          = message.seqNum
        self.senderCompID    = message.senderCompID
        self.targetCompID    = message.targetCompID
        self.symbol          = message.symbol
        self.side            = message.side
        self.sideDisplay     = message.sideDisplay
        self.orderQty        = message.orderQty
        self.price           = message.price
        self.ordStatus       = message.ordStatus
        self.ordStatusDisplay = message.ordStatusDisplay
        self.clOrdID         = message.clOrdID
        self.securityID      = message.securityID
        self.execType        = message.execType
        self.execTypeDisplay = message.execTypeDisplay
        self.text            = message.text
    }
}
