// swift scripts/make-dmg-background.swift [output.png]
//
// The installer window's background: 660 x 400 points, rendered at 2x, written to packaging/dmg-background.png unless
// another path is given. scripts/release.sh copies it into the disk image and places Tansu's icon at (165, 215) and
// Applications at (495, 215), in Finder's coordinates (points from the top left), with 112-point icons.
//
// Light on purpose, like Pli's. Finder draws the labels under the icons in black on any window with a background
// picture, whatever the appearance, so a Night ground would hide "Tansu" and "Applications"; Paper and Rice keep them
// legible, and Tansu's warm black icon stands out on them. The brand comes back as the icon's own drawer, drawn here
// with shapes rather than read from brand/, so the script needs nothing but the palette: it hangs from a bar at the top
// edge, the way a drawer drops from the menu bar, with one compartment lit in Honey.
import AppKit

func color(_ hex: String, alpha: CGFloat = 1) -> NSColor {
    let value = UInt64(hex.dropFirst(), radix: 16) ?? 0
    return NSColor(srgbRed: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255,
                   blue: CGFloat(value & 0xFF) / 255, alpha: alpha)
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("make-dmg-background: \(message)\n".utf8))
    exit(1)
}

// The brand palette: scripts/tests/test-dmg-background.sh checks every color here against brand/tokens/tokens.json.
let night = color("#0C0B0A"), lacquer = color("#17150F"), rice = color("#F5F1EA"), ash = color("#9D968B")
let honey = color("#FFB938"), deepHoney = color("#8F5600"), paper = color("#FAF8F4"), ink = color("#1C1A17")
let graphite = color("#6E6A63"), hairline = color("#DAD5CC")

let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "packaging/dmg-background.png"
let width: CGFloat = 660, height: CGFloat = 400, scale = 2
guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width) * scale, pixelsHigh: Int(height) * scale,
                                 bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                 colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { fail("no bitmap") }
rep.size = NSSize(width: width, height: height)   // 144 dpi: Finder shows it at 660 x 400 points

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
// Drawing coordinates start at the bottom left: Finder's y = 215 is 400 - 215 = 185 here.

// 1. The ground: Paper at the top, Rice at the bottom.
NSGradient(colors: [rice, paper])!.draw(in: NSRect(x: 0, y: 0, width: width, height: height), angle: 90)

// 2. The bar along the top edge, with its one honey tab: the icon's frosted bar, dark on a light ground. Its top corners
//    run past the edge, so only the bottom ones show as rounded.
night.setFill()
NSBezierPath(roundedRect: NSRect(x: 250, y: height - 11, width: 160, height: 22), xRadius: 5, yRadius: 5).fill()
honey.setFill()
NSBezierPath(roundedRect: NSRect(x: 316, y: height - 7.5, width: 28, height: 4), xRadius: 2, yRadius: 2).fill()

// 3. The drawer hanging under the tab (Finder's y = 17 to 62), with a soft shadow that says it has dropped, and its grid
//    of compartments, one lit in Honey with a glow around it. The shadow comes from a plain fill: a gradient clips to
//    its path, so it would cut its own shadow away.
let drawer = NSRect(x: 271, y: height - 62, width: 118, height: 45)
let drawerPath = NSBezierPath(roundedRect: drawer, xRadius: 10, yRadius: 10)
NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = ink.withAlphaComponent(0.25)
shadow.shadowBlurRadius = 14
shadow.shadowOffset = NSSize(width: 0, height: -5)
shadow.set()
lacquer.setFill()
drawerPath.fill()
NSGraphicsContext.restoreGraphicsState()
NSGradient(colors: [night, lacquer])!.draw(in: drawerPath, angle: 90)

let columns = 4, rows = 2, padding: CGFloat = 7, gap: CGFloat = 4
let cellWidth = (drawer.width - 2 * padding - CGFloat(columns - 1) * gap) / CGFloat(columns)
let cellHeight = (drawer.height - 2 * padding - CGFloat(rows - 1) * gap) / CGFloat(rows)
func cell(row: Int, column: Int) -> NSRect {
    NSRect(x: drawer.minX + padding + CGFloat(column) * (cellWidth + gap),
           y: drawer.maxY - padding - CGFloat(row + 1) * cellHeight - CGFloat(row) * gap,
           width: cellWidth, height: cellHeight)
}
let lit = cell(row: 0, column: 2)
NSGraphicsContext.saveGraphicsState()
drawerPath.addClip()
NSGradient(colors: [honey.withAlphaComponent(0.32), honey.withAlphaComponent(0)])!
    .draw(fromCenter: NSPoint(x: lit.midX, y: lit.midY), radius: 0, toCenter: NSPoint(x: lit.midX, y: lit.midY),
          radius: 30, options: [])
NSGraphicsContext.restoreGraphicsState()
for row in 0..<rows {
    for column in 0..<columns {
        let rect = cell(row: row, column: column)
        (rect == lit ? honey : ash.withAlphaComponent(0.16)).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 3.5, yRadius: 3.5).fill()
    }
}

// 4. The arrow from Tansu to Applications, at icon height, in the accent for light grounds.
let arrow = NSBezierPath()
arrow.lineWidth = 3
arrow.lineCapStyle = .round
arrow.lineJoinStyle = .round
arrow.move(to: NSPoint(x: 262, y: 185))
arrow.line(to: NSPoint(x: 398, y: 185))
arrow.move(to: NSPoint(x: 378, y: 203))
arrow.line(to: NSPoint(x: 398, y: 185))
arrow.line(to: NSPoint(x: 378, y: 167))
deepHoney.withAlphaComponent(0.9).setStroke()
arrow.stroke()

// 5. The shelf: a hairline under the labels, fading at both ends.
NSGradient(colors: [hairline.withAlphaComponent(0), hairline, hairline, hairline.withAlphaComponent(0)],
           atLocations: [0, 0.2, 0.8, 1], colorSpace: .sRGB)!
    .draw(in: NSRect(x: 90, y: 92, width: 480, height: 1), angle: 0)

// 6. What to do, then who Tansu is not.
func centered(_ text: String, size: CGFloat, weight: NSFont.Weight, color: NSColor, y: CGFloat) {
    let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color]
    let textWidth = (text as NSString).size(withAttributes: attributes).width
    (text as NSString).draw(at: NSPoint(x: (width - textWidth) / 2, y: y), withAttributes: attributes)
}
centered("Drag Tansu to Applications.", size: 13, weight: .medium, color: ink, y: 54)
centered("Tansu is not affiliated with Apple.", size: 10.5, weight: .regular, color: graphite, y: 22)
NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else { fail("no PNG") }
do {
    try FileManager.default.createDirectory(at: URL(fileURLWithPath: output).deletingLastPathComponent(), withIntermediateDirectories: true)
    try png.write(to: URL(fileURLWithPath: output))
} catch {
    fail("cannot write \(output): \(error)")
}
print("DMG background: \(output)")
