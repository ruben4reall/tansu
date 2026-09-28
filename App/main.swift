import AppKit

// Tiroir is a menu bar app: no Dock icon and no main menu until a window opens (LSUIElement). The app's code lives in
// the TiroirKit package, where `swift test` covers it; this target adds the updater and the move to Applications.
let delegate = TiroirShellDelegate()
let application = NSApplication.shared
application.delegate = delegate
application.run()
