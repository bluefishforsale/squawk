// The dictation shortcut as data, plus the tracker that turns raw keyboard
// state into press, release and chord edges. A shortcut can be one modifier,
// several held together, or modifiers plus an ordinary key, so people whose
// single keys are all taken still have somewhere to put it.

import Foundation

public enum ModifierKey: CaseIterable, Sendable {
    case leftControl, rightControl
    case leftOption, rightOption
    case leftShift, rightShift
    case leftCommand, rightCommand
    case fn

    /// Device-dependent bits from IOLLEvent.h (NX_DEVICELCTLKEYMASK and
    /// friends), which is the only place macOS tells left from right.
    public var mask: UInt64 {
        switch self {
        case .leftControl: 0x1
        case .leftShift: 0x2
        case .rightShift: 0x4
        case .leftCommand: 0x8
        case .rightCommand: 0x10
        case .leftOption: 0x20
        case .rightOption: 0x40
        case .rightControl: 0x2000
        case .fn: 0x80_0000
        }
    }

    public var keycap: String {
        switch self {
        case .leftControl: "left ⌃"
        case .rightControl: "right ⌃"
        case .leftOption: "left ⌥"
        case .rightOption: "right ⌥"
        case .leftShift: "left ⇧"
        case .rightShift: "right ⇧"
        case .leftCommand: "left ⌘"
        case .rightCommand: "right ⌘"
        case .fn: "fn"
        }
    }

    public static let allMasks = allCases.reduce(UInt64(0)) { $0 | $1.mask }
}

public struct KeyBinding: Codable, Equatable, Sendable {
    public var modifiers: UInt64
    public var keyCode: UInt16?
    /// What the key printed when it was learned. Stored because the same key
    /// code is a different letter on another keyboard layout.
    public var keyLabel: String?

    public init(modifiers: UInt64, keyCode: UInt16? = nil, keyLabel: String? = nil) {
        self.modifiers = modifiers & ModifierKey.allMasks
        self.keyCode = keyCode
        self.keyLabel = keyLabel
    }

    public static let rightOption = KeyBinding(modifiers: ModifierKey.rightOption.mask)

    public var keycaps: [String] {
        ModifierKey.allCases.filter { modifiers & $0.mask != 0 }.map(\.keycap)
            + (keyCode.map { [keyLabel ?? "key \($0)"] } ?? [])
    }

    /// F1 through F20. These type nothing, so they are safe to bind bare.
    private static let functionKeys: Set<UInt16> = [
        122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111, 105, 107, 113, 106, 64, 79, 80, 90,
    ]

    /// A bare letter or space as the shortcut would make that key untypeable.
    public var isUsable: Bool {
        guard let keyCode else { return modifiers != 0 }
        return modifiers != 0 || Self.functionKeys.contains(keyCode)
    }
}

public struct BindingTracker {
    public enum Edge: Equatable, Sendable {
        case down
        case up
        /// A key outside the shortcut was pressed.
        case chord
    }

    public var binding: KeyBinding {
        didSet { reset() }
    }
    private var modifiers: UInt64 = 0
    private var keyHeld = false
    private var active = false

    public init(binding: KeyBinding) {
        self.binding = binding
    }

    public mutating func reset() {
        modifiers = 0
        keyHeld = false
        active = false
    }

    public mutating func modifiersChanged(_ flags: UInt64) -> [Edge] {
        modifiers = flags & ModifierKey.allMasks
        return settle()
    }

    /// `swallow` is true for the shortcut's own key, which must not reach the
    /// focused app or holding Control+Space would type spaces into it.
    public mutating func keyDown(_ code: UInt16) -> (edges: [Edge], swallow: Bool) {
        guard code == binding.keyCode, modifiers == binding.modifiers else {
            return ([.chord], false)
        }
        keyHeld = true
        return (settle(), true)
    }

    public mutating func keyUp(_ code: UInt16) -> (edges: [Edge], swallow: Bool) {
        guard code == binding.keyCode, keyHeld else { return ([], false) }
        keyHeld = false
        return (settle(), true)
    }

    private mutating func settle() -> [Edge] {
        let keySatisfied = binding.keyCode == nil || keyHeld
        let wanted = modifiers == binding.modifiers && keySatisfied
        guard wanted != active else { return [] }
        active = wanted
        guard !wanted else { return [.down] }
        // An extra modifier on top of the shortcut means the user went on to
        // some other shortcut, so the recording is thrown away, not pasted.
        let addedModifier = modifiers & binding.modifiers == binding.modifiers && modifiers != binding.modifiers
        return addedModifier ? [.chord, .up] : [.up]
    }
}
