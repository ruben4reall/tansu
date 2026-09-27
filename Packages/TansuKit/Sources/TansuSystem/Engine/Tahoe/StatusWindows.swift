import AppKit
import CoreGraphics

/// One window of the menu bar's icons, as the window server lists it (macOS 26).
public struct StatusWindow: Equatable, Sendable {
    public var id: UInt32
    /// Top-left origin, main display.
    public var frame: CGRect
    public var ownerPID: pid_t

    public init(id: UInt32, frame: CGRect, ownerPID: pid_t) {
        self.id = id
        self.frame = frame
        self.ownerPID = ownerPID
    }
}

/// Where the engine reads windows. The system implementation reads the window server; tests use a simulated bar.
public protocol StatusWindowSource: Sendable {
    /// Every icon window (status window level), from right to left, including the ones pushed off screen.
    func statusWindows() -> [StatusWindow]
    /// Frames of menus and popovers open on screen whose window belongs to one of `ownerPIDs`.
    func openMenuFrames(ownerPIDs: Set<pid_t>) -> [CGRect]
}

/// The window server, through the public window list. Needs no permission: only window names would need Screen
/// Recording, and Tansu never reads them.
public struct SystemStatusWindows: StatusWindowSource {
    public init() {}

    static let statusLevel = Int(CGWindowLevelForKey(.statusWindow))
    static let mainMenuLevel = Int(CGWindowLevelForKey(.mainMenuWindow))
    static let popUpMenuLevel = Int(CGWindowLevelForKey(.popUpMenuWindow))

    public func statusWindows() -> [StatusWindow] {
        guard let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] else { return [] }
        return list.compactMap { info -> StatusWindow? in
            guard info[kCGWindowLayer as String] as? Int == Self.statusLevel,
                  let number = info[kCGWindowNumber as String] as? Int, let id = UInt32(exactly: number),
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds),
                  let owner = info[kCGWindowOwnerPID as String] as? Int else { return nil }
            return StatusWindow(id: id, frame: frame, ownerPID: pid_t(owner))
        }
        .sorted { $0.frame.midX > $1.frame.midX }
    }

    public func openMenuFrames(ownerPIDs: Set<pid_t>) -> [CGRect] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] else { return [] }
        return list.compactMap { info -> CGRect? in
            guard let layer = info[kCGWindowLayer as String] as? Int,
                  let owner = info[kCGWindowOwnerPID as String] as? Int, ownerPIDs.contains(pid_t(owner)),
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds) else { return nil }
            // Menus live at the pop-up menu level; popovers and panels that icons open sit at or near the menu
            // bar's levels and are taller than the bar itself.
            let isMenu = layer == Self.popUpMenuLevel || layer == Self.popUpMenuLevel - 1
            let isPanel = [Self.mainMenuLevel, Self.statusLevel].contains(layer) && frame.height > 40
            return isMenu || isPanel ? frame : nil
        }
    }
}

/// Converts between AppKit's screen coordinates (bottom-left origin) and the window server's (top-left origin of the
/// main display).
public enum ScreenCoordinates {
    @MainActor
    public static var mainDisplayHeight: CGFloat {
        NSScreen.screens.first?.frame.height ?? 0
    }

    @MainActor
    public static func windowServerRect(fromAppKit rect: CGRect) -> CGRect {
        CGRect(x: rect.minX, y: mainDisplayHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    @MainActor
    public static func appKitRect(fromWindowServer rect: CGRect) -> CGRect {
        CGRect(x: rect.minX, y: mainDisplayHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    /// Whether a window server rectangle lies on any display.
    @MainActor
    public static func isOnScreen(_ rect: CGRect) -> Bool {
        let height = mainDisplayHeight
        return NSScreen.screens.contains { screen in
            let frame = screen.frame
            let flipped = CGRect(x: frame.minX, y: height - frame.maxY, width: frame.width, height: frame.height)
            return flipped.intersection(rect).width >= rect.width * 0.5
        }
    }
}
