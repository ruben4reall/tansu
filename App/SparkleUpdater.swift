import AppKit
import Sparkle
import TansuApp

/// Tansu's only network code: Sparkle reads the update feed on the website and installs EdDSA-signed disk images from
/// GitHub Releases. The welcome asks whether to check automatically. Debug builds never start it, so a development
/// copy is never replaced by a release.
@MainActor
final class SparkleUpdater: NSObject, UpdateChecking {
    private let reminders = UpdateReminders()
    private let controller: SPUStandardUpdaterController

    override init() {
        // Sparkle takes its delegates only here; the updater starts in `start()`, once everything is wired.
        controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: reminders)
        super.init()
    }

    func start() {
        #if !DEBUG
        controller.startUpdater()
        #endif
    }

    var canCheckForUpdates: Bool { controller.updater.canCheckForUpdates }

    var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}

/// Sparkle's gentle reminders, for an app without a Dock icon: an update found by a scheduled check waits for the next
/// time the person looks, instead of an alert that would take the focus from the app in use.
@MainActor
private final class UpdateReminders: NSObject, @preconcurrency SPUStandardUserDriverDelegate {
    var supportsGentleScheduledUpdateReminders: Bool { true }
}

/// The package's delegate, with Sparkle as its updater and the move to Applications (only this target links Sparkle).
final class TansuShellDelegate: TansuAppDelegate {
    override func makeUpdater() -> UpdateChecking? {
        SparkleUpdater()
    }

    override func moveToApplications() {
        ApplicationsFolder.moveNow()
    }

    override func offerToMoveToApplications() {
        ApplicationsFolder.offerIfNeeded()
    }
}
