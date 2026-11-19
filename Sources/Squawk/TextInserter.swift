// Puts text at the cursor of whatever app is frontmost by pasting. Paste is
// the one insertion path that works in native, Electron and terminal apps alike.

import AppKit
import ApplicationServices

enum TextInserter {
    /// Stamped on every event posted here so the shortcut monitor can tell
    /// Squawk's own keystrokes from the user's.
    static let eventTag: Int64 = 0x5351_5741

    /// - Parameter leadingSpace: typed as a real Space key press before the
    ///   paste. Terminals and chat boxes trim whitespace off pasted text, so a
    ///   space inside the paste is not reliable; a keystroke is.
    static func paste(_ text: String, leadingSpace: Bool) {
        let pasteboard = NSPasteboard.general
        let saved = (pasteboard.pasteboardItems ?? []).map { item in
            item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
        }

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        // Convention from nspasteboard.org: clipboard managers skip entries
        // carrying this type, so dictation does not pile up in their history.
        pasteboard.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType"))
        let ours = pasteboard.changeCount

        if leadingSpace {
            press(49, flags: [])
        }
        press(9, flags: .maskCommand)

        // The target app reads the pasteboard asynchronously after Cmd+V, so
        // restoring immediately would paste the old clipboard instead.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            guard pasteboard.changeCount == ours else { return }
            pasteboard.clearContents()
            pasteboard.writeObjects(
                saved.map { entries in
                    let item = NSPasteboardItem()
                    for (type, data) in entries { item.setData(data, forType: type) }
                    return item
                })
        }
    }

    /// The character just before the insertion point in the focused text
    /// field, or nil when the app does not expose it (terminals, mostly).
    /// `.some(nil)` means the cursor is at the very start of the field.
    static func characterBeforeCursor() -> Character?? {
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
            let focused, CFGetTypeID(focused) == AXUIElementGetTypeID()
        else { return nil }
        let element = focused as! AXUIElement

        var selection: CFTypeRef?
        var range = CFRange()
        guard
            AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &selection) == .success,
            let selection, CFGetTypeID(selection) == AXValueGetTypeID(),
            AXValueGetValue(selection as! AXValue, .cfRange, &range)
        else { return nil }
        guard range.location > 0 else { return .some(nil) }

        var before = CFRange(location: range.location - 1, length: 1)
        var text: CFTypeRef?
        guard let query = AXValueCreate(.cfRange, &before),
            AXUIElementCopyParameterizedAttributeValue(
                element, kAXStringForRangeParameterizedAttribute as CFString, query, &text) == .success,
            let character = (text as? String)?.first
        else { return nil }
        return .some(character)
    }

    private static func press(_ key: CGKeyCode, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .combinedSessionState)
        for keyDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: keyDown)
            event?.flags = flags
            event?.setIntegerValueField(.eventSourceUserData, value: eventTag)
            event?.post(tap: .cgSessionEventTap)
        }
    }
}
