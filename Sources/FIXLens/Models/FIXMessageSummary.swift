import Foundation

/// Lightweight summary of a FIX message used as the unified display/filter type
/// for both Live mode (today's small files) and Analysis mode (large/old files).
///
/// In Live mode it is built from a full FIXMessage (byteOffset/byteLength are 0).
/// In Analysis mode it is built directly from raw bytes with a stored file offset,
/// so the full field list can be read on demand without keeping everything in RAM.
struct FIXMessageSummary: Identifiable, Sendable, TradingSummarizable {

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

    // Trading session fields
    let tradingSessionID: String?       // tag 336
    let tradSesStatus: String?          // tag 340 raw
    let tradSesStatusDisplay: String?   // tag 340 desc

    // Market data fields
    let mdUpdateAction: String?         // tag 279 raw
    let mdUpdateActionDisplay: String?  // tag 279 desc
    let mdEntryType: String?            // tag 269 raw
    let mdEntryTypeDisplay: String?     // tag 269 desc
    let mdEntrySize: String?            // tag 271
    let mdEntryPx: String?              // tag 270

    // IOI fields
    let ioiID: String?                  // tag 23
    let ioiTransType: String?           // tag 28 raw
    let ioiTransTypeDisplay: String?    // tag 28 desc
    let ioiQty: String?                 // tag 27 raw
    let ioiQtyDisplay: String?          // tag 27 desc

    // MARK: - Derived display helpers (mirrors FIXMessage)

    var formattedTime: String {
        guard let t = sendingTime else { return "—" }
        if let dash = t.firstIndex(of: "-") {
            return String(t[t.index(after: dash)...])
        }
        return t
    }

    func displayTime(local: Bool) -> String {
        guard let t = sendingTime else { return "—" }
        guard local else { return formattedTime }
        if let date = FIXTimeParsers.parse(t) {
            return FIXTimeParsers.localTimeString(from: date, hasMs: t.contains("."))
        }
        return formattedTime
    }

    var sessionDisplay: String {
        "\(senderCompID ?? "?") → \(targetCompID ?? "?")"
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
        self.tradingSessionID      = message.tradingSessionID
        self.tradSesStatus         = message.tradSesStatus
        self.tradSesStatusDisplay  = message.tradSesStatusDisplay
        self.mdUpdateAction        = message.mdUpdateAction
        self.mdUpdateActionDisplay = message.mdUpdateActionDisplay
        self.mdEntryType           = message.mdEntryType
        self.mdEntryTypeDisplay    = message.mdEntryTypeDisplay
        self.mdEntrySize           = message.mdEntrySize
        self.mdEntryPx             = message.mdEntryPx
        self.ioiID                 = message.ioiID
        self.ioiTransType          = message.ioiTransType
        self.ioiTransTypeDisplay   = message.ioiTransTypeDisplay
        self.ioiQty                = message.ioiQty
        self.ioiQtyDisplay         = message.ioiQtyDisplay
    }
}

// MARK: - UTC → local time helpers

private enum FIXTimeParsers {
    // FIX SendingTime formats: YYYYMMDD-HH:MM:SS or YYYYMMDD-HH:MM:SS.sss
    private static let withMs: DateFormatter = {
        let f = DateFormatter()
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyyMMdd-HH:mm:ss.SSS"
        return f
    }()
    private static let withoutMs: DateFormatter = {
        let f = DateFormatter()
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyyMMdd-HH:mm:ss"
        return f
    }()
    private static let localDisplay: DateFormatter = {
        let f = DateFormatter()
        f.timeZone = .current
        f.dateFormat = "HH:mm:ss"
        return f
    }()
    private static let localDisplayMs: DateFormatter = {
        let f = DateFormatter()
        f.timeZone = .current
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    static func parse(_ raw: String) -> Date? {
        withMs.date(from: raw) ?? withoutMs.date(from: raw)
    }

    static func localTimeString(from date: Date, hasMs: Bool) -> String {
        hasMs ? localDisplayMs.string(from: date) : localDisplay.string(from: date)
    }
}
