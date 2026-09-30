import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// Writes the corrected text back into the source text field.
enum TextReplacer {
    static func replaceAll(in target: FocusedText, with newText: String) {
        // Electron text boxes accept AX writes inconsistently, so go straight to paste there.
        if !target.isElectron, replaceViaAX(target.element, original: target.text, with: newText) {
            return
        }
        replaceViaPaste(newText)
    }

    private static func replaceViaAX(_ element: AXUIElement, original: String, with newText: String) -> Bool {
        var range = CFRange(location: 0, length: (original as NSString).length)
        guard let rangeValue = AXValueCreate(.cfRange, &range),
              AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, rangeValue) == .success,
              AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, newText as CFString) == .success
        else { return false }
        return AX.value(element) == newText
    }

    /// Select-all + paste, restoring the user's clipboard afterwards.
    private static func replaceViaPaste(_ newText: String) {
        let pasteboard = NSPasteboard.general
        let saved: [[NSPasteboard.PasteboardType: Data]] = (pasteboard.pasteboardItems ?? []).map { item in
            var entry: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) { entry[type] = data }
            }
            return entry
        }

        postKey(CGKeyCode(kVK_ANSI_A), flags: .maskCommand)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            pasteboard.clearContents()
            pasteboard.setString(newText, forType: .string)
            postKey(CGKeyCode(kVK_ANSI_V), flags: .maskCommand)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                pasteboard.clearContents()
                let items = saved.map { entry -> NSPasteboardItem in
                    let item = NSPasteboardItem()
                    for (type, data) in entry { item.setData(data, forType: type) }
                    return item
                }
                if !items.isEmpty { pasteboard.writeObjects(items) }
            }
        }
    }

    private static func postKey(_ key: CGKeyCode, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .hidSystemState)
        for isDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: isDown)
            event?.flags = flags
            event?.post(tap: .cghidEventTap)
        }
    }
}
