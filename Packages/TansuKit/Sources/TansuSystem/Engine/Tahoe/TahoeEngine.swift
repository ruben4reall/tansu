import AppKit
import TansuCore

/// The macOS 26 engine (spec 4.3): Tansu's divider pushes concealed icons off screen; synthetic Command-drags carry
/// icons across it; an icon opened from a drawer is brought next to the drawer's mark for the time its menu is open.
@MainActor
public final class TahoeEngine: MenuBarEngine {
    public let kind = EngineKind.tahoe
    public let granularity = Granularity.icon
    public private(set) var status: EngineStatus = .ready {
        didSet { if status != oldValue { onStatusChange?(status) } }
    }
    public var onStatusChange: (@MainActor (EngineStatus) -> Void)?
    /// How long an icon opened from a drawer stays after its menu closes.
    public var rehideDelay: TimeInterval = 0.5

    private let icons: IconSource
    private let windows: StatusWindowSource
    private let mover: ItemMover
    private let poster: EventPosting
    private let activity: UserActivitySource
    private let makeDivider: @MainActor () -> DividerControlling
    private let isOnScreen: @MainActor (CGRect) -> Bool
    private let pause: @Sendable (Duration) async -> Void

    private var divider: DividerControlling?
    private var pressers: [IconID: @Sendable () -> Bool] = [:]
    private var windowOwners: [UInt32: pid_t] = [:]
    private var lastSnapshot = MenuBarSnapshot.empty
    private var wantsConcealed = false
    private var shown: (icon: IconID, task: Task<Void, Never>, beside: IconID?)?
    /// The identity each icon window had at the last scan.
    private var identityByWindow: [UInt32: IconID] = [:]
    /// Icons that could not be moved, and when: they wait a minute before another try, so a failing move never
    /// repeats with every change of the menu bar.
    private var recentFailures: [UInt32: ContinuousClock.Instant] = [:]
    static let retryAfter: Duration = .seconds(60)

    /// While Tansu moves icons, the divider is this wide, so a drop can land on either side of it.
    static let arrangingLength: CGFloat = 24
    /// Whether a drop at this x (window server coordinates) is safe: far enough from the notch, where macOS places no
    /// icon and where apps drawn around the notch catch drops.
    private let isSafeDrop: @MainActor (CGFloat) -> Bool

