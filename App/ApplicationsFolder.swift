import AppKit
import TiroirUI

/// Offers, once, to move Tiroir into Applications when it was opened from somewhere else, such as the disk image or
/// Downloads: login items and updates need it to stay in one place, and macOS 27 lets only apps in /Applications change
/// the menu bar. Pattern from Islet.
@MainActor
enum ApplicationsFolder {
    private static let declinedKey = "declinedMoveToApplications"

    static var isInApplications: Bool {
        Bundle.main.bundleURL.deletingLastPathComponent().path == "/Applications"
    }

    /// Development builds live in build folders: never offer to move those.
    static var isDevelopmentBuild: Bool {
        let path = Bundle.main.bundleURL.path
        return path.contains("/.build/") || path.contains("/DerivedData/")
    }

    /// Asks once; a refusal is remembered.
    static func offerIfNeeded() {
        guard !isInApplications, !isDevelopmentBuild, !UserDefaults.standard.bool(forKey: declinedKey) else { return }
        let alert = NSAlert()
        alert.messageText = Strings.moveToApplicationsQuestion
        alert.informativeText = Strings.moveToApplicationsReason
        alert.addButton(withTitle: Strings.moveToApplications)
        alert.addButton(withTitle: Strings.notNow)
        alert.icon = NSApp.applicationIconImage
        NSApp.activate()
        guard alert.runModal() == .alertFirstButtonReturn else {
            UserDefaults.standard.set(true, forKey: declinedKey)
            return
        }
        moveNow()
    }

    /// Copies Tiroir to /Applications (the copy already there goes to the Trash), opens the copy and quits.
    static func moveNow() {
        let bundle = Bundle.main.bundleURL
        let destination = URL(fileURLWithPath: "/Applications").appendingPathComponent(bundle.lastPathComponent)
        guard destination.standardizedFileURL != bundle.standardizedFileURL else { return }
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.trashItem(at: destination, resultingItemURL: nil)
            }
            try FileManager.default.copyItem(at: bundle, to: destination)
        } catch {
            NSAlert(error: error).runModal()
            return
        }
        // Open the copy once this process has exited, then quit; the disk image can then be ejected.
        let relaunch = Process()
        relaunch.executableURL = URL(fileURLWithPath: "/bin/sh")
        relaunch.arguments = ["-c", "sleep 0.5; /usr/bin/open \"$0\"", destination.path]
        try? relaunch.run()
        NSApp.terminate(nil)
    }
}
