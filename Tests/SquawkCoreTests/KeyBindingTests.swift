import Testing

@testable import SquawkCore

@Suite struct KeyBindingTests {
    private let rightOption = ModifierKey.rightOption.mask
    private let rightCommand = ModifierKey.rightCommand.mask
    private let leftOption = ModifierKey.leftOption.mask
    private let leftControl = ModifierKey.leftControl.mask
    private let space: UInt16 = 49

    @Test func singleModifierPressAndRelease() {
        var tracker = BindingTracker(binding: .rightOption)
        #expect(tracker.modifiersChanged(rightOption) == [.down])
        #expect(tracker.modifiersChanged(0) == [.up])
    }

    @Test func leftOptionDoesNotTriggerRightOptionBinding() {
        var tracker = BindingTracker(binding: .rightOption)
        #expect(tracker.modifiersChanged(leftOption) == [])
    }

    @Test func capsLockAndOtherFlagBitsAreIgnored() {
        var tracker = BindingTracker(binding: .rightOption)
        #expect(tracker.modifiersChanged(rightOption | 0x10000 | 0x100) == [.down])
    }

    @Test func twoModifierBindingNeedsBothHeld() {
        var tracker = BindingTracker(binding: KeyBinding(modifiers: rightOption | rightCommand))
        #expect(tracker.modifiersChanged(rightCommand) == [])
        #expect(tracker.modifiersChanged(rightCommand | rightOption) == [.down])
        #expect(tracker.modifiersChanged(rightOption) == [.up])
    }

    @Test func extraModifierOnTopOfBindingIsAChordNotAFinish() {
        var tracker = BindingTracker(binding: .rightOption)
        _ = tracker.modifiersChanged(rightOption)
        #expect(tracker.modifiersChanged(rightOption | rightCommand) == [.chord, .up])
    }

    @Test func ordinaryKeyWhileHoldingIsAChordAndStillTypes() {
        var tracker = BindingTracker(binding: .rightOption)
        _ = tracker.modifiersChanged(rightOption)
        let result = tracker.keyDown(14)
        #expect(result.edges == [.chord])
        #expect(!result.swallow)
    }

    @Test func modifierPlusKeyBindingSwallowsOnlyItsOwnKey() {
        var tracker = BindingTracker(binding: KeyBinding(modifiers: leftControl, keyCode: space, keyLabel: "Space"))
        #expect(tracker.modifiersChanged(leftControl) == [])
        let down = tracker.keyDown(space)
        #expect(down.edges == [.down])
        #expect(down.swallow)
        let up = tracker.keyUp(space)
        #expect(up.edges == [.up])
        #expect(up.swallow)
    }

    @Test func keyRepeatWhileHoldingDoesNotRestartOrLeak() {
        var tracker = BindingTracker(binding: KeyBinding(modifiers: leftControl, keyCode: space))
        _ = tracker.modifiersChanged(leftControl)
        _ = tracker.keyDown(space)
        let again = tracker.keyDown(space)
        #expect(again.edges == [])
        #expect(again.swallow)
    }

    @Test func boundKeyWithoutItsModifiersTypesNormally() {
        var tracker = BindingTracker(binding: KeyBinding(modifiers: leftControl, keyCode: space))
        let result = tracker.keyDown(space)
        #expect(!result.swallow)
        #expect(!tracker.keyUp(space).swallow)
    }

    @Test func releasingModifierBeforeKeyEndsDictationOnce() {
        var tracker = BindingTracker(binding: KeyBinding(modifiers: leftControl, keyCode: space))
        _ = tracker.modifiersChanged(leftControl)
        _ = tracker.keyDown(space)
        #expect(tracker.modifiersChanged(0) == [.up])
        let up = tracker.keyUp(space)
        #expect(up.edges == [])
        #expect(up.swallow)
    }

    @Test func bareLetterIsRejectedButBareFunctionKeyIsFine() {
        #expect(!KeyBinding(modifiers: 0, keyCode: space).isUsable)
        #expect(KeyBinding(modifiers: 0, keyCode: 105, keyLabel: "F13").isUsable)
        #expect(KeyBinding(modifiers: leftControl, keyCode: space).isUsable)
        #expect(!KeyBinding(modifiers: 0).isUsable)
    }

    @Test func keycapsListModifiersThenKey() {
        let binding = KeyBinding(modifiers: rightOption | leftControl, keyCode: space, keyLabel: "Space")
        #expect(binding.keycaps == ["left ⌃", "right ⌥", "Space"])
    }
}

@Suite struct NameEntryTests {
    @Test func aliasesSplitOnCommasAndDropBlanks() {
        let entry = NameEntry(text: " Terrac ", soundsLike: "terek, tarik ,, Derrick")
        #expect(entry.name == "Terrac")
        #expect(entry.aliases == ["terek", "tarik", "Derrick"])
    }

    @Test func trainingAddsWhatWasHeardWithoutPunctuation() {
        var entry = NameEntry(text: "Terrac", soundsLike: "terek")
        entry.learn(heard: " Tarik. ")
        #expect(entry.soundsLike == "terek, Tarik")
    }

    @Test func trainingIgnoresCorrectAndAlreadyKnownHearings() {
        var entry = NameEntry(text: "Terrac", soundsLike: "terek")
        entry.learn(heard: "terrac")
        entry.learn(heard: "Terek.")
        entry.learn(heard: "  ")
        #expect(entry.soundsLike == "terek")
    }
}
