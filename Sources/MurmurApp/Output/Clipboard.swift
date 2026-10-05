import AppKit

/// Final text always goes to the general pasteboard. Auto-paste (Milestone 4) builds on this.
@MainActor
enum Clipboard {
    static func copy(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}
