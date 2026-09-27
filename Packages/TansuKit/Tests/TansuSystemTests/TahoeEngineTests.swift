import AppKit
import Testing
import TansuCore
@testable import TansuSystem

@MainActor
@Suite struct TahoeEngineTests {
    let bar: SimulatedBar
    let icons: SimulatedIcons
    let divider: SimulatedDivider
    let engine: TahoeEngine

    init() {
        bar = SimulatedBar(apps: [
            ("com.google.drivefs", 32), ("com.protonmail.bridge", 38), ("com.anthropic.claudefordesktop", 40), ("ch.rubencatalao.pli", 38),
        ])
        icons = SimulatedIcons(bar: bar)
        let divider = SimulatedDivider(bar: bar)
        self.divider = divider
        engine = TahoeEngine(icons: icons, windows: bar, poster: bar, activity: IdlePerson(), makeDivider: { divider },
                             isOnScreen: { $0.maxX > 0 && $0.minX < SimulatedBar.screenWidth }, pause: instant)
    }

    /// A plan as LayoutPlanner makes it: every other icon of the bar is visible.
    func plan(hiding bundleIDs: Set<String>) -> VisibilityPlan {
        let concealed = Set(bundleIDs.map { IconID(bundleID: $0) })
        let everyone = Set(bar.entries.filter { $0.windowID != SimulatedBar.dividerWindow }.map { IconID(bundleID: $0.bundleID, key: $0.key) })
        return VisibilityPlan(visible: everyone.subtracting(concealed), concealed: concealed, hiddenApps: bundleIDs)
    }

    @Test func scanNamesEveryIconAndSkipsTheDivider() async {
        await engine.start()
        let snapshot = await engine.scan()
        #expect(snapshot.icons.count == 6)
        #expect(!snapshot.bundleIDs.contains("ch.rubencatalao.tansu"))
        #expect(snapshot.icon(IconID(bundleID: "com.google.drivefs"))?.windowID == 100)
        #expect(snapshot.icon(IconID(bundleID: "com.apple.controlcenter", key: "com.apple.menuextra.clock"))?.isMovable == false)
        #expect(snapshot.icon(IconID(bundleID: "com.apple.controlcenter", key: "com.apple.menuextra.clock"))?.kind == .system)
    }

    @Test func applyCarriesMisplacedIconsLeftOfTheDividerAndHidesThem() async {
        await engine.start()
        #expect(bar.order == ["|", "ch.rubencatalao.pli", "com.anthropic.claudefordesktop", "com.protonmail.bridge", "com.google.drivefs"])
        let report = await engine.apply(plan(hiding: ["com.google.drivefs", "com.protonmail.bridge"]))
        #expect(Set(report.moved) == [IconID(bundleID: "com.google.drivefs"), IconID(bundleID: "com.protonmail.bridge")])
        #expect(report.failed.isEmpty)
        let divider = bar.order.firstIndex(of: "|")!
        #expect(bar.order.firstIndex(of: "com.google.drivefs")! < divider)
        #expect(bar.order.firstIndex(of: "com.protonmail.bridge")! < divider)
        #expect(bar.order.firstIndex(of: "com.anthropic.claudefordesktop")! > divider)
        #expect(self.divider.isExpanded)
    }

    /// Seen on a real menu bar: two neighbours hidden together came back swapped once Tansu quit.
    @Test func iconsHiddenTogetherKeepTheirOrder() async {
        await engine.start()
        let before = bar.order.filter { $0 != "|" }
        _ = await engine.apply(plan(hiding: ["ch.rubencatalao.pli", "com.anthropic.claudefordesktop"]))
        #expect(bar.order == ["ch.rubencatalao.pli", "com.anthropic.claudefordesktop", "|", "com.protonmail.bridge", "com.google.drivefs"])
        // Quitting takes the divider away: every icon shows, in the order it had.
        divider.remove()
        #expect(bar.order == before)
    }

    @Test func anIconOpenedFromADrawerGoesBackToItsOwnPlace() async throws {
        bar.entries.insert(SimulatedBar.Entry(windowID: 50, bundleID: "ch.rubencatalao.tansu", key: "drawer", width: 30, pid: 1), at: 2)
        await engine.start()
        _ = await engine.apply(plan(hiding: ["ch.rubencatalao.pli", "com.anthropic.claudefordesktop"]))
        let hidden = bar.order
        bar.openMenuOwners = [2003]
        try await engine.open(IconID(bundleID: "ch.rubencatalao.pli"), anchor: bar.frame(50)!)
        bar.openMenuOwners = []
        let deadline = ContinuousClock.now + .seconds(3)
        while bar.order != hidden, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(bar.order == hidden, "back next to the divider, not at the far left of the hidden icons")
    }

