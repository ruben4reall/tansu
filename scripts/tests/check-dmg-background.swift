// swift scripts/tests/check-dmg-background.swift <png>: the installer background's size and layout.
import AppKit

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("check-dmg-background: \(message)\n".utf8))
    exit(1)
}

guard CommandLine.arguments.count == 2, let data = FileManager.default.contents(atPath: CommandLine.arguments[1]),
      let rep = NSBitmapImageRep(data: data) else { fail("usage: check-dmg-background.swift <png>") }
guard rep.pixelsWide == 1320, rep.pixelsHigh == 800 else { fail("\(rep.pixelsWide) x \(rep.pixelsHigh) pixels, expected 1320 x 800") }
guard Int(rep.size.width.rounded()) == 660, Int(rep.size.height.rounded()) == 400 else {
    fail("\(rep.size.width) x \(rep.size.height) points, expected 660 x 400 (144 dpi)")
}

/// The color at a point in Finder's coordinates: points from the top left.
func pixel(_ x: Double, _ y: Double) -> NSColor {
    guard let color = rep.colorAt(x: Int(x * 2), y: Int(y * 2))?.usingColorSpace(.sRGB) else { fail("no pixel at \(x), \(y)") }
    return color
}

/// Luminance, 0 to 1.
func luminance(_ x: Double, _ y: Double) -> Double {
    let color = pixel(x, y)
    return 0.2126 * color.redComponent + 0.7152 * color.greenComponent + 0.0722 * color.blueComponent
}

func darkest(x: ClosedRange<Double>, y: ClosedRange<Double>) -> Double {
    var result = 1.0
    for px in stride(from: x.lowerBound, through: x.upperBound, by: 0.5) {
        for py in stride(from: y.lowerBound, through: y.upperBound, by: 0.5) { result = min(result, luminance(px, py)) }
    }
    return result
}

/// Whether some point in the area is Honey (#FFB938), the lit compartment.
func honey(x: ClosedRange<Double>, y: ClosedRange<Double>) -> Bool {
    for px in stride(from: x.lowerBound, through: x.upperBound, by: 1) {
        for py in stride(from: y.lowerBound, through: y.upperBound, by: 1) {
            let color = pixel(px, py)
            if abs(color.redComponent - 1) < 0.06, abs(color.greenComponent - 0.725) < 0.06, abs(color.blueComponent - 0.22) < 0.08 {
                return true
            }
        }
    }
    return false
}

// Finder draws each 112-point icon centered at y = 215 and its label under it, in black: the ground must be light
// there, for the black labels and for Tansu's dark icon.
for x in [165.0, 495.0] {
    for y in [165.0, 180.0, 215.0, 250.0, 283.0, 292.0] where luminance(x, y) < 0.9 {
        fail("the ground at (\(x), \(y)) is too dark for Finder's black labels and Tansu's icon")
    }
}
let ground = luminance(240, 215)
guard darkest(x: 280...380, y: 214...216) < ground - 0.2 else { fail("no arrow between the icons") }
guard darkest(x: 260...300, y: 1...9) < 0.2, darkest(x: 360...400, y: 1...9) < 0.2 else { fail("no bar along the top edge") }
guard honey(x: 318...342, y: 3...8) else { fail("no honey tab on the bar") }
guard darkest(x: 280...380, y: 22...58) < 0.2 else { fail("no drawer under the bar") }
guard honey(x: 272...388, y: 18...61) else { fail("no compartment lit in honey") }
guard luminance(330, 100) > 0.9 else { fail("the drawer or its shadow reaches too far down") }
guard darkest(x: 250...410, y: 334...345) < 0.5 else { fail("no instruction under the shelf") }
guard darkest(x: 270...390, y: 368...377) < 0.75 else { fail("no non-affiliation notice at the bottom") }
var shelf = 0.0
for px in stride(from: 250.0, through: 410.0, by: 1) { shelf = max(shelf, abs(luminance(px, 307.5) - ground)) }
guard shelf > 0.04 else { fail("no shelf line under the labels") }
print("OK: 1320 x 800 px at 144 dpi, light under the icons and labels, bar, drawer, arrow, shelf and text in place")
