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

    /// Compact human-readable sentence: "Buy 1,000 IBM @ 150.25 — Filled"
    /// Returns nil when none of the trading fields are present (admin, market data, etc.).
    var tradingSummary: String? {
        var parts: [String] = []

        if let s = sideDisplay              { parts.append(s) }
        if let q = orderQty                 { parts.append(q) }
        if let sym = symbol                 { parts.append(sym) }
        if let p = price                    { parts.append("@ \(p)") }

        guard !parts.isEmpty else { return nil }

        if let status = ordStatusDisplay ?? ordStatus {
            parts.append("— \(status)")
        }

        return parts.joined(separator: " ")
    }
}

// MARK: - Helpers

func sideLabel(_ raw: String) -> String {
    switch raw {
    case "1": return "Buy"
    case "2": return "Sell"
    case "5": return "Sell Short"
    case "6": return "Sell Short Exempt"
    default: return raw
    }
}
