// Decides how long to keep recording after the dictation key is released.
// People let go while the last word is still coming out, and audio that stops
// mid-word makes Parakeet return nothing at all, or invent a word. So the
// recording runs on until the voice has gone quiet, within fixed bounds.

import Foundation

public struct SpeechTail {
    /// Recording always runs at least this long past release.
    public var minimum: TimeInterval = 0.15
    /// And never longer than this, however noisy the room is.
    public var maximum: TimeInterval = 0.6
    /// How long the level must stay down before the voice counts as finished.
    public var quiet: TimeInterval = 0.15

    private var peak: Float = 0
    private var lastLoudAt: TimeInterval?

    public init() {}

    /// Feed every level reading of the dictation, from key down onwards.
    /// `rms` is linear amplitude, 0 to 1.
    public mutating func heard(rms: Float, at time: TimeInterval) {
        peak = max(peak, rms)
        // Loud is judged against this dictation's own peak, so a quiet talker
        // and a noisy room both work; the floor keeps silence from counting.
        if rms >= max(0.003, peak * 0.2) {
            lastLoudAt = time
        }
    }

    public func isFinished(releasedAt: TimeInterval, now: TimeInterval) -> Bool {
        let elapsed = now - releasedAt
        if elapsed < minimum { return false }
        if elapsed >= maximum { return true }
        guard let lastLoudAt else { return true }
        return now - lastLoudAt >= quiet
    }
}
