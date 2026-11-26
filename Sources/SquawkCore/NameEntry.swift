// A name the recognizer keeps getting wrong, with the spellings it produces
// instead. The sound-alikes feed acoustic rescoring: when one of them shows up
// in a transcript, the audio is checked against the real name.

import Foundation

public struct NameEntry: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var text: String
    /// Comma-separated, exactly as typed in settings.
    public var soundsLike: String

    public init(id: UUID = UUID(), text: String = "", soundsLike: String = "") {
        self.id = id
        self.text = text
        self.soundsLike = soundsLike
    }

    public var name: String {
        text.trimmingCharacters(in: .whitespaces)
    }

    public var aliases: [String] {
        soundsLike.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// The sound-alikes the rescorer may use. One with a different number of
    /// words than the name lets a whole stretch of speech be swapped for it:
    /// "Terrick Skeens" listed under "Terrac" turned "home dot Terek dot com"
    /// into a bare "Terrac".
    public var rescoringAliases: [String] {
        aliases.filter { Self.wordCount($0) == Self.wordCount(name) }
    }

    private static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: \.isWhitespace).count
    }

    /// Training: the user says the name, and whatever the recognizer wrote
    /// down instead becomes a new sound-alike. People repeat the name while
    /// the microphone is open, which comes back as "Tarek, Tarek, Tarek", so
    /// the transcript is split and each distinct hearing is added once. A
    /// hearing with more or fewer words than the name is skipped, since saying
    /// the full name while training a first name is what produced "Terrick
    /// Skeptic".
    public mutating func learn(heard transcript: String) {
        var known = Set(([name] + aliases).map { $0.lowercased() })
        var added: [String] = []
        for piece in transcript.split(whereSeparator: { ",.;!?\n".contains($0) }) {
            let heard = piece.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            guard !heard.isEmpty, Self.wordCount(heard) == Self.wordCount(name),
                known.insert(heard.lowercased()).inserted
            else { continue }
            added.append(heard)
        }
        guard !added.isEmpty else { return }
        soundsLike = (aliases + added).joined(separator: ", ")
    }
}

extension NameEntry {
    /// A hostname, path or email address in a transcript. The rescorer works
    /// on whole words and would replace all of "home.tarek.com" with the name.
    public static func isAddress(_ word: String) -> Bool {
        word.contains("/") || word.contains("@") || word.range(of: hostname, options: .regularExpression) != nil
    }

    /// Fixes the name inside a hostname by spelling, lowercased as a hostname
    /// is written: "home.tarek.com" becomes "home.terrac.com".
    public static func correctingAddresses(in text: String, names: [NameEntry]) -> String {
        var spellings: [String: String] = [:]
        for entry in names where !entry.name.isEmpty && wordCount(entry.name) == 1 {
            for heard in [entry.name] + entry.aliases { spellings[heard.lowercased()] = entry.name.lowercased() }
        }
        guard !spellings.isEmpty else { return text }
        var text = text
        let matches = hostnameRegex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        for match in matches.reversed() {
            guard let range = Range(match.range, in: text) else { continue }
            let fixed = text[range].split(separator: ".", omittingEmptySubsequences: false)
                .map { spellings[$0.lowercased()] ?? String($0) }
                .joined(separator: ".")
            text.replaceSubrange(range, with: fixed)
        }
        return text
    }

    /// NOTE: the last label must be two or more lowercase letters, like a
    /// top-level domain, so "3.5" and a missing space in "works.Then" are not
    /// taken for hostnames.
    private static let hostname = #"[\p{L}\p{N}-]+(?:\.[\p{L}\p{N}-]+)*\.\p{Ll}{2,}(?![\p{L}\p{N}])"#
    private static let hostnameRegex = try! NSRegularExpression(pattern: hostname)
}
