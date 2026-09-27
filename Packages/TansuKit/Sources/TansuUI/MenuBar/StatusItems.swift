import AppKit
import TansuCore
import TansuSystem

/// Tansu's own items in the menu bar: its icon (the All drawer) and one item per drawer (spec 6.2).
@MainActor
public final class StatusItemsController {
    public enum Target: Hashable, Sendable {
        case all
        case drawer(UUID)
    }

    public var onOpen: ((Target) -> Void)?
    /// Option-click on Tansu's icon.
    public var onShowEverything: (() -> Void)?
    /// The menu for a right-click.
    public var menuFor: ((Target) -> NSMenu)?
    /// Open drawers after the pointer rests on them this long; nil turns hovering off.
    public var hoverDelay: TimeInterval?

    private var main: NSStatusItem?
    private var drawerItems: [UUID: NSStatusItem] = [:]
    private var trackers: [ObjectIdentifier: HoverTracker] = [:]
    private var hoverTask: Task<Void, Never>?
    /// The drawers, and whether Tansu's icon showed, the last time Tansu set their places itself.
    private var placed: (drawers: [UUID], main: Bool)?

    static let mainAutosaveName = "tansu.main"
    static func autosaveName(for drawer: UUID) -> String { "tansu.drawer.\(drawer.uuidString)" }

    public init() {}

    /// Makes the menu bar show exactly these drawers, in this order, and Tansu's icon if asked. With
    /// `keepsAtRightEnd`, Tansu's icons sit together next to Control Center, the drawers in the order of Settings.
    public func update(drawers: [Drawer], counts: [UUID: Int], showsMain: Bool, isFocusOn: Bool, isShowingEverything: Bool,
                       keepsAtRightEnd: Bool = true) {
        let wantsMain = showsMain || isFocusOn
        if keepsAtRightEnd, placed?.drawers != drawers.map(\.id) || placed?.main != wantsMain {
            place(drawers: drawers)
            placed = (drawers.map(\.id), wantsMain)
        }
        let wanted = Set(drawers.map(\.id))
        for (id, item) in drawerItems where !wanted.contains(id) {
            NSStatusBar.system.removeStatusItem(item)
            drawerItems[id] = nil
        }
        // Tansu's icon first, then the drawers from right to left: macOS puts each new item on the left of the others.
        if wantsMain {
            if main == nil { main = makeItem(autosaveName: Self.mainAutosaveName, position: 0, target: .all) }
            main?.button?.image = TansuGlyph.image(isFocusOn ? .focus : (isShowingEverything ? .open : .closed))
            main?.button?.toolTip = isFocusOn ? Strings.focusIsOnHelp : Strings.tansuIconHelp
            main?.button?.setAccessibilityLabel(Strings.appName)
        } else if let main {
            NSStatusBar.system.removeStatusItem(main)
            self.main = nil
        }
        // macOS stores each item's place as its distance from the right end of the menu bar, and rewrites Tansu's own
        // after the first launch: new drawers start just left of wherever Tansu's icon is now.
        let base = UserDefaults.standard.double(forKey: Self.positionKey(Self.mainAutosaveName))
        for (offset, drawer) in drawers.reversed().enumerated() {
            let item = drawerItems[drawer.id]
                ?? makeItem(autosaveName: Self.autosaveName(for: drawer.id), position: base + Double(offset + 1), target: .drawer(drawer.id))
            drawerItems[drawer.id] = item
            item.isVisible = !isFocusOn
            if let button = item.button { StatusMark.apply(drawer, count: counts[drawer.id] ?? 0, to: button) }
        }
    }

    /// Where a target's item sits: AppKit coordinates for placing a panel, window server coordinates for the engine.
    public func anchor(for target: Target) -> (appKit: CGRect, windowServer: CGRect)? {
        let item: NSStatusItem? = switch target {
        case .all: main
        case .drawer(let id): drawerItems[id]
        }
        guard let frame = item?.button?.window?.frame, frame.width > 0 else { return nil }
        return (frame, ScreenCoordinates.windowServerRect(fromAppKit: frame))
    }

    /// The frames of Tansu's own items that show, in AppKit coordinates.
    public var itemFrames: [CGRect] {
        ([main].compactMap { $0 } + Array(drawerItems.values)).compactMap { item in
            guard item.isVisible, let frame = item.button?.window?.frame, frame.width > 0 else { return nil }
            return frame
        }
    }

    /// Where to hang the All drawer when Tansu's icon is not in the menu bar: under the leftmost drawer.
    public func fallbackAnchor() -> (appKit: CGRect, windowServer: CGRect)? {
        let frames = drawerItems.values.compactMap { item -> CGRect? in
            guard item.isVisible, let frame = item.button?.window?.frame, frame.width > 0 else { return nil }
            return frame
        }
        guard let frame = frames.min(by: { $0.minX < $1.minX }) else { return nil }
        return (frame, ScreenCoordinates.windowServerRect(fromAppKit: frame))
    }

    /// Removes every item (on quit), keeping their places for the next launch.
    public func removeAll() {
        for item in drawerItems.values { NSStatusBar.system.removeStatusItem(item) }
        drawerItems.removeAll()
        if let main { NSStatusBar.system.removeStatusItem(main) }
        main = nil
        trackers.removeAll()
    }

