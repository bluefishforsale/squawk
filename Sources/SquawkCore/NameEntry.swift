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

    /// Training: the user says the name, and whatever the recognizer wrote
    /// down instead becomes a new sound-alike.
    public mutating func learn(heard transcript: String) {
        let heard = transcript.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        let known = ([name] + aliases).map { $0.lowercased() }
        guard !heard.isEmpty, !known.contains(heard.lowercased()) else { return }
        soundsLike = (aliases + [heard]).joined(separator: ", ")
    }
}
