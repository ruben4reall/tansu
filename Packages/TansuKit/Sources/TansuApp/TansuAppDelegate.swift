import AppKit
import TansuSystem

/// Tansu's application delegate. The app target subclasses it to add the Sparkle updater and the move to
/// /Applications, the only code that lives outside this package.
@MainActor
open class TansuAppDelegate: NSObject, NSApplicationDelegate {
    public private(set) var coordinator: Coordinator?

    public override init() {
        super.init()
    }

    /// The updater, provided by the app target.
    open func makeUpdater() -> UpdateChecking? { nil }

    /// Moves Tansu to /Applications and relaunches it from there; the app target provides it.
    open func moveToApplications() {}

    /// Offers once to move Tansu to /Applications; the app target provides it.
    open func offerToMoveToApplications() {}

    open func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        offerToMoveToApplications()
        let coordinator = Coordinator(options: .current(), updater: makeUpdater())
        coordinator.moveToApplicationsHandler = { [weak self] in self?.moveToApplications() }
        self.coordinator = coordinator
        Log.app.info("Tansu started")
        Task { await coordinator.start() }
    }

    open func applicationWillTerminate(_ notification: Notification) {
        coordinator?.shutdown()
    }

    /// Opening Tansu again from Finder or Spotlight opens Settings.
    open func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        coordinator?.interface.actions.openSettings(.layout)
        return false
    }

    open func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
