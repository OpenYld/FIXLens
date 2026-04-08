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
    let ordType: String?
    let ordTypeDisplay: String?
    let lastQty: String?
    let lastPx: String?

    // Quote fields
    let bidPx: String?
    let offerPx: String?
    let bidSize: String?
    let offerSize: String?
    let quoteStatus: String?   // tag 297: 0=Accepted/Ack, 1=Cancel

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
        switch category {
        case .admin:
            return text

        case .newOrder:
            var parts: [String] = []
            if let s = sideDisplay                       { parts.append(s) }
            if let q = formatFIXQty(orderQty)            { parts.append(q) }
            if let id = securityID ?? symbol             { parts.append(id) }
            if ordTypeDisplay?.lowercased() == "market" {
                parts.append("[Market]")
            } else if let p = formatFIXPrice(price)      {
                parts.append("@ \(p)")
            }
            return parts.isEmpty ? nil : parts.joined(separator: " ")

        case .executionReport:
            var orderParts: [String] = []
            if let s = sideDisplay                       { orderParts.append(s) }
            if let q = formatFIXQty(orderQty)            { orderParts.append(q) }
            if let id = securityID ?? symbol             { orderParts.append(id) }
            if execType == "1" || execType == "2" || execType == "F" {
                var fill = ["Fill"]
                if let lq = formatFIXQty(lastQty)        { fill.append(lq) }
                if let lp = formatFIXPrice(lastPx)       { fill.append("@ \(lp)") }
                let fillStr = fill.joined(separator: " ")
                let orderStr = orderParts.joined(separator: " ")
                return orderStr.isEmpty ? fillStr : "\(fillStr) — \(orderStr)"
            } else {
                if let p = formatFIXPrice(price)         { orderParts.append("@ \(p)") }
                let orderStr = orderParts.joined(separator: " ")
                if let st = execTypeDisplay ?? ordStatusDisplay ?? ordStatus {
                    return orderStr.isEmpty ? st : "\(st) — \(orderStr)"
                }
                return orderStr.isEmpty ? nil : orderStr
            }

        case .cancelRequest:
            var parts = ["Cancel"]
            if let q = formatFIXQty(orderQty)            { parts.append(q) }
            if let id = securityID ?? symbol             { parts.append(id) }
            return parts.joined(separator: " ")

        case .cancelReplace:
            var parts = ["Replace"]
            if let q = formatFIXQty(orderQty)            { parts.append(q) }
            if let id = securityID ?? symbol             { parts.append(id) }
            if let p = formatFIXPrice(price)             { parts.append("@ \(p)") }
            return parts.joined(separator: " ")

        case .orderReject:
            if let t = text { return "Rejected: \(t)" }
            return "Rejected"

        case .allocation:
            var parts: [String] = []
            if let q = formatFIXQty(orderQty)            { parts.append(q) }
            if let id = securityID ?? symbol             { parts.append(id) }
            return parts.isEmpty ? nil : parts.joined(separator: " ")

        case .quote:
            return quoteSummary(
                sideDisplay: sideDisplay, side: side,
                securityID: securityID ?? symbol,
                bidPx: bidPx, bidSize: bidSize,
                offerPx: offerPx, offerSize: offerSize
            )

        case .quoteAck:
            let qs = quoteSummary(
                sideDisplay: sideDisplay, side: side,
                securityID: securityID ?? symbol,
                bidPx: bidPx, bidSize: bidSize,
                offerPx: offerPx, offerSize: offerSize
            )
            let prefix = quoteStatus == "1" ? "Cancel" : "Ack"
            if let qs { return "\(prefix) — \(qs)" }
            return nil

        case .marketData, .other:
            return nil
        }
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
        self.ordType         = message.ordType
        self.ordTypeDisplay  = message.ordTypeDisplay
        self.lastQty         = message.lastQty
        self.lastPx          = message.lastPx
        self.bidPx           = message.bidPx
        self.offerPx         = message.offerPx
        self.bidSize         = message.bidSize
        self.offerSize       = message.offerSize
        self.quoteStatus     = message.quoteStatus
    }
}