    public init(
        icons: IconSource, windows: StatusWindowSource = SystemStatusWindows(), poster: EventPosting,
        activity: UserActivitySource = SystemUserActivity(),
        makeDivider: @escaping @MainActor () -> DividerControlling = { Divider() },
        isOnScreen: @escaping @MainActor (CGRect) -> Bool = { ScreenCoordinates.isOnScreen($0) },
        isSafeDrop: @escaping @MainActor (CGFloat) -> Bool = { TahoeEngine.isClearOfNotch($0) },
        pause: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) }
    ) {
        self.icons = icons
        self.windows = windows
        self.poster = poster
        self.activity = activity
        self.makeDivider = makeDivider
        self.isOnScreen = isOnScreen
        self.isSafeDrop = isSafeDrop
        self.pause = pause
        mover = ItemMover(windows: windows, poster: poster, activity: activity, pause: pause)
    }

    public func start() async {
        if divider == nil { divider = makeDivider() }
        refreshStatus()
    }

    func refreshStatus() {
        status = icons.isTrusted ? .ready : .needsAccessibility
        if status != .ready {
            // Without Accessibility nothing can be moved back: nothing stays hidden.
            divider?.relax()
        }
    }

    // MARK: Scanning

    public func scan() async -> MenuBarSnapshot {
        refreshStatus()
        guard status == .ready else { return .empty }
        let found = await icons.find()
        let listed = windows.statusWindows()
        let ownFrames = [divider?.frame].compactMap { $0 }
        let others = listed.filter { window in !ownFrames.contains { Self.sameWindow($0, window.frame) } }
        windowOwners = Dictionary(listed.map { ($0.id, $0.ownerPID) }, uniquingKeysWith: { first, _ in first })

        let matches = FrameMatcher.match(
            elements: found.enumerated().map { FrameMatcher.Element(index: $0.offset, frame: $0.element.frame) },
            windows: others.map { FrameMatcher.Window(id: $0.id, frame: $0.frame) })
        let windowsByID = Dictionary(others.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        // An icon without a window is one macOS itself keeps out of the menu bar ("Allow in the Menu Bar"): it is left
        // out before an app's icons are numbered, so it never shifts the others' identities.
        let windowed = found.enumerated().compactMap { index, icon in matches[index].map { (icon, $0) } }

        var result: [MenuBarIcon] = []
        var presses: [IconID: @Sendable () -> Bool] = [:]
        for entry in stableIdentities(windowed) {
            guard let window = windowsByID[entry.windowID] else { continue }
            let kind = IconAssembly.kind(of: entry.id.bundleID)
            let icon = MenuBarIcon(
                id: entry.id, ownerName: entry.found.app.name,
                label: IconAssembly.displayLabel(entry.found.label, kind: kind), frame: window.frame,
                isOnScreen: isOnScreen(window.frame),
                isMovable: !IconIdentity.fixedSystemIdentifiers.contains(entry.id.key),
                kind: kind, windowID: entry.windowID, pid: entry.found.app.pid)
            result.append(icon)
            presses[entry.id] = entry.found.press
        }
        // An app that did not answer in time keeps the icons it had, as long as their windows are still listed: the
        // window list does not depend on the app. Without this, a busy app's hidden icon would come back.
        let seen = Set(result.compactMap(\.windowID))
        for previous in lastSnapshot.icons {
            guard let windowID = previous.windowID, !seen.contains(windowID), let window = windowsByID[windowID],
                  !result.contains(where: { $0.id == previous.id }) else { continue }
            var carried = previous
            carried.frame = window.frame
            carried.isOnScreen = isOnScreen(window.frame)
            result.append(carried)
            presses[previous.id] = pressers[previous.id]
        }
        pressers = presses
        lastSnapshot = MenuBarSnapshot(icons: result)
        return lastSnapshot
    }

    /// Identities of an app's icons. An icon keeps the identity it had as long as its window lives, even when a move
    /// changes its rank among its app's icons (hiding the right one of two would otherwise swap them); icons seen for
    /// the first time are named by rank, skipping the ranks already taken.
    private func stableIdentities(_ windowed: [(FoundIcon, UInt32)]) -> [(found: FoundIcon, windowID: UInt32, id: IconID)] {
        var result: [(found: FoundIcon, windowID: UInt32, id: IconID)] = []
        for (bundleID, group) in Dictionary(grouping: windowed, by: { $0.0.app.bundleID }) {
            let ordered = group.sorted { $0.0.frame.midX > $1.0.frame.midX }
            var assigned: [UInt32: IconID] = [:]
            var used = Set<IconID>()
            for (_, window) in ordered {
                if let previous = identityByWindow[window], previous.bundleID == bundleID, used.insert(previous).inserted {
                    assigned[window] = previous
                }
            }
            for (rank, (icon, window)) in ordered.enumerated() where assigned[window] == nil {
                var next = rank
                var id = IconIdentity.make(bundleID: bundleID, identifier: icon.identifier, indexFromRight: next, countForApp: ordered.count)
                while used.contains(id), icon.identifier == nil, next < ordered.count * 2 {
                    next += 1
                    id = IconIdentity.make(bundleID: bundleID, identifier: nil, indexFromRight: next, countForApp: ordered.count)
                }
                used.insert(id)
                assigned[window] = id
            }
            result.append(contentsOf: ordered.compactMap { icon, window in assigned[window].map { (icon, window, $0) } })
        }
        identityByWindow = Dictionary(result.map { ($0.windowID, $0.id) }, uniquingKeysWith: { first, _ in first })
        return result
    }

    static func sameWindow(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) <= 2 && abs(a.width - b.width) <= 2
    }

    // MARK: Arranging

    public func apply(_ plan: VisibilityPlan) async -> ApplyReport {
        guard let divider else { return .nothing }
        wantsConcealed = !plan.concealed.isEmpty
        guard wantsConcealed else {
            // A narrow divider hides nothing: every icon shows without a single move, and each keeps its place for
            // the next time some hide.
            divider.relax()
            return .nothing
        }
        var snapshot = await scan()
        guard status == .ready, let dividerFrame = divider.frame else { return .nothing }
        var moves = LayoutPlanner.moves(plan: plan, snapshot: snapshot, dividerFrame: dividerFrame)
        var report = ApplyReport()
        if !moves.isEmpty {
            // With the divider narrow and every icon on screen, each drop lands on a real place. macOS lays the bar
            // out again, and may still be placing Tansu's own items after a launch: wait until nothing moves.
            setArranging(divider)
            await waitForStillBar()
            snapshot = await scan()
            if let arrangingFrame = divider.frame {
                moves = LayoutPlanner.moves(plan: plan, snapshot: snapshot, dividerFrame: arrangingFrame)
            }
            for move in moves {
                guard let icon = snapshot.icon(move.icon), let windowID = icon.windowID,
                      let dividerFrame = divider.frame else {
                    report.failed.append(move.icon)
                    continue
                }
                let dividerWindow = windows.statusWindows().first { Self.sameWindow($0.frame, dividerFrame) }?.id
                if let failed = recentFailures[windowID], ContinuousClock.now - failed < Self.retryAfter {
                    report.failed.append(move.icon)
                    continue
                }
                do {
                    if move.to == .concealed {
                        try await conceal(windowID: windowID, ownerPID: windowOwners[windowID] ?? icon.pid, dividerWindow: dividerWindow)
                    } else {
                        try await mover.move(windowID: windowID, ownerPID: windowOwners[windowID] ?? icon.pid,
                                             to: .rightOf(dividerFrame, windowID: dividerWindow))
                    }
                    report.moved.append(move.icon)
                    recentFailures[windowID] = nil
                } catch {
                    report.failed.append(move.icon)
                    recentFailures[windowID] = .now
                }
            }
        }
        if wantsConcealed { divider.expand() } else { divider.relax() }
        if !report.moved.isEmpty || !report.failed.isEmpty {
            Log.engine.notice("applied: \(report.moved.count) moved, \(report.failed.count) failed")
        }
        return report
    }

    private func setArranging(_ divider: DividerControlling) {
        if let flexible = divider as? ArrangingDivider {
            flexible.setArranging()
        } else {
            divider.relax()
        }
    }

    // MARK: Opening

    public func open(_ id: IconID, anchor: CGRect?) async throws {
        await putBackShownIcon()
        let snapshot = await scan()
        guard status == .ready else { throw EngineError.notReady(status) }
        guard let icon = snapshot.icon(id), let windowID = icon.windowID else { throw EngineError.iconNotFound(id) }
        guard let divider, let dividerFrame = divider.frame else { throw EngineError.notReady(status) }

        let concealed = divider.isExpanded && icon.frame.midX < dividerFrame.maxX
        if !concealed {
            try await press(icon)
            return
        }
        // Bring the icon next to the drawer's mark, open it there, and put it back once its menu has closed, beside the
        // concealed icon that was its right neighbour.
        if let anchor, let anchorWindow = windows.statusWindows().first(where: { Self.sameWindow($0.frame, anchor) }) {
            let neighbour = Self.rightNeighbour(of: icon, in: snapshot, dividerFrame: dividerFrame)
            do {
                try await mover.move(windowID: windowID, ownerPID: windowOwners[windowID] ?? icon.pid,
                                     to: .leftOf(anchorWindow.frame, windowID: anchorWindow.id))
                await pause(.milliseconds(90))
                let moved = await scan().icon(id) ?? icon
                try await press(moved)
                watchUntilClosed(moved, thenPutBack: true, beside: neighbour)
                return
            } catch EngineError.personIsBusy {
                throw EngineError.personIsBusy
            } catch {
                // Fall through to the gentler way.
            }
        }
        // Without a move: let every hidden icon show for the time the menu is open.
        divider.relax()
        await pause(.milliseconds(220))
        guard let revealed = await scan().icon(id), revealed.isOnScreen else {
            if wantsConcealed { divider.expand() }
            throw EngineError.cannotOpen(id)
        }
        try await press(revealed)
        watchUntilClosed(revealed, thenPutBack: false, beside: nil)
    }

    private func press(_ icon: MenuBarIcon) async throws {
        if let presser = pressers[icon.id], presser() { return }
        guard let windowID = icon.windowID else { throw EngineError.cannotOpen(icon.id) }
        // Some apps (Electron ones among them) ignore the Accessibility action: a click does it.
        await poster.click(windowID: windowID, ownerPID: windowOwners[windowID] ?? icon.pid,
                           at: CGPoint(x: icon.frame.midX, y: icon.frame.midY), route: mover.workingRoute ?? .session)
    }

    /// Checks four times a second, only while an icon is shown, whether its menu is still open; once it has been
    /// closed for `rehideDelay` and no button is held, the icon goes back.
    private func watchUntilClosed(_ icon: MenuBarIcon, thenPutBack: Bool, beside neighbour: IconID?) {
        shown?.task.cancel()
        var owners: Set<pid_t> = [icon.pid]
        if let windowID = icon.windowID, let owner = windowOwners[windowID] { owners.insert(owner) }
        let task = Task { [weak self] in
            guard let self else { return }
            var closedSince: ContinuousClock.Instant?
            let started = ContinuousClock.now
            // A menu takes a moment to appear after the press.
            await self.pause(.milliseconds(400))
            while !Task.isCancelled {
                let open = !self.windows.openMenuFrames(ownerPIDs: owners).isEmpty || self.activity.isMouseButtonDown
                if open {
                    closedSince = nil
                } else if let since = closedSince {
                    if ContinuousClock.now - since >= .milliseconds(Int(self.rehideDelay * 1000)) { break }
                } else {
                    closedSince = .now
                }
                // Ten minutes is plenty for any menu.
                if ContinuousClock.now - started > .seconds(600) { break }
                await self.pause(.milliseconds(250))
            }
            guard !Task.isCancelled else { return }
            await self.finishShowing(icon, putBack: thenPutBack, beside: neighbour)
        }
        shown = (icon.id, task, neighbour)
    }

    private func finishShowing(_ icon: MenuBarIcon, putBack: Bool, beside neighbour: IconID?) async {
        shown = nil
        guard let divider else { return }
        if putBack {
            // The wide divider's left edge is off screen: narrow it so the icon can go right next to it, in the place
            // it had among the concealed icons, then widen it again.
            setArranging(divider)
            await waitForStillBar()
            let snapshot = await scan()
            if let frame = divider.frame, let current = snapshot.icon(icon.id), let windowID = current.windowID {
                let dividerWindow = windows.statusWindows().first { Self.sameWindow($0.frame, frame) }?.id
                do {
                    if let neighbour, let beside = snapshot.icon(neighbour), let besideWindow = beside.windowID,
                       beside.frame.maxX <= frame.minX + ItemMover.slack, isSafeDrop(beside.frame.minX) {
                        // Back in its own place among the concealed icons.
                        try await mover.move(windowID: windowID, ownerPID: windowOwners[windowID] ?? current.pid,
                                             to: .leftOf(beside.frame, windowID: besideWindow))
                    } else {
                        try await conceal(windowID: windowID, ownerPID: windowOwners[windowID] ?? current.pid, dividerWindow: dividerWindow)
                    }
                } catch {
                    Log.engine.error("an icon opened from a drawer could not go back")
                }
            }
        }
        if wantsConcealed { divider.expand() } else { divider.relax() }
    }

    /// Carries an icon behind the divider without ever dropping on the divider's left, where the notch, or an app drawn
    /// around it, can catch the drop: the icon comes right next to the divider, then the divider steps over it. Every
    /// drop lands on the right of the divider, among icons that show.
    private func conceal(windowID: UInt32, ownerPID: pid_t, dividerWindow: UInt32?) async throws {
        guard let divider, let dividerFrame = divider.frame, let dividerWindow else { throw EngineError.notReady(status) }
        try await mover.move(windowID: windowID, ownerPID: ownerPID, to: .rightOf(dividerFrame, windowID: dividerWindow))
        guard let iconFrame = mover.frame(of: windowID) else { throw EngineError.iconNotFound(IconID(bundleID: "window \(windowID)")) }
        try await mover.move(windowID: dividerWindow, ownerPID: windowOwners[dividerWindow] ?? ownerPID,
                             to: .rightOf(iconFrame, windowID: windowID))
    }

    /// Clear of the notch by 60 points, room for a drop and for the hover area of apps drawn around it.
    public static func isClearOfNotch(_ x: CGFloat) -> Bool {
        guard let screen = NSScreen.screens.first, let right = screen.auxiliaryTopRightArea else { return true }
        return x >= right.minX - screen.frame.minX + 60
    }

    /// Waits until the icons' windows hold still for three readings in a row, 50 ms apart, and 1.5 s at most.
    func waitForStillBar() async {
        await pause(.milliseconds(120))
        var previous: [StatusWindow] = []
        var still = 0
        for _ in 0..<30 {
            let now = windows.statusWindows()
            still = now == previous ? still + 1 : 0
            previous = now
            if still >= 2 { return }
            await pause(.milliseconds(50))
        }
    }

    /// The concealed icon right of `icon`, which it goes back beside; nil when the divider comes first.
    static func rightNeighbour(of icon: MenuBarIcon, in snapshot: MenuBarSnapshot, dividerFrame: CGRect) -> IconID? {
        snapshot.icons
            .filter { $0.id != icon.id && $0.frame.minX >= icon.frame.maxX - ItemMover.slack && $0.frame.maxX <= dividerFrame.minX + ItemMover.slack }
            .min { $0.frame.minX < $1.frame.minX }?.id
    }

    /// An icon still shown from a drawer goes back before another one opens.
    private func putBackShownIcon() async {
        guard let shown else { return }
        shown.task.cancel()
        self.shown = nil
        if let icon = lastSnapshot.icon(shown.icon) {
            await finishShowing(icon, putBack: true, beside: shown.beside)
        }
    }

    // MARK: Quitting

    public func restore() {
        shown?.task.cancel()
        shown = nil
        divider?.remove()
        divider = nil
    }
}

/// A divider that can hold a middle width while Tansu arranges icons.
@MainActor
public protocol ArrangingDivider: DividerControlling {
    func setArranging()
}

extension Divider: ArrangingDivider {}
