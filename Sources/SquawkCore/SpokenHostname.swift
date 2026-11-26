// The recognizer writes a hostname read aloud as words, "home dot terrac dot
// com", and only sometimes joins it. A hostname is only useful pasted whole.

import Foundation

public enum SpokenHostname {
    /// Joins "home dot terrac dot com" and "home.terrac dot com" into
    /// "home.terrac.com", lowercased as hostnames are written.
    public static func joining(_ transcript: String) -> String {
        var text = transcript
        for match in spoken.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            guard let range = Range(match.range, in: text) else { continue }
            let joined = text[range].replacingOccurrences(
                of: #"\s+dot\s+"#, with: ".", options: [.regularExpression, .caseInsensitive])
            text.replaceSubrange(range, with: joined.lowercased())
        }
        return text
    }

    /// NOTE: only joins when the last label is a known top-level domain, so
    /// "connect the dot to the line" is left alone. `home` and `lan` are here
    /// because the fleet's own hosts are named that way.
    private static let topLevelDomains = [
        "com", "net", "org", "io", "dev", "app", "ai", "co", "me", "us", "uk", "ca", "edu", "gov", "info",
        "xyz", "sh", "home", "lan", "local", "internal",
    ]

    private static let label = #"[\p{L}\p{N}][\p{L}\p{N}-]*"#
    private static let spoken = try! NSRegularExpression(
        pattern: #"(?i)(?<![\p{L}\p{N}.@/-])"# + label + #"(?:(?:\s+dot\s+|\.)"# + label + #")*"#
            + #"\s+dot\s+(?:"# + topLevelDomains.joined(separator: "|") + #")(?![\p{L}\p{N}-])"#)
}
