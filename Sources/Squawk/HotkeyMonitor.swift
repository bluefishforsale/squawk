// Watches the dictation shortcut system-wide through an event tap. The only
// event it ever withholds from other apps is the shortcut's own non-modifier
// key while the shortcut is held; everything else passes through untouched.

import CoreGraphics
import Foundation
import SquawkCore

final class HotkeyMonitor {
    var onEdge: (BindingTracker.Edge) -> Void = { _ in }
    /// A real key press or mouse click, meaning the cursor may have moved.
    var onUserInput: () -> Void = {}

    /// Paused while dictation is disabled and while settings is learning a new
    /// shortcut, so pressing candidate keys does not start a recording.
    var isPaused = false {
        didSet { tracker.reset() }
    }

    var binding: KeyBinding {
        get { tracker.binding }
        set {
            guard newValue != tracker.binding else { return }
            tracker.binding = newValue
        }
    }

    private var tracker: BindingTracker
    private var tap: CFMachPort?

    init(binding: KeyBinding) {
        tracker = BindingTracker(binding: binding)
    }

    /// Fails until the user grants Accessibility; call again after they do.
    func start() -> Bool {
        guard tap == nil else { return true }
        let types: [CGEventType] = [.flagsChanged, .keyDown, .keyUp, .leftMouseDown, .rightMouseDown]
        let events = types.reduce(CGEventMask(0)) { $0 | 1 << $1.rawValue }
        let callback: CGEventTapCallBack = { _, type, event, context in
            let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(context!).takeUnretainedValue()
            return monitor.handle(type, event) ? nil : Unmanaged.passUnretained(event)
        }
        guard
            let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                eventsOfInterest: events, callback: callback,
                userInfo: Unmanaged.passUnretained(self).toOpaque())
        else { return false }
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
        self.tap = tap
        return true
    }

    /// Returns true when the event should be swallowed.
    private func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        }
        guard event.getIntegerValueField(.eventSourceUserData) != TextInserter.eventTag else { return false }
        if type == .leftMouseDown || type == .rightMouseDown {
            onUserInput()
            return false
        }
        guard !isPaused else { return false }

        let code = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let edges: [BindingTracker.Edge]
        var swallow = false
        switch type {
        case .flagsChanged:
            edges = tracker.modifiersChanged(event.flags.rawValue)
        case .keyDown:
            (edges, swallow) = tracker.keyDown(code)
        case .keyUp:
            (edges, swallow) = tracker.keyUp(code)
        default:
            return false
        }
        if type == .keyDown, !swallow { onUserInput() }
        edges.forEach(onEdge)
        return swallow
    }
}
