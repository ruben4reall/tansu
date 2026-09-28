import Foundation
import Testing
@testable import TiroirApp
import TiroirUI

@Suite struct LaunchOptionsTests {
    final class Scratch {
        let name = "ch.rubencatalao.tiroir.launch.\(UUID().uuidString)"
        let defaults: UserDefaults
        init() { defaults = UserDefaults(suiteName: name)! }
        deinit { discardDefaults(name) }
    }

    @Test func nothingSetMeansNormalLaunch() {
        let options = LaunchOptions.current(Scratch().defaults)
        #expect(!options.demo)
        #expect(options.welcomeStep == nil)
        #expect(options.openDrawer == nil)
        #expect(options.settingsPane == nil)
        #expect(!options.quiet)
    }

    /// The command line gives text (`-TiroirOpenDrawer 0`), `defaults write` gives numbers: both work.
    @Test func numbersArriveAsTextOrNumbers() {
        let scratch = Scratch()
        scratch.defaults.set("2", forKey: "TiroirWelcomeStep")
        scratch.defaults.set(0, forKey: "TiroirOpenDrawer")
        scratch.defaults.set("appearance", forKey: "TiroirSettingsPane")
        scratch.defaults.set(true, forKey: "TiroirDemo")
        let options = LaunchOptions.current(scratch.defaults)
        #expect(options.welcomeStep == 2)
        #expect(options.openDrawer == 0)
        #expect(options.settingsPane == .appearance)
        #expect(options.demo)
    }

    @Test func allOpensTheAllDrawer() {
        let scratch = Scratch()
        scratch.defaults.set("all", forKey: "TiroirOpenDrawer")
        #expect(LaunchOptions.current(scratch.defaults).openDrawer == -1)
    }
}

/// Removes a preferences domain a test made, and the empty file macOS would otherwise leave in ~/Library/Preferences.
func discardDefaults(_ name: String) {
    UserDefaults(suiteName: name)?.removePersistentDomain(forName: name)
    CFPreferencesAppSynchronize(name as CFString)
    let file = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Preferences/\(name).plist")
    try? FileManager.default.removeItem(at: file)
}
