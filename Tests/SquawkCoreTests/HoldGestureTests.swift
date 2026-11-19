import Testing

@testable import SquawkCore

@Suite struct HoldGestureTests {
    @Test func holdThenReleaseTranscribes() {
        var gesture = HoldGesture()
        #expect(gesture.keyDown(at: 0) == .start)
        #expect(gesture.keyUp(at: 1.5) == .finish)
    }

    @Test func accidentalTapDiscardsInsteadOfPastingNoise() {
        var gesture = HoldGesture()
        #expect(gesture.keyDown(at: 0) == .start)
        #expect(gesture.keyUp(at: 0.1) == .discard)
    }

    @Test func doubleTapLocksRecordingUntilNextPress() {
        var gesture = HoldGesture()
        _ = gesture.keyDown(at: 0)
        _ = gesture.keyUp(at: 0.1)
        #expect(gesture.keyDown(at: 0.3) == .start)
        #expect(gesture.keyUp(at: 0.4) == nil)
        #expect(gesture.keyDown(at: 20) == .finish)
        #expect(gesture.keyUp(at: 20.1) == nil)
    }

    @Test func releaseAfterLockedStopDoesNotStartNewRecording() {
        var gesture = HoldGesture()
        _ = gesture.keyDown(at: 0)
        _ = gesture.keyUp(at: 0.1)
        _ = gesture.keyDown(at: 0.3)
        _ = gesture.keyUp(at: 0.4)
        _ = gesture.keyDown(at: 20)
        _ = gesture.keyUp(at: 20.1)
        #expect(gesture.keyDown(at: 30) == .start)
        #expect(gesture.keyUp(at: 32) == .finish)
    }

    @Test func slowSecondTapIsAFreshHoldNotALock() {
        var gesture = HoldGesture()
        _ = gesture.keyDown(at: 0)
        _ = gesture.keyUp(at: 0.1)
        #expect(gesture.keyDown(at: 2) == .start)
        #expect(gesture.keyUp(at: 4) == .finish)
    }

    @Test func chordWithHotkeyDiscardsAndIgnoresRelease() {
        var gesture = HoldGesture()
        _ = gesture.keyDown(at: 0)
        #expect(gesture.otherKeyDown() == .discard)
        #expect(gesture.keyUp(at: 1) == nil)
        #expect(gesture.keyDown(at: 2) == .start)
    }

    @Test func typingWhileLockedKeepsRecording() {
        var gesture = HoldGesture()
        _ = gesture.keyDown(at: 0)
        _ = gesture.keyUp(at: 0.1)
        _ = gesture.keyDown(at: 0.3)
        _ = gesture.keyUp(at: 0.4)
        #expect(gesture.otherKeyDown() == nil)
        #expect(gesture.keyDown(at: 5) == .finish)
    }

    @Test func keystrokeBetweenTapsCancelsPendingLock() {
        var gesture = HoldGesture()
        _ = gesture.keyDown(at: 0)
        _ = gesture.keyUp(at: 0.1)
        _ = gesture.otherKeyDown()
        #expect(gesture.keyDown(at: 0.3) == .start)
        #expect(gesture.keyUp(at: 2) == .finish)
    }
}