    /// Seen on a real menu bar: Claude has a second icon macOS keeps out of the menu bar, parked at x -1. Once Tansu
    /// hid the real one far left, the parked one became the rightmost and took its identity.
    @Test func anIconMacOSKeepsOutNeverShiftsTheOthers() async {
        icons.windowless = [FoundIcon(app: RunningApp(pid: 2002, bundleID: "com.anthropic.claudefordesktop", name: "Claude"),
                                      frame: CGRect(x: -1, y: 0, width: 42, height: 33))]
        await engine.start()
        #expect(await engine.scan().icon(IconID(bundleID: "com.anthropic.claudefordesktop")) != nil, "one icon: no rank in its name")
        _ = await engine.apply(plan(hiding: ["com.anthropic.claudefordesktop"]))
        let drags = bar.drags.count
        let again = await engine.apply(plan(hiding: ["com.anthropic.claudefordesktop"]))
        #expect(again.moved.isEmpty && again.failed.isEmpty)
        #expect(bar.drags.count == drags, "hidden once, left alone after")
    }

    @Test func twoIconsOfOneAppKeepTheirNamesWhenOneHides() async {
        bar.entries.insert(SimulatedBar.Entry(windowID: 120, bundleID: "com.google.drivefs", width: 30, pid: 2000), at: 3)
        await engine.start()
        let before = await engine.scan()
        let right = try? #require(before.icons.first { $0.id.bundleID == "com.google.drivefs" })
        let rightID = right?.id
        #expect(rightID == IconID(bundleID: "com.google.drivefs", key: "#0"))
        let plan = VisibilityPlan(visible: Set(before.icons.map(\.id)).subtracting([rightID!]), concealed: [rightID!], hiddenApps: [])
        _ = await engine.apply(plan)
        let after = await engine.scan()
        #expect(after.icon(rightID!)?.windowID == right?.windowID, "the hidden icon is still #0")
        let drags = bar.drags.count
        _ = await engine.apply(plan)
        #expect(bar.drags.count == drags)
    }

    /// Seen on a real menu bar: Pli, busy right after its move, missed the Accessibility timeout; its icon dropped out
    /// of the scan, nothing was left to hide, and the divider let it come back.
    @Test func anAppThatDoesNotAnswerKeepsItsIconsHidden() async {
        await engine.start()
        _ = await engine.apply(plan(hiding: ["ch.rubencatalao.pli"]))
        #expect(divider.isExpanded)
        icons.silent = ["ch.rubencatalao.pli"]
        let snapshot = await engine.scan()
        #expect(snapshot.icon(IconID(bundleID: "ch.rubencatalao.pli")) != nil, "known from its window")
        _ = await engine.apply(plan(hiding: ["ch.rubencatalao.pli"]))
        #expect(divider.isExpanded)
    }

    @Test func anIconWhoseWindowIsGoneIsGone() async {
        await engine.start()
        _ = await engine.scan()
        icons.silent = ["ch.rubencatalao.pli"]
        bar.entries.removeAll { $0.bundleID == "ch.rubencatalao.pli" }
        #expect(await engine.scan().icon(IconID(bundleID: "ch.rubencatalao.pli")) == nil)
    }

    @Test func showingEveryIconMovesNothing() async {
        await engine.start()
        _ = await engine.apply(plan(hiding: ["com.google.drivefs", "com.protonmail.bridge"]))
        let drags = bar.drags.count
        let report = await engine.apply(.showEverything)
        #expect(report.moved.isEmpty)
        #expect(bar.drags.count == drags)
        #expect(!divider.isExpanded)
        // Back to the layout: still no move, the divider just widens again.
        _ = await engine.apply(plan(hiding: ["com.google.drivefs", "com.protonmail.bridge"]))
        #expect(bar.drags.count == drags)
        #expect(divider.isExpanded)
    }

    @Test func iconsAlreadyInPlaceAreNotMovedAgain() async {
        await engine.start()
        _ = await engine.apply(plan(hiding: ["com.google.drivefs"]))
        let dragsBefore = bar.drags.count
        let report = await engine.apply(plan(hiding: ["com.google.drivefs"]))
        #expect(report.moved.isEmpty)
        #expect(bar.drags.count == dragsBefore)
        #expect(divider.isExpanded)
    }

