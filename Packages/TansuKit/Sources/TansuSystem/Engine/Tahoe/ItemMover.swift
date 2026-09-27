import CoreGraphics
import Foundation
import TansuCore

/// Moves one icon on macOS 26 and checks that it landed (spec 4.3, Arranging).
///
/// A move waits until the person pauses (no button held, no modifier, the pointer still for 50 ms) so it never
/// fights them, then posts one Command-drag and reads the window list until the icon settles. A move that did not
/// land is tried again through the next posting route; the route that worked is remembered.
@MainActor
public final class ItemMover {
    public enum Destination: Equatable, Sendable {
        /// Just left of the window at `frame`.
        case leftOf(CGRect, windowID: UInt32?)
        /// Just right of the window at `frame`.
        case rightOf(CGRect, windowID: UInt32?)

        var frame: CGRect {
            switch self {
            case .leftOf(let frame, _), .rightOf(let frame, _): frame
            }
        }

        var windowID: UInt32? {
            switch self {
            case .leftOf(_, let id), .rightOf(_, let id): id
            }
        }
    }

    let windows: StatusWindowSource
    let poster: EventPosting
    let activity: UserActivitySource
    let pause: @Sendable (Duration) async -> Void
    /// The posting route that moved the last icon.
    public private(set) var workingRoute: PostingRoute?

    /// Longest wait for the person to pause.
    static let patience: Duration = .seconds(2)
    /// How long a move may take to show in the window list.
    static let settleChecks = 10
    static let settleInterval: Duration = .milliseconds(40)
    /// Points of slack when checking where an icon landed.
    static let slack: CGFloat = 3

    public init(
        windows: StatusWindowSource, poster: EventPosting, activity: UserActivitySource,
        pause: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) }
    ) {
        self.windows = windows
        self.poster = poster
        self.activity = activity
        self.pause = pause
    }

    /// The posting route and drop variant that moved the last icon.
    public private(set) var workingVariant = 0

    /// Moves the icon window `windowID` and returns its new frame.
    @discardableResult
    public func move(windowID: UInt32, ownerPID: pid_t, to destination: Destination) async throws -> CGRect {
        for (route, variant) in attempts() {
            try await waitForPause()
            guard let current = frame(of: windowID) else { throw EngineError.iconNotFound(IconID(bundleID: "window \(windowID)")) }
            if landed(current, at: destination) { return current }
            let target = destination.windowID.flatMap(frame(of:)) ?? destination.frame
            let start = CGPoint(x: current.midX, y: current.midY)
            let end = Self.dropPoint(for: destination, target: target, moving: current, variant: variant)
            await poster.commandDrag(windowID: windowID, ownerPID: ownerPID, from: start, to: end,
                                     destinationWindowID: destination.windowID, route: route)
            for _ in 0..<Self.settleChecks {
                await pause(Self.settleInterval)
                if let now = frame(of: windowID), landed(now, at: destination) {
                    workingRoute = route
                    workingVariant = variant
                    return now
                }
            }
        }
        throw EngineError.moveFailed(IconID(bundleID: "window \(windowID)"))
    }

    /// The combinations to try, the one that worked last first; six at most.
    func attempts() -> [(PostingRoute, Int)] {
        var all: [(PostingRoute, Int)] = []
        for route in PostingRoute.allCases {
            for variant in 0..<3 { all.append((route, variant)) }
        }
        if let workingRoute {
            all.removeAll { $0 == (workingRoute, workingVariant) }
            all.insert((workingRoute, workingVariant), at: 0)
        }
        return Array(all.prefix(6))
    }

    /// Where to release. Over the left part of an icon, macOS drops the dragged one on its left; over the right part,
    /// on its right. Icons are laid out from the right edge, so lifting an icon slides every icon on its left to the
    /// right by its width: the variants cover that shift, no shift, and the opposite shift.
    static func dropPoint(for destination: Destination, target: CGRect, moving: CGRect, variant: Int) -> CGPoint {
        let movingLeft = moving.midX > target.midX
        let shift: CGFloat = switch variant {
        case 0: movingLeft ? moving.width : 0
        case 1: 0
        default: -moving.width
        }
        switch destination {
        case .leftOf: return CGPoint(x: target.minX + shift + 2, y: target.midY)
        case .rightOf: return CGPoint(x: target.maxX + shift - 2, y: target.midY)
        }
    }

    func landed(_ frame: CGRect, at destination: Destination) -> Bool {
        let target = destination.windowID.flatMap(self.frame(of:)) ?? destination.frame
        switch destination {
        case .leftOf: return frame.maxX <= target.minX + Self.slack && frame.midX < target.midX
        case .rightOf: return frame.minX >= target.maxX - Self.slack && frame.midX > target.midX
        }
    }

    func frame(of windowID: UInt32) -> CGRect? {
        windows.statusWindows().first { $0.id == windowID }?.frame
    }

    func waitForPause() async throws {
        let deadline = ContinuousClock.now + Self.patience
        while activity.isMouseButtonDown || activity.areModifiersDown || activity.secondsSincePointerMoved < 0.05 {
            if ContinuousClock.now > deadline { throw EngineError.personIsBusy }
            await pause(.milliseconds(25))
        }
    }
}
