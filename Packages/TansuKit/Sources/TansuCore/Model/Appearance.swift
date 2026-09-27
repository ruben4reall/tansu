import Foundation

/// A color in sRGB, stored as components between 0 and 1.
public struct RGBA: Codable, Hashable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    /// "#FFB938" or "FFB938", with an optional alpha pair ("#FFB93880").
    public init?(hex: String) {
        var digits = hex.trimmingCharacters(in: .whitespaces)
        if digits.hasPrefix("#") { digits.removeFirst() }
        guard digits.count == 6 || digits.count == 8, let value = UInt64(digits, radix: 16) else { return nil }
        let hasAlpha = digits.count == 8
        let shift: UInt64 = hasAlpha ? 8 : 0
        red = Double((value >> (16 + shift)) & 0xFF) / 255
        green = Double((value >> (8 + shift)) & 0xFF) / 255
        blue = Double((value >> shift) & 0xFF) / 255
        alpha = hasAlpha ? Double(value & 0xFF) / 255 : 1
    }

    public var hex: String {
        func byte(_ component: Double) -> Int { Int((min(max(component, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(red), byte(green), byte(blue))
    }

    public var clamped: RGBA {
        RGBA(red: red.clamped(to: 0...1), green: green.clamped(to: 0...1), blue: blue.clamped(to: 0...1), alpha: alpha.clamped(to: 0...1))
    }

    /// Relative luminance (WCAG 2), for contrast checks.
    public var luminance: Double {
        func linear(_ channel: Double) -> Double {
            channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    /// WCAG contrast ratio between two opaque colors, from 1 to 21.
    public func contrast(with other: RGBA) -> Double {
        let (light, dark) = luminance > other.luminance ? (luminance, other.luminance) : (other.luminance, luminance)
        return (light + 0.05) / (dark + 0.05)
    }
}

/// How Tansu dresses the menu bar (spec 6.3, Appearance).
public struct Appearance: Codable, Hashable, Sendable {
    public enum Tint: String, Codable, Sendable, CaseIterable {
        case none, color, gradient
    }

    public var tint: Tint
    public var color: RGBA
    /// The right end of a gradient, which starts from `color` on the left.
    public var gradientEnd: RGBA
    /// How strongly the tint shows, from 0 to 1.
    public var opacity: Double
    /// A hairline along the bottom of the menu bar.
    public var border: Bool
    /// A soft shadow under the menu bar.
    public var shadow: Bool

    public init(
        tint: Tint = .none, color: RGBA = RGBA(hex: "#FFB938")!, gradientEnd: RGBA = RGBA(hex: "#FF8A1F")!,
        opacity: Double = 0.35, border: Bool = false, shadow: Bool = false
    ) {
        self.tint = tint
        self.color = color
        self.gradientEnd = gradientEnd
        self.opacity = opacity
        self.border = border
        self.shadow = shadow
    }

    public static let standard = Appearance()

    /// Whether anything is drawn over the menu bar at all.
    public var isVisible: Bool { tint != .none || border || shadow }

    public var clamped: Appearance {
        var copy = self
        copy.color = color.clamped
        copy.gradientEnd = gradientEnd.clamped
        copy.opacity = opacity.clamped(to: 0...1)
        return copy
    }

    private enum CodingKeys: String, CodingKey { case tint, color, gradientEnd, opacity, border, shadow }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let standard = Appearance()
        tint = (try? container.decodeIfPresent(Tint.self, forKey: .tint)) ?? standard.tint
        color = (try? container.decodeIfPresent(RGBA.self, forKey: .color)) ?? standard.color
        gradientEnd = (try? container.decodeIfPresent(RGBA.self, forKey: .gradientEnd)) ?? standard.gradientEnd
        opacity = (try? container.decodeIfPresent(Double.self, forKey: .opacity)) ?? standard.opacity
        border = (try? container.decodeIfPresent(Bool.self, forKey: .border)) ?? standard.border
        shadow = (try? container.decodeIfPresent(Bool.self, forKey: .shadow)) ?? standard.shadow
    }
}

extension Comparable {
    /// The value, brought inside `range`.
    public func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