    @Test func showingAnIconAgainCarriesItBack() async {
        await engine.start()
        _ = await engine.apply(plan(hiding: ["com.google.drivefs", "ch.rubencatalao.pli"]))
        let report = await engine.apply(plan(hiding: ["com.google.drivefs"]))
        #expect(report.moved == [IconID(bundleID: "ch.rubencatalao.pli")])
        #expect(bar.order.firstIndex(of: "ch.rubencatalao.pli")! > bar.order.firstIndex(of: "|")!)
    }

    @Test func nothingToHideRelaxesTheDivider() async {
        await engine.start()
        _ = await engine.apply(plan(hiding: ["com.google.drivefs"]))
        _ = await engine.apply(plan(hiding: []))
        #expect(!divider.isExpanded)
    }

    @Test func aMoveThatNeverLandsIsReportedNotRepeatedForever() async {
        await engine.start()
        bar.ignoresDrags = true
        let report = await engine.apply(plan(hiding: ["com.google.drivefs"]))
        #expect(report.failed == [IconID(bundleID: "com.google.drivefs")])
        #expect(bar.drags.count == 6, "every posting route and drop variant, then it gives up")
    }

    @Test func restoreRelaxesTheDivider() async {
        await engine.start()
        _ = await engine.apply(plan(hiding: ["com.google.drivefs"]))
        engine.restore()
        #expect(divider.removed)
        #expect(!divider.isExpanded)
    }

    @Test func permissionLossShowsEverything() async {
        await engine.start()
        _ = await engine.apply(plan(hiding: ["com.google.drivefs"]))
        icons.isTrusted = false
        let snapshot = await engine.scan()
        #expect(snapshot.icons.isEmpty)
        #expect(engine.status == .needsAccessibility)
        #expect(!divider.isExpanded)
    }

    @Test func aVisibleIconIsPressedWhereItIs() async throws {
        await engine.start()
        try await engine.open(IconID(bundleID: "com.anthropic.claudefordesktop"), anchor: nil)
        #expect(icons.pressed == ["com.anthropic.claudefordesktop"])
        #expect(bar.drags.isEmpty)
    }

    @Test func anIconThatRefusesThePressIsClicked() async throws {
        await engine.start()
        icons.refusesPress = ["com.anthropic.claudefordesktop"]
        try await engine.open(IconID(bundleID: "com.anthropic.claudefordesktop"), anchor: nil)
        #expect(bar.clicks == [102])
    }

    @Test func aConcealedIconComesNextToItsDrawerThenGoesBack() async throws {
        // Tansu's drawer item: a status item right of the other icons.
        bar.entries.insert(SimulatedBar.Entry(windowID: 50, bundleID: "ch.rubencatalao.tansu", key: "drawer", width: 30, pid: 1), at: 2)
        await engine.start()
        _ = await engine.apply(plan(hiding: ["com.google.drivefs"]))
        #expect(bar.order.firstIndex(of: "com.google.drivefs")! < bar.order.firstIndex(of: "|")!)
        let anchor = bar.frame(50)!
        bar.openMenuOwners = [2000]
        try await engine.open(IconID(bundleID: "com.google.drivefs"), anchor: anchor)
        #expect(icons.pressed == ["com.google.drivefs"])
        let drive = bar.frame(100)!, drawer = bar.frame(50)!
        #expect(drive.maxX <= drawer.minX + 1 && drive.maxX >= drawer.minX - 1,
                "the icon sits right next to its drawer, on screen, while its menu is open")
        // The menu closes: the icon goes back behind the divider.
        bar.openMenuOwners = []
        let deadline = ContinuousClock.now + .seconds(3)
        while bar.order.firstIndex(of: "com.google.drivefs")! > bar.order.firstIndex(of: "|")!, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(bar.order.firstIndex(of: "com.google.drivefs")! < bar.order.firstIndex(of: "|")!)
        #expect(divider.isExpanded)
    }

    @Test func aBusyPersonIsNeverFought() async {
        let busy = TahoeEngine(icons: icons, windows: bar, poster: bar,
                               activity: IdlePerson(secondsSincePointerMoved: 0, isMouseButtonDown: true),
                               makeDivider: { self.divider }, isOnScreen: { _ in true }, pause: instant)
        await busy.start()
        let report = await busy.apply(plan(hiding: ["com.google.drivefs"]))
        #expect(report.failed == [IconID(bundleID: "com.google.drivefs")])
        #expect(bar.drags.isEmpty)
    }
}
