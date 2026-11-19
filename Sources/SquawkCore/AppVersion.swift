// A release version, for deciding whether GitHub has something newer than the
// running app. Only plain dotted numbers count: a tag with a suffix, such as
// v0.0.0-signing-test, is not a release anyone should be updated to.

public struct AppVersion: Comparable, CustomStringConvertible {
    public let parts: [Int]

    /// Accepts "1.2.3" or "v1.2.3". Returns nil for anything else.
    public init?(_ string: String) {
        let digits = string.hasPrefix("v") ? String(string.dropFirst()) : string
        let fields = digits.split(separator: ".", omittingEmptySubsequences: false)
        var parts: [Int] = []
        for field in fields {
            guard !field.isEmpty, field.allSatisfy(\.isASCII), field.allSatisfy(\.isNumber), let number = Int(field)
            else { return nil }
            parts.append(number)
        }
        guard !parts.isEmpty else { return nil }
        self.parts = parts
    }

    public var description: String {
        parts.map(String.init).joined(separator: ".")
    }

    /// Local builds are stamped 0.0.0 and must never be offered an update.
    public var isDevelopmentBuild: Bool {
        parts.allSatisfy { $0 == 0 }
    }

    public static func == (left: AppVersion, right: AppVersion) -> Bool {
        !(left < right) && !(right < left)
    }

    public static func < (left: AppVersion, right: AppVersion) -> Bool {
        for index in 0..<max(left.parts.count, right.parts.count) {
            let a = index < left.parts.count ? left.parts[index] : 0
            let b = index < right.parts.count ? right.parts[index] : 0
            if a != b { return a < b }
        }
        return false
    }
}
