// Puts text at the cursor of whatever app is frontmost by pasting. Paste is
// the one insertion path that works in native, Electron and terminal apps alike.

import AppKit

enum TextInserter {
    static func paste(_ text: String) {
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

        let source = CGEventSource(stateID: .combinedSessionState)
        let vKey: CGKeyCode = 9
        for keyDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: keyDown)
            event?.flags = .maskCommand
            event?.post(tap: .cgSessionEventTap)
        }

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
}
