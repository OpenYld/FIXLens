import Foundation

// MARK: - FIX Field (a single tag=value pair, enriched from dictionary)

struct FIXField: Identifiable, Sendable {
    let id: UUID
    let tag: Int
    let name: String        // human-readable name from dictionary
    let rawValue: String
    let description: String?  // enum description if available

    var displayValue: String {
        if let desc = description {
            return "\(rawValue) — \(desc)"
        }
        return rawValue
    }
}

// MARK: - FIX Message

struct FIXMessage: Identifiable, Sendable {
    let id: UUID
    let index: Int          // position in the parsed input
    let rawText: String
    let fields: [FIXField]  // ordered as received

    // Category / identity
    let isAdmin: Bool
    let category: MessageCategory

    // Frequently accessed header fields
    let msgType: String?
    let msgTypeName: String
    let sendingTime: String?
    let seqNum: String?
    let senderCompID: String?
    let targetCompID: String?

    // Common trading fields
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

    // Private lookup map (first occurrence wins for duplicate tags)
    private let fieldMap: [Int: FIXField]

    init(index: Int, rawText: String, fields: [FIXField], dictionary: FIXDictionary) {
        self.id = UUID()
        self.index = index
        self.rawText = rawText
        self.fields = fields

        // Build lookup map; first occurrence wins (body takes priority over later repeats)
        var map: [Int: FIXField] = [:]
        for field in fields {
            if map[field.tag] == nil { map[field.tag] = field }
        }
        self.fieldMap = map

        let mt = map[35]?.rawValue
        self.msgType = mt
        self.msgTypeName = mt.map { dictionary.messageName(for: $0) } ?? "Unknown"
        let cat = mt.map { dictionary.messageCategory(for: $0) } ?? .other
        self.category = cat
        self.isAdmin = cat == .admin

        self.sendingTime = map[52]?.rawValue
        self.seqNum      = map[34]?.rawValue
        self.senderCompID = map[49]?.rawValue
        self.targetCompID = map[56]?.rawValue

        self.symbol       = map[55]?.rawValue
        self.side         = map[54]?.rawValue
        self.sideDisplay  = map[54]?.description ?? map[54].map { sideLabel($0.rawValue) }
        self.orderQty     = map[38]?.rawValue
        self.price        = map[44]?.rawValue
        self.ordStatus        = map[39]?.rawValue
        self.ordStatusDisplay = map[39]?.description
        self.clOrdID      = map[11]?.rawValue
        self.securityID   = map[48]?.rawValue
        self.execType        = map[150]?.rawValue
        self.execTypeDisplay = map[150]?.description
        self.text         = map[58]?.rawValue
        self.ordType      = map[40]?.rawValue
        self.ordTypeDisplay = map[40]?.description
        self.lastQty      = map[32]?.rawValue
        self.lastPx       = map[31]?.rawValue
        self.bidPx        = map[132]?.rawValue
        self.offerPx      = map[133]?.rawValue
        self.bidSize      = map[134]?.rawValue
        self.offerSize    = map[135]?.rawValue
        self.quoteStatus  = map[297]?.rawValue
    }

    func field(tag: Int) -> FIXField? { fieldMap[tag] }

    // MARK: - Derived display helpers

    /// Just the HH:MM:SS.mmm portion of SendingTime
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

    /// Compact human-readable sentence tailored to message category.
    /// Examples: "Buy 1,000 IBM @ 150.25 — Fill 500 @ 149.99", "Cancel IBM", "Rejected: Unknown order"
    /// Falls back to tag-58 Text if no structured summary can be built.
    var tradingSummary: String? {
        let primary: String? = {
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
            if execType == "1" || execType == "2" || execType == "F" || execType == "G" || execType == "H" {
                let fillPrefix: String
                if execType == "G" {
                    fillPrefix = "Correct"
                } else if execType == "H" {
                    fillPrefix = "Cancel"
                } else if execType == "F" && ordStatus == "4" {
                    fillPrefix = "Cancel"
                } else if execType == "F" && ordStatus == "5" {
                    fillPrefix = "Correct"
                } else if execType == "F" && ordStatus == "1" {
                    fillPrefix = "Partial"
                } else {
                    fillPrefix = "Fill"
                }
                var fill = [fillPrefix]
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
        }()
        return primary ?? text
    }
}

// MARK: - Helpers

/// Formats a raw FIX quantity string with thousand separators.
/// Returns nil when the input is nil; returns the raw string if it cannot be parsed.
func formatFIXQty(_ raw: String?) -> String? {
    guard let raw else { return nil }
    guard let d = Double(raw) else { return raw }
    if d.truncatingRemainder(dividingBy: 1) == 0 {
        return Int(d).formatted(.number)
    }
    return d.formatted(.number.precision(.fractionLength(0...4)))
}

/// Formats a raw FIX price string with at least 2 and up to 8 decimal places.
/// Returns nil when the input is nil; returns the raw string if it cannot be parsed.
func formatFIXPrice(_ raw: String?) -> String? {
    guard let raw else { return nil }
    guard let d = Double(raw) else { return raw }
    return d.formatted(.number.precision(.fractionLength(2...8)))
}

/// Returns true when a quote side is cancelled — i.e. both price and size are absent or zero.
func isQuoteSideCancelled(px: String?, size: String?) -> Bool {
    func isAbsentOrZero(_ v: String?) -> Bool {
        guard let v else { return true }
        return (Double(v) ?? 0) == 0
    }
    return isAbsentOrZero(px) && isAbsentOrZero(size)
}

/// Builds the Quote summary for a single-sided quote message.
/// Side (tag 54) determines which price/size fields apply:
///   Buy (1)        → BidPx (132) / BidSize (134)
///   Sell (2, 5, 6) → OfferPx (133) / OfferSize (135)
/// Normal format: "<side> <qty> <securityID> @ <price>"
/// Cancel format: "<side> Cancel <securityID>"
func quoteSummary(sideDisplay: String?, side: String?, securityID: String?,
                  bidPx: String?, bidSize: String?,
                  offerPx: String?, offerSize: String?) -> String? {
    let px: String?
    let sz: String?

    switch side {
    case "1":            // Buy → bid fields
        px = bidPx;  sz = bidSize
    case "2", "5", "6":  // Sell / Sell Short → offer fields
        px = offerPx; sz = offerSize
    default:
        return nil
    }

    let sideStr = sideDisplay ?? (side == "1" ? "Buy" : "Sell")
    var parts: [String] = []

    if isQuoteSideCancelled(px: px, size: sz) {
        parts.append("Cancel")
        parts.append(sideStr)
        if let id = securityID { parts.append(id) }
    } else {
        parts.append(sideStr)
        if let q = formatFIXQty(sz)    { parts.append(q) }
        if let id = securityID         { parts.append(id) }
        if let p = formatFIXPrice(px)  { parts.append("@ \(p)") }
    }

    return parts.joined(separator: " ")
}

func sideLabel(_ raw: String) -> String {
    switch raw {
    case "1": return "Buy"
    case "2": return "Sell"
    case "5": return "Sell Short"
    case "6": return "Sell Short Exempt"
    default: return raw
    }
}
