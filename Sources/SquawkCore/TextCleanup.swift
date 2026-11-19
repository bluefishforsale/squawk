// Rule-based tidy-up of a transcript before it is pasted. Deliberately not a
// language model: it has to cost nothing in memory and never surprise.

import Foundation

public struct Replacement: Equatable, Sendable {
    public var spoken: String
    public var written: String

    public init(spoken: String, written: String) {
        self.spoken = spoken
        self.written = written
    }

    /// One rule per line, `spoken => written`. Lines without `=>` are ignored
    /// so a half-typed settings field never breaks dictation.
    public static func parse(_ text: String) -> [Replacement] {
        text.split(whereSeparator: \.isNewline).compactMap { line in
            guard let arrow = line.range(of: "=>") else { return nil }
            let spoken = line[..<arrow.lowerBound].trimmingCharacters(in: .whitespaces)
            let written = line[arrow.upperBound...].trimmingCharacters(in: .whitespaces)
            guard !spoken.isEmpty else { return nil }
            return Replacement(spoken: spoken, written: written)
        }
    }
}

public struct TextCleanup: Sendable {
    public var removeFillers: Bool
    public var replacements: [Replacement]

    public init(removeFillers: Bool = true, replacements: [Replacement] = []) {
        self.removeFillers = removeFillers
        self.replacements = replacements
    }

    public func apply(_ transcript: String) -> String {
        var text = transcript
        if removeFillers {
            text = Self.strippingFillers(from: text)
        }
        for rule in replacements {
            let pattern = #"(?i)(?<![\p{L}\p{N}])"# + NSRegularExpression.escapedPattern(for: rule.spoken)
                + #"(?![\p{L}\p{N}])"#
            text = text.replacingOccurrences(
                of: pattern,
                with: NSRegularExpression.escapedTemplate(for: rule.written),
                options: .regularExpression)
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let filler = try! NSRegularExpression(
        pattern: #"(?i)(?<![\p{L}\p{N}'])(?:um+|uh+|erm+|hmm+)(?![\p{L}\p{N}']),?\s*"#)

    private static func strippingFillers(from transcript: String) -> String {
        var text = transcript
        let matches = filler.matches(in: text, range: NSRange(text.startIndex..., in: text))
        for match in matches.reversed() {
            guard let range = Range(match.range, in: text) else { continue }
            let before = text[..<range.lowerBound].trimmingCharacters(in: .whitespaces)
            let startsSentence = before.isEmpty || ".!?".contains(before.last!)
            var after = String(text[range.upperBound...])
            if startsSentence, let first = after.first {
                after = first.uppercased() + after.dropFirst()
            }
            text = text[..<range.lowerBound] + after
        }
        // A filler that ended a clause leaves ", ." or a space before punctuation.
        text = text.replacingOccurrences(of: #",?\s+([.!?])"#, with: "$1", options: .regularExpression)
        text = text.replacingOccurrences(of: #",\s*$"#, with: "", options: .regularExpression)
        return text.replacingOccurrences(of: #" {2,}"#, with: " ", options: .regularExpression)
    }
}
