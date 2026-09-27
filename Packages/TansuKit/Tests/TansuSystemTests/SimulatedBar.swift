import AppKit
import TansuCore
@testable import TansuSystem

/// A menu bar in memory that behaves like macOS 26's for Command-drags: icons are laid out from the right edge, and an
/// icon dropped over the left half of another lands on its left.
@MainActor
final class SimulatedBar: StatusWindowSource, EventPosting, @unchecked Sendable {
    struct Entry {
        var windowID: UInt32
        var bundleID: String
        var key: String = ""
        var width: CGFloat
        var pid: pid_t
        var isFixed = false
    }

    static let controlCenterPID: pid_t = 707
    static let dividerWindow: UInt32 = 1
    static let screenWidth: CGFloat = 1512

    /// Right to left.
    var entries: [Entry]
    var ignoresDrags = false
    var openMenuOwners: Set<pid_t> = []
    private(set) var drags: [(window: UInt32, end: CGPoint, route: PostingRoute)] = []
    private(set) var clicks: [UInt32] = []

    init(apps: [(bundleID: String, width: CGFloat)]) {
        var entries: [Entry] = [
            Entry(windowID: 900, bundleID: "com.apple.controlcenter", key: "com.apple.menuextra.clock", width: 151, pid: Self.controlCenterPID, isFixed: true),
            Entry(windowID: 901, bundleID: "com.apple.controlcenter", key: "com.apple.menuextra.controlcenter", width: 42, pid: Self.controlCenterPID, isFixed: true),
        ]
        for (index, app) in apps.enumerated() {
            entries.append(Entry(windowID: UInt32(100 + index), bundleID: app.bundleID, width: app.width, pid: pid_t(2000 + index)))
        }
        // New status items appear at the far left: the divider starts there.
        entries.append(Entry(windowID: Self.dividerWindow, bundleID: "ch.rubencatalao.tansu", key: "divider", width: 1, pid: 1))
        self.entries = entries
    }

    func frames() -> [UInt32: CGRect] {
        var x = Self.screenWidth
        var result: [UInt32: CGRect] = [:]
        for entry in entries {
            x -= entry.width
            result[entry.windowID] = CGRect(x: x, y: 0, width: entry.width, height: 33)
        }
        return result
    }

    func frame(_ windowID: UInt32) -> CGRect? { frames()[windowID] }

    /// Bundle identifiers from left to right, the divider written as "|".
    var order: [String] {
        entries.reversed().filter { !$0.isFixed }.map { $0.windowID == Self.dividerWindow ? "|" : $0.bundleID }
    }

    func setDividerWidth(_ width: CGFloat) {
        guard let index = entries.firstIndex(where: { $0.windowID == Self.dividerWindow }) else { return }
        entries[index].width = width
    }

    // MARK: StatusWindowSource

    nonisolated func statusWindows() -> [StatusWindow] {
        MainActor.assumeIsolated {
            let frames = self.frames()
            return entries.map { StatusWindow(id: $0.windowID, frame: frames[$0.windowID]!, ownerPID: Self.controlCenterPID) }
        }
    }

    nonisolated func openMenuFrames(ownerPIDs: Set<pid_t>) -> [CGRect] {
        MainActor.assumeIsolated {
            openMenuOwners.isDisjoint(with: ownerPIDs) ? [] : [CGRect(x: 0, y: 33, width: 200, height: 300)]
        }
    }

    // MARK: EventPosting

    func commandDrag(windowID: UInt32, ownerPID: pid_t, from start: CGPoint, to end: CGPoint, destinationWindowID: UInt32?, route: PostingRoute) async {
        drags.append((windowID, end, route))
        guard !ignoresDrags, let index = entries.firstIndex(where: { $0.windowID == windowID }), !entries[index].isFixed else { return }
        let lifted = entries.remove(at: index)
        let frames = self.frames()
        var insertion = entries.filter { frames[$0.windowID]!.midX > end.x }.count
        insertion = max(insertion, entries.filter(\.isFixed).count)
        entries.insert(lifted, at: min(insertion, entries.count))
    }

    func click(windowID: UInt32, ownerPID: pid_t, at point: CGPoint, route: PostingRoute) async {
        clicks.append(windowID)
    }
}

@MainActor
final class SimulatedDivider: ArrangingDivider {
    let bar: SimulatedBar
    private(set) var isExpanded = false
    private(set) var removed = false

    init(bar: SimulatedBar) { self.bar = bar }

    var frame: CGRect? { removed ? nil : bar.frame(SimulatedBar.dividerWindow) }
    func expand() { bar.setDividerWidth(10_000); isExpanded = true }
    func relax() { bar.setDividerWidth(1); isExpanded = false }
    func setArranging() { bar.setDividerWidth(24); isExpanded = false }
    func remove() {
        bar.entries.removeAll { $0.windowID == SimulatedBar.dividerWindow }
        removed = true
        isExpanded = false
    }
}

/// Apps describe their icons with the same frames as their windows, as on macOS 26.5.
@MainActor
final class SimulatedIcons: IconSource {
    let bar: SimulatedBar
    var isTrusted = true
    private(set) var pressed: [String] = []
    var refusesPress: Set<String> = []

    init(bar: SimulatedBar) { self.bar = bar }

    func find() async -> [FoundIcon] {
        guard isTrusted else { return [] }
        let frames = bar.frames()
        return bar.entries.filter { $0.windowID != SimulatedBar.dividerWindow }.map { entry in
            let bundleID = entry.bundleID
            let refuses = refusesPress.contains(bundleID)
            let recorder = PressRecorder(icons: self)
            return FoundIcon(
                app: RunningApp(pid: entry.pid, bundleID: bundleID, name: bundleID.components(separatedBy: ".").last ?? bundleID),
                frame: frames[entry.windowID]!, identifier: entry.key.isEmpty ? nil : entry.key,
                press: { refuses ? false : recorder.press(bundleID) })
        }
    }

    func record(_ bundleID: String) { pressed.append(bundleID) }
}

/// Carries presses back to the main actor from a Sendable closure.
final class PressRecorder: @unchecked Sendable {
    weak var icons: SimulatedIcons?
    init(icons: SimulatedIcons) { self.icons = icons }
    func press(_ bundleID: String) -> Bool {
        MainActor.assumeIsolated { icons?.record(bundleID) }
        return true
    }
}

struct IdlePerson: UserActivitySource {
    var secondsSincePointerMoved: TimeInterval = 10
    var isMouseButtonDown = false
    var areModifiersDown = false
}

let instant: @Sendable (Duration) async -> Void = { _ in await Task.yield() }
