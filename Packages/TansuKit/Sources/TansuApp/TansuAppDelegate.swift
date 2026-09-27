import AppKit
import TansuCore
import TansuSystem

/// Tansu's application delegate. The app target subclasses it to add the Sparkle updater, the only code that lives
/// outside this package.
@MainActor
open class TansuAppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?

    public override init() {
        super.init()
    }

    open func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = "tansu.main"
        item.button?.title = "Tansu"
        statusItem = item
        Log.app.info("Tansu started")
    }
}
