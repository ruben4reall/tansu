import Foundation
import Testing
@testable import TansuApp
import TansuUI

@Suite struct LaunchOptionsTests {
    final class Scratch {
        let name = "ch.rubencatalao.tansu.launch.\(UUID().uuidString)"
        let defaults: UserDefaults
        init() { defaults = UserDefaults(suiteName: name)! }
        deinit { defaults.removePersistentDomain(forName: name) }
    }

    @Test func nothingSetMeansNormalLaunch() {
        let options = LaunchOptions.current(Scratch().defaults)
        #expect(!options.demo)
        #expect(options.welcomeStep == nil)
        #expect(options.openDrawer == nil)
        #expect(options.settingsPane == nil)
        #expect(!options.quiet)
    }

    /// The command line gives text (`-TansuOpenDrawer 0`), `defaults write` gives numbers: both work.
    @Test func numbersArriveAsTextOrNumbers() {
        let scratch = Scratch()
        scratch.defaults.set("2", forKey: "TansuWelcomeStep")
        scratch.defaults.set(0, forKey: "TansuOpenDrawer")
        scratch.defaults.set("appearance", forKey: "TansuSettingsPane")
        scratch.defaults.set(true, forKey: "TansuDemo")
        let options = LaunchOptions.current(scratch.defaults)
        #expect(options.welcomeStep == 2)
        #expect(options.openDrawer == 0)
        #expect(options.settingsPane == .appearance)
        #expect(options.demo)
    }

    @Test func allOpensTheAllDrawer() {
        let scratch = Scratch()
        scratch.defaults.set("all", forKey: "TansuOpenDrawer")
        #expect(LaunchOptions.current(scratch.defaults).openDrawer == -1)
    }
}
