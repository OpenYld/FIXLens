import Foundation

// MARK: - Field Definition

struct FieldDef: Sendable {
    let number: Int
    let name: String
    let typeName: String
    let enumValues: [String: String]  // raw value → human-readable description

    func description(for value: String) -> String? {
        enumValues[value]
    }
}

// MARK: - Message Definition

struct MessageDef: Sendable {
    let name: String
    let msgType: String
    let category: MessageCategory
}

// MARK: - Message Category

enum MessageCategory: Sendable, Equatable {
    case admin
    case newOrder
    case executionReport
    case cancelRequest
    case cancelReplace
    case orderReject
    case allocation
    case marketData
    case quote
    case other

    static func from(msgType: String, msgcat: String) -> MessageCategory {
        if msgcat == "admin" { return .admin }
        switch msgType {
        case "D":       return .newOrder
        case "8":       return .executionReport
        case "F":       return .cancelRequest
        case "G":       return .cancelReplace
        case "9":       return .orderReject
        case "J", "P":  return .allocation
        case "V", "W", "X", "Y": return .marketData
        case "R", "S":  return .quote
        default:        return .other
        }
    }
}

// MARK: - FIX Dictionary

final class FIXDictionary: Sendable {
    let fields: [Int: FieldDef]
    let messages: [String: MessageDef]  // msgType string → MessageDef

    static let empty = FIXDictionary(fields: [:], messages: [:])

    init(fields: [Int: FieldDef], messages: [String: MessageDef]) {
        self.fields = fields
        self.messages = messages
    }

    func fieldName(for tag: Int) -> String {
        fields[tag]?.name ?? "Tag(\(tag))"
    }

    func fieldDescription(tag: Int, value: String) -> String? {
        fields[tag]?.description(for: value)
    }

    func messageName(for msgType: String) -> String {
        messages[msgType]?.name ?? "Unknown(\(msgType))"
    }

    func messageCategory(for msgType: String) -> MessageCategory {
        messages[msgType]?.category ?? .other
    }
}
