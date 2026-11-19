// Watches one modifier key system-wide through a listen-only event tap. It
// never consumes or rewrites events, so a crash here cannot eat keystrokes.

import CoreGraphics
import Foundation

enum Hotkey: String, CaseIterable, Identifiable {
    case rightOption
    case rightCommand
    case fn

    var id: String { rawValue }

    var label: String {
        switch self {
        case .rightOption: "Right Option"
        case .rightCommand: "Right Command"
        case .fn: "Fn / Globe"
        }
    }

    var keyCode: Int64 {
        switch self {
        case .rightOption: 61
        case .rightCommand: 54
        case .fn: 63
        }
    }

    /// Device-dependent bits from IOLLEvent.h (NX_DEVICERALTKEYMASK and
    /// friends). The generic Option and Command masks cannot tell left from right.
    var flagMask: UInt64 {
        switch self {
        case .rightOption: 0x40
        case .rightCommand: 0x10
        case .fn: 0x80_0000
        }
    }
}

final class HotkeyMonitor {
    var onHotkeyDown: () -> Void = {}
    var onHotkeyUp: () -> Void = {}
    var onOtherKeyDown: () -> Void = {}

    private var tap: CFMachPort?
    private var isDown = false

    /// Fails until the user grants Accessibility; call again after they do.
    func start() -> Bool {
        guard tap == nil else { return true }
        let events = CGEventMask(1 << CGEventType.flagsChanged.rawValue | 1 << CGEventType.keyDown.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, context in
            let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(context!).takeUnretainedValue()
            monitor.handle(type, event)
            return Unmanaged.passUnretained(event)
        }
        guard
            let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
                eventsOfInterest: events, callback: callback,
                userInfo: Unmanaged.passUnretained(self).toOpaque())
        else { return false }
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
        self.tap = tap
        return true
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
        case .keyDown:
            onOtherKeyDown()
        case .flagsChanged:
            let hotkey = Preferences.hotkey
            guard event.getIntegerValueField(.keyboardEventKeycode) == hotkey.keyCode else { return }
            let down = event.flags.rawValue & hotkey.flagMask != 0
            guard down != isDown else { return }
            isDown = down
            down ? onHotkeyDown() : onHotkeyUp()
        default:
            break
        }
    }
}
