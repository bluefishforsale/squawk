import Testing

@testable import SquawkCore

@Suite struct SpeechTailTests {
    @Test func finishesAtTheMinimumWhenTheVoiceHasAlreadyStopped() {
        var tail = SpeechTail()
        tail.heard(rms: 0.1, at: 0.5)
        tail.heard(rms: 0.001, at: 0.9)
        #expect(!tail.isFinished(releasedAt: 1.0, now: 1.1))
        #expect(tail.isFinished(releasedAt: 1.0, now: 1.16))
    }

    @Test func keepsRecordingWhileTheLastWordIsStillBeingSpoken() {
        var tail = SpeechTail()
        tail.heard(rms: 0.1, at: 0.9)
        tail.heard(rms: 0.08, at: 1.2)
        #expect(!tail.isFinished(releasedAt: 1.0, now: 1.25))
        #expect(tail.isFinished(releasedAt: 1.0, now: 1.35))
    }

    @Test func givesUpAtTheMaximumInARoomThatNeverGoesQuiet() {
        var tail = SpeechTail()
        tail.heard(rms: 0.1, at: 1.55)
        #expect(tail.isFinished(releasedAt: 1.0, now: 1.6))
    }

    @Test func backgroundNoiseFarBelowTheVoiceDoesNotCountAsSpeech() {
        var tail = SpeechTail()
        tail.heard(rms: 0.2, at: 0.5)
        tail.heard(rms: 0.02, at: 1.14)
        #expect(tail.isFinished(releasedAt: 1.0, now: 1.16))
    }

    @Test func finishesAtTheMinimumWhenNothingWasHeardAtAll() {
        let tail = SpeechTail()
        #expect(tail.isFinished(releasedAt: 1.0, now: 1.16))
    }
}
