import AppKit
import QuartzCore
import TansuCore

/// The menu bar's tint, border and shadow (spec 6.3, Appearance). One window per display, just below the menu bar's
/// level: on macOS 26 and 27 the bar has no background by default, so the tint shows through, and the icons stay on
/// top of it. It never takes a click.
@MainActor
public final class TintOverlay {
    private var windows: [CGDirectDisplayID: NSWindow] = [:]
    private var appearance = Appearance.standard

    public init() {}

    public func update(_ appearance: Appearance) {
        self.appearance = appearance
        guard appearance.isVisible else {
            removeAll()
            return
        }
        let screens = NSScreen.screens
        let ids = Set(screens.compactMap(Self.displayID))
        for (id, window) in windows where !ids.contains(id) {
            window.orderOut(nil)
            windows[id] = nil
        }
        for screen in screens {
            guard let id = Self.displayID(screen) else { continue }
            let frame = Self.menuBarFrame(of: screen)
            guard frame.height > 0 else {
                windows[id]?.orderOut(nil)
                continue
            }
            let window = windows[id] ?? Self.makeWindow()
            windows[id] = window
            // The shadow falls below the menu bar: the window reaches that far down, and takes no click there either.
            let shadow = appearance.shadow ? Self.shadowHeight : 0
            window.setFrame(CGRect(x: frame.minX, y: frame.minY - shadow, width: frame.width, height: frame.height + shadow), display: false)
            draw(in: window, appearance: appearance)
            window.orderFrontRegardless()
        }
    }

    public func removeAll() {
        for window in windows.values { window.orderOut(nil) }
        windows.removeAll()
    }

    static let shadowHeight: CGFloat = 12

    static func displayID(_ screen: NSScreen) -> CGDirectDisplayID? {
        screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }

    /// The strip between the top of the visible frame and the top of the screen; empty when the menu bar hides itself.
    static func menuBarFrame(of screen: NSScreen) -> CGRect {
        let top = screen.frame.maxY
        let bottom = screen.visibleFrame.maxY
        return CGRect(x: screen.frame.minX, y: bottom, width: screen.frame.width, height: max(0, top - bottom))
    }

    static func makeWindow() -> NSWindow {
        let window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        window.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue - 1)
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        window.ignoresMouseEvents = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.isReleasedWhenClosed = false
        let view = NSView()
        view.wantsLayer = true
        window.contentView = view
        return window
    }

    private func draw(in window: NSWindow, appearance: Appearance) {
        guard let layer = window.contentView?.layer else { return }
        layer.sublayers?.forEach { $0.removeFromSuperlayer() }
        let shadowHeight = appearance.shadow ? Self.shadowHeight : 0
        let bounds = CGRect(x: 0, y: shadowHeight, width: window.frame.width, height: window.frame.height - shadowHeight)
        switch appearance.tint {
        case .none:
            break
        case .color:
            let fill = CALayer()
            fill.frame = bounds
            fill.backgroundColor = NSColor(appearance.color).withAlphaComponent(appearance.opacity).cgColor
            layer.addSublayer(fill)
        case .gradient:
            let gradient = CAGradientLayer()
            gradient.frame = bounds
            gradient.startPoint = CGPoint(x: 0, y: 0.5)
            gradient.endPoint = CGPoint(x: 1, y: 0.5)
            gradient.colors = [
                NSColor(appearance.color).withAlphaComponent(appearance.opacity).cgColor,
                NSColor(appearance.gradientEnd).withAlphaComponent(appearance.opacity).cgColor,
            ]
            layer.addSublayer(gradient)
        }
        if appearance.border {
            let line = CALayer()
            line.frame = CGRect(x: 0, y: bounds.minY, width: bounds.width, height: 1 / (window.backingScaleFactor > 0 ? window.backingScaleFactor : 2))
            line.backgroundColor = NSColor.white.withAlphaComponent(0.18).cgColor
            layer.addSublayer(line)
        }
        if appearance.shadow {
            let shade = CAGradientLayer()
            shade.frame = CGRect(x: 0, y: 0, width: bounds.width, height: shadowHeight)
            shade.colors = [NSColor.black.withAlphaComponent(0).cgColor, NSColor.black.withAlphaComponent(0.2).cgColor]
            shade.startPoint = CGPoint(x: 0.5, y: 0)
            shade.endPoint = CGPoint(x: 0.5, y: 1)
            layer.addSublayer(shade)
        }
    }
}
