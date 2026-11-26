// Rule-based tidy-up of a transcript before it is pasted. Deliberately not a
// language model: it has to cost nothing in memory and never surprise. Every
// rule removes speech noise or fixes spacing; none of them rephrase.

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
    /// Drops um and uh, and stuttered function words ("the the").
    public var removeFillers: Bool
    /// Drops filler "like" and turns "she was like," into "she said,".
    public var rewriteLike: Bool
    public var spaceAfterPunctuation: Bool
    /// The recognizer reads level or trailing-off intonation as an unfinished
    /// sentence and leaves the full stop out; this puts it back.
    public var endWithPeriod: Bool
    /// Zero to nine as words, ten and up as digits, phone numbers hyphenated.
    public var formatNumbers: Bool
    public var replacements: [Replacement]

    public init(
        removeFillers: Bool = true,
        rewriteLike: Bool = false,
        spaceAfterPunctuation: Bool = true,
        endWithPeriod: Bool = true,
        formatNumbers: Bool = true,
        replacements: [Replacement] = []
    ) {
        self.removeFillers = removeFillers
        self.rewriteLike = rewriteLike
        self.spaceAfterPunctuation = spaceAfterPunctuation
        self.endWithPeriod = endWithPeriod
        self.formatNumbers = formatNumbers
        self.replacements = replacements
    }

    public func apply(_ transcript: String) -> String {
        var text = transcript
        if removeFillers {
            text = Self.removing(Self.filler, from: text)
            text = text.replacingOccurrences(of: Self.stutter, with: "$1", options: .regularExpression)
        }
        if rewriteLike {
            text = text.replacingOccurrences(of: Self.likeBeforeIntensifier, with: "$1 ", options: .regularExpression)
            text = text.replacingOccurrences(of: Self.quotativeLike, with: "$1 said, ", options: .regularExpression)
            text = Self.removing(Self.fillerLike, from: text)
        }
        if formatNumbers {
            text = NumberFormatting.apply(text)
        }
        for rule in replacements {
            let pattern = #"(?i)(?<![\p{L}\p{N}])"# + NSRegularExpression.escapedPattern(for: rule.spoken)
                + #"(?![\p{L}\p{N}])"#
            text = text.replacingOccurrences(
                of: pattern,
                with: NSRegularExpression.escapedTemplate(for: rule.written),
                options: .regularExpression)
        }
        if spaceAfterPunctuation {
            text = text.replacingOccurrences(of: #"([,;:!?])(?=\p{L})"#, with: "$1 ", options: .regularExpression)
            // Only between a lowercase word and a capitalized one, so "3.5",
            // "example.com" and "U.S." are left alone.
            text = text.replacingOccurrences(
                of: #"(?<=\p{Ll}{2})\.(?=\p{Lu}\p{Ll})"#, with: ". ", options: .regularExpression)
        }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Three words is the floor so that dictating a name or a search term
        // into a field does not grow a full stop.
        if endWithPeriod, let last = text.last, last.isLetter || last.isNumber,
            text.split(separator: " ").count >= 3
        {
            text += "."
        }
        return text
    }

    private static let notInWord = #"(?<![\p{L}\p{N}'’])"#
    private static let wordEnd = #"(?![\p{L}\p{N}'’])"#

    private static let filler = try! NSRegularExpression(
        pattern: #"(?i)\s*"# + notInWord + #"(?:um+|uh+|erm+|hmm+)"# + wordEnd + #",?\s*"#)

    /// "like" set off by a comma is filler; "I like tea" and "looks like rain"
    /// have no comma after it and are left alone.
    private static let fillerLike = try! NSRegularExpression(
        pattern: #"(?i),?\s*"# + notInWord + #"like,\s*"#)

    /// Limited to short function words. Doubling a content word is usually
    /// meant ("very very", "no no"), and "had had" and "that that" are grammar.
    private static let stutter =
        #"(?i)\b(i|the|a|an|and|to|we|it|of|in|so|but|you|he|she|they|my|this|for|on|at|if|or)(?:\s+\1\b)+"#

    private static let beVerb =
        #"(?:was|were|is|are|am|be|been|(?:it|that|he|she|there)['’]s|i['’]m|(?:you|we|they)['’]re)"#

    /// "it was like really big": only after a form of "to be", because "I
    /// like really spicy food" has the same words and means them.
    private static let likeBeforeIntensifier =
        #"(?i)\b("# + beVerb + #")\s+like,?\s+"#
        + #"(?=(?:so|really|totally|super|literally|seriously|basically|kind of|kinda|very|way|just)\b)"#

    private static let quotativeLike =
        #"(?i)\b(I|he|she|they|we|you|it)(?:\s+(?:was|were|am|is|are)|['’](?:m|s|re))\s+(?:all\s+)?like,\s*"#

    /// Cuts every match out, leaving one space between the neighbours and
    /// capitalizing whatever now starts a sentence.
    private static func removing(_ noise: NSRegularExpression, from transcript: String) -> String {
        var text = transcript
        let matches = noise.matches(in: text, range: NSRange(text.startIndex..., in: text))
        for match in matches.reversed() {
            guard let range = Range(match.range, in: text) else { continue }
            let before = String(text[..<range.lowerBound])
            var after = String(text[range.upperBound...])
            let startsSentence = before.isEmpty || ".!?".contains(before.last!)
            if startsSentence, let first = after.first {
                after = first.uppercased() + after.dropFirst()
            }
            text = before + (before.isEmpty || after.isEmpty ? "" : " ") + after
        }
        // Noise that ended a clause leaves ", ." or a space before punctuation.
        text = text.replacingOccurrences(of: #",?\s+([.!?])"#, with: "$1", options: .regularExpression)
        return text.replacingOccurrences(of: #",\s*$"#, with: "", options: .regularExpression)
    }
}
