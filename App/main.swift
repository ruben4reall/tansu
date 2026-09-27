import AppKit
import TansuApp

// Tansu is a menu bar app: no Dock icon and no main menu until a window opens (LSUIElement). The app's code lives
// in the TansuKit package, where `swift test` covers it; this target only adds the updater.
let delegate = TansuAppDelegate()
let application = NSApplication.shared
application.delegate = delegate
application.run()