    /// Sets the places of Tansu's items afresh: its icon at the right end of the icons macOS lets move, the drawers on
    /// its left in the order of Settings. macOS remembers each item's place as a number it compares with every other
    /// app's, often stale: set once per launch and per reorder, Tansu's icons stay together where people look for
    /// them. The items are made again, since macOS reads a place only when an item appears.
    private func place(drawers: [Drawer]) {
        removeAll()
        let defaults = UserDefaults.standard
        defaults.set(0.0, forKey: Self.positionKey(Self.mainAutosaveName))
        for (offset, drawer) in drawers.reversed().enumerated() {
            defaults.set(Double(offset + 1), forKey: Self.positionKey(Self.autosaveName(for: drawer.id)))
        }
    }

    static func positionKey(_ autosaveName: String) -> String { "NSStatusItem Preferred Position \(autosaveName)" }

    private func makeItem(autosaveName: String, position: Double, target: Target) -> NSStatusItem {
        let defaults = UserDefaults.standard
        let key = Self.positionKey(autosaveName)
        // The first time only: macOS keeps the place after that, including where the person drags the item.
        if defaults.object(forKey: key) == nil { defaults.set(position, forKey: key) }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = autosaveName
        item.behavior = []
        if let button = item.button {
            let handler = ClickHandler(target: target, controller: self)
            button.target = handler
            button.action = #selector(ClickHandler.clicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            objc_setAssociatedObject(button, &ClickHandler.key, handler, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            let tracker = HoverTracker(frame: button.bounds)
            tracker.autoresizingMask = [.width, .height]
            tracker.onEnter = { [weak self] in self?.hoverStarted(target) }
            tracker.onExit = { [weak self] in self?.hoverTask?.cancel() }
            button.addSubview(tracker)
            trackers[ObjectIdentifier(item)] = tracker
        }
        return item
    }

    fileprivate func clicked(_ target: Target, button: NSStatusBarButton) {
        hoverTask?.cancel()
        let event = NSApp.currentEvent
        let isRightClick = event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true
        if isRightClick, let menu = menuFor?(target) {
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 4), in: button)
            return
        }
        if target == .all, event?.modifierFlags.contains(.option) == true {
            onShowEverything?()
            return
        }
        onOpen?(target)
    }

    private func hoverStarted(_ target: Target) {
        guard let hoverDelay, NSEvent.pressedMouseButtons == 0 else { return }
        hoverTask?.cancel()
        hoverTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(Int(hoverDelay * 1000)))
            guard !Task.isCancelled else { return }
            self?.onOpen?(target)
        }
    }
}

/// Receives a status item's clicks and forwards them with the item's target.
@MainActor
private final class ClickHandler: NSObject {
    static var key: UInt8 = 0
    let target: StatusItemsController.Target
    weak var controller: StatusItemsController?

    init(target: StatusItemsController.Target, controller: StatusItemsController) {
        self.target = target
        self.controller = controller
    }

    @objc func clicked(_ sender: NSStatusBarButton) {
        controller?.clicked(target, button: sender)
    }
}

/// Tells when the pointer enters and leaves a status item, without taking its clicks.
private final class HoverTracker: NSView {
    var onEnter: (() -> Void)?
    var onExit: (() -> Void)?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { onEnter?() }
    override func mouseExited(with event: NSEvent) { onExit?() }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// Tansu's own menu bar glyph: a small chest of three drawers, drawn as a template image so it follows the menu bar
/// like the system's icons.
public enum TansuGlyph {
    public enum State { case closed, open, focus }

    public static func image(_ state: State) -> NSImage {
        if state == .focus {
            let configuration = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
            let moon = NSImage(systemSymbolName: "moon.fill", accessibilityDescription: nil)?.withSymbolConfiguration(configuration)
            moon?.isTemplate = true
            return moon ?? NSImage()
        }
        let image = NSImage(size: NSSize(width: 18, height: 16), flipped: true) { _ in
            NSColor.black.setStroke()
            let body = NSBezierPath(roundedRect: NSRect(x: 2, y: 1.5, width: 14, height: 13), xRadius: 2.6, yRadius: 2.6)
            body.lineWidth = 1.4
            body.stroke()
            for row in 0..<3 {
                let top = 1.5 + CGFloat(row) * 13 / 3
                if row > 0 {
                    let divider = NSBezierPath()
                    divider.move(to: NSPoint(x: 2.7, y: top))
                    divider.line(to: NSPoint(x: 15.3, y: top))
                    divider.lineWidth = 1.2
                    divider.stroke()
                }
                // Drawers pulled out a little when every icon is showing.
                let shift: CGFloat = state == .open ? CGFloat(row - 1) * 1.5 : 0
                let handle = NSBezierPath()
                let middle = top + 13 / 6
                handle.move(to: NSPoint(x: 7.3 + shift, y: middle))
                handle.line(to: NSPoint(x: 10.7 + shift, y: middle))
                handle.lineWidth = 1.5
                handle.lineCapStyle = .round
                handle.stroke()
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}
