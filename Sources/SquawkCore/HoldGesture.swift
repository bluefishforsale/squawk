// Turns raw hotkey down/up edges into dictation actions. Kept free of AppKit
// so the timing rules (hold, tap, double-tap lock, chord) are testable
// without an event tap.

import Foundation

public struct HoldGesture {
    public enum Action: Equatable, Sendable {
        case start
        case finish
        case discard
    }

    private enum State {
        case idle
        case holding(since: TimeInterval)
        case tapped(at: TimeInterval)
        case locked(keyStillDown: Bool)
        case draining
    }

    public var tapThreshold: TimeInterval
    public var doubleTapWindow: TimeInterval
    private var state = State.idle

    public init(tapThreshold: TimeInterval = 0.25, doubleTapWindow: TimeInterval = 0.4) {
        self.tapThreshold = tapThreshold
        self.doubleTapWindow = doubleTapWindow
    }

    public mutating func keyDown(at time: TimeInterval) -> Action? {
        switch state {
        case .idle:
            state = .holding(since: time)
            return .start
        case .tapped(let at):
            state = time - at <= doubleTapWindow ? .locked(keyStillDown: true) : .holding(since: time)
            return .start
        case .locked(keyStillDown: false):
            state = .draining
            return .finish
        case .holding, .locked, .draining:
            return nil
        }
    }

    public mutating func keyUp(at time: TimeInterval) -> Action? {
        switch state {
        case .holding(let since):
            guard time - since >= tapThreshold else {
                state = .tapped(at: time)
                return .discard
            }
            state = .idle
            return .finish
        case .locked(keyStillDown: true):
            state = .locked(keyStillDown: false)
            return nil
        case .draining:
            state = .idle
            return nil
        case .idle, .tapped, .locked:
            return nil
        }
    }

    /// Another key went down. While the hotkey is held that makes it a chord
    /// (Option+E), not dictation.
    public mutating func otherKeyDown() -> Action? {
        switch state {
        case .holding:
            state = .draining
            return .discard
        case .tapped:
            state = .idle
            return nil
        case .idle, .locked, .draining:
            return nil
        }
    }
}
