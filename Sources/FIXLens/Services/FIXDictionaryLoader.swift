import Foundation

// SAX-style XML parser for FIX44.xml.
// Thread-safe: constructed and used on whichever thread calls load().
final class FIXDictionaryLoader: NSObject, XMLParserDelegate, @unchecked Sendable {

    // Accumulated results
    private var fieldDefs: [Int: FieldDef] = [:]
    private var messageDefs: [String: MessageDef] = [:]

    // Parsing state
    private var inFieldsSection = false
    private var inMessagesSection = false

    // Current field being built
    private var currentTag: Int?
    private var currentName: String?
    private var currentType: String?
    private var currentEnumValues: [String: String] = [:]

    // MARK: - Public API

    static func loadFromBundle() -> FIXDictionary {
        // Production: bundled resource
        if let url = Bundle.module.url(forResource: "FIX44", withExtension: "xml") {
            return load(from: url)
        }
        // Development fallback: ~/Applications/share/FIX44.xml
        let devURL = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Applications/share/FIX44.xml")
        if FileManager.default.fileExists(atPath: devURL.path) {
            return load(from: devURL)
        }
        return .empty
    }

    static func load(from url: URL) -> FIXDictionary {
        let loader = FIXDictionaryLoader()
        guard let parser = XMLParser(contentsOf: url) else { return .empty }
        parser.delegate = loader
        parser.parse()
        return FIXDictionary(fields: loader.fieldDefs, messages: loader.messageDefs)
    }

    // MARK: - XMLParserDelegate

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName _: String?,
        attributes attrs: [String: String] = [:]
    ) {
        switch elementName {

        case "fields":
            inFieldsSection = true
            inMessagesSection = false

        case "messages":
            inMessagesSection = true
            inFieldsSection = false

        case "components", "header", "trailer":
            inFieldsSection = false
            inMessagesSection = false

        // A <field> inside <fields> carries number/name/type attributes
        case "field" where inFieldsSection:
            guard
                let numberStr = attrs["number"],
                let number = Int(numberStr),
                let name = attrs["name"],
                let type = attrs["type"]
            else { return }
            currentTag = number
            currentName = name
            currentType = type
            currentEnumValues = [:]

        // <value> children of a field carry enum mappings
        case "value" where inFieldsSection && currentTag != nil:
            guard let raw = attrs["enum"], let desc = attrs["description"] else { return }
            currentEnumValues[raw] = humanize(desc)

        // <message> inside <messages>
        case "message" where inMessagesSection:
            guard
                let name = attrs["name"],
                let msgType = attrs["msgtype"],
                let msgcat = attrs["msgcat"]
            else { return }
            let category = MessageCategory.from(msgType: msgType, msgcat: msgcat)
            messageDefs[msgType] = MessageDef(name: name, msgType: msgType, category: category)

        default:
            break
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName _: String?
    ) {
        guard elementName == "field", inFieldsSection else { return }
        if let tag = currentTag, let name = currentName, let type = currentType {
            fieldDefs[tag] = FieldDef(
                number: tag,
                name: name,
                typeName: type,
                enumValues: currentEnumValues
            )
        }
        currentTag = nil
        currentName = nil
        currentType = nil
        currentEnumValues = [:]
    }

    // MARK: - Helpers

    /// Convert SCREAMING_SNAKE_CASE to Title Case With Spaces
    private func humanize(_ raw: String) -> String {
        raw.split(separator: "_")
            .map { word -> String in
                let s = word.lowercased()
                return s.prefix(1).uppercased() + s.dropFirst()
            }
            .joined(separator: " ")
    }
}
