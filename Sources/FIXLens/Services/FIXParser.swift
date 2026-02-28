import Foundation

// MARK: - Delimiter

enum FIXDelimiter: CaseIterable, Sendable {
    case soh    // \u{01} — actual wire format
    case pipe   // |
    case caret  // ^
    case space  // fallback

    var string: String {
        switch self {
        case .soh:   return "\u{01}"
        case .pipe:  return "|"
        case .caret: return "^"
        case .space: return " "
        }
    }
}

// MARK: - Parser

struct FIXParser: Sendable {

    static func parse(_ input: String, dictionary: FIXDictionary) -> [FIXMessage] {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let delimiter = detectDelimiter(trimmed)
        let rawMessages = extractMessages(from: trimmed, delimiter: delimiter)

        return rawMessages.enumerated().compactMap { index, raw in
            parseMessage(raw, index: index, delimiter: delimiter, dictionary: dictionary)
        }
    }

    // MARK: - Delimiter detection

    static func detectDelimiter(_ input: String) -> FIXDelimiter {
        let sample = String(input.prefix(1000))

        // Count candidate delimiters (only SOH, pipe, caret — space needs special handling)
        let candidates: [(FIXDelimiter, Int)] = [
            (.soh,   sample.components(separatedBy: "\u{01}").count - 1),
            (.pipe,  sample.components(separatedBy: "|").count - 1),
            (.caret, sample.components(separatedBy: "^").count - 1),
        ]

        // Pick whichever has the most occurrences, requiring at least 3
        if let (best, count) = candidates.max(by: { $0.1 < $1.1 }), count >= 3 {
            return best
        }

        // Space fallback: check whether space-separated tokens look like tag=value
        let spaceTokens = sample.components(separatedBy: " ")
        let tagValueCount = spaceTokens.filter { looksLikeTagValue($0) }.count
        if tagValueCount >= 3 {
            return .space
        }

        return .pipe  // safe default
    }

    // MARK: - Message extraction

    private static func extractMessages(from input: String, delimiter: FIXDelimiter) -> [String] {
        var results: [String] = []

        // Strategy 1: line-by-line (most log files have one message per line)
        let lines = input.components(separatedBy: CharacterSet.newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        for line in lines {
            if let msg = extractFIXMessage(from: line) {
                results.append(msg)
            }
        }

        // Strategy 2: treat entire input as a blob (e.g. SOH-delimited multi-message stream)
        if results.isEmpty {
            results = splitBlob(input)
        }

        return results
    }

    /// Finds the first occurrence of "8=FIX" in a line and returns everything from there.
    /// Handles log prefixes like timestamps, log levels, direction markers, etc.
    private static func extractFIXMessage(from line: String) -> String? {
        guard let range = line.range(of: "8=FIX", options: [], range: line.startIndex..<line.endIndex) else {
            return nil
        }
        let msg = String(line[range.lowerBound...]).trimmingCharacters(in: .whitespaces)
        return msg.isEmpty ? nil : msg
    }

    /// Splits a blob of text into individual messages by finding "8=FIX" boundaries.
    private static func splitBlob(_ input: String) -> [String] {
        var messages: [String] = []
        var searchFrom = input.startIndex

        while searchFrom < input.endIndex {
            guard let start = input.range(of: "8=FIX", range: searchFrom..<input.endIndex) else { break }

            // Look for next occurrence of "8=FIX" after a delimiter
            let afterStart = start.upperBound
            if let nextStart = input.range(of: "8=FIX", range: afterStart..<input.endIndex) {
                let chunk = String(input[start.lowerBound..<nextStart.lowerBound])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !chunk.isEmpty { messages.append(chunk) }
                searchFrom = nextStart.lowerBound
            } else {
                let chunk = String(input[start.lowerBound...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !chunk.isEmpty { messages.append(chunk) }
                break
            }
        }

        return messages
    }

    // MARK: - Single message parsing

    private static func parseMessage(
        _ raw: String,
        index: Int,
        delimiter: FIXDelimiter,
        dictionary: FIXDictionary
    ) -> FIXMessage? {
        // For space delimiter, use regex-based extraction to handle log prefixes
        let tokens: [String]
        if delimiter == .space {
            tokens = extractSpaceDelimitedTokens(from: raw)
        } else {
            tokens = raw.components(separatedBy: delimiter.string)
        }

        var fields: [FIXField] = []

        for token in tokens {
            let trimmed = token.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            // Find the first '=' to split tag from value
            guard let eqIndex = trimmed.firstIndex(of: "=") else { continue }
            let tagStr = String(trimmed[..<eqIndex])
            let value  = String(trimmed[trimmed.index(after: eqIndex)...])

            guard let tag = Int(tagStr), !value.isEmpty else { continue }

            let name = dictionary.fieldName(for: tag)
            let desc = dictionary.fieldDescription(tag: tag, value: value)

            fields.append(FIXField(id: UUID(), tag: tag, name: name, rawValue: value, description: desc))
        }

        guard !fields.isEmpty else { return nil }

        return FIXMessage(index: index, rawText: raw, fields: fields, dictionary: dictionary)
    }

    /// For space-delimited input: extract only tokens that look like tag=value (tag is all digits).
    private static func extractSpaceDelimitedTokens(from raw: String) -> [String] {
        raw.components(separatedBy: " ").filter { looksLikeTagValue($0) }
    }

    private static func looksLikeTagValue(_ token: String) -> Bool {
        guard let eq = token.firstIndex(of: "=") else { return false }
        let tagPart = token[..<eq]
        return !tagPart.isEmpty && tagPart.allSatisfy(\.isNumber)
    }
}

// MARK: - Streaming

struct ParseUpdate: Sendable {
    let batch: [FIXMessage]
    let progress: Double
}

extension FIXParser {
    static func stream(
        _ input: String,
        dictionary: FIXDictionary
    ) -> AsyncStream<ParseUpdate> {
        AsyncStream { continuation in
            Task.detached(priority: .userInitiated) {
                let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continuation.finish(); return }

                let delimiter = detectDelimiter(trimmed)
                let lines = trimmed.components(separatedBy: CharacterSet.newlines)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }

                let total = Double(max(lines.count, 1))
                let batchSize = 2_000
                var batch: [FIXMessage] = []
                var msgIdx = 0

                for (i, line) in lines.enumerated() {
                    if let raw = extractFIXMessage(from: line),
                       let msg = parseMessage(raw, index: msgIdx, delimiter: delimiter, dictionary: dictionary) {
                        batch.append(msg)
                        msgIdx += 1
                    }
                    if batch.count >= batchSize {
                        continuation.yield(ParseUpdate(batch: batch, progress: Double(i + 1) / total))
                        batch = []
                    }
                }
                if !batch.isEmpty {
                    continuation.yield(ParseUpdate(batch: batch, progress: 1.0))
                }
                continuation.finish()
            }
        }
    }
}
