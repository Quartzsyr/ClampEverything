import AppKit
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 640, pixelsHigh: 480, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)!
NSColor(calibratedRed: 0.96, green: 0.96, blue: 0.93, alpha: 1).setFill()
NSBezierPath(rect: NSRect(x: 0, y: 0, width: 640, height: 480)).fill()
func text(_ value: String, x: CGFloat, y: CGFloat, size: CGFloat, weight: NSFont.Weight, color: NSColor) {
    let text = value as NSString
    let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color]
    let width = text.size(withAttributes: attributes).width
    text.draw(at: NSPoint(x: x - width / 2, y: y), withAttributes: attributes)
}
text("屏幕夹子", x: 320, y: 396, size: 30, weight: .medium, color: NSColor(calibratedWhite: 0.18, alpha: 1))
text("拖入 Applications，安装到应用程序", x: 320, y: 360, size: 15, weight: .regular, color: NSColor(calibratedWhite: 0.42, alpha: 1))
// Finder icon centres: application (160, 215), Applications (480, 215).
let arrow = NSBezierPath()
arrow.move(to: NSPoint(x: 260, y: 265)); arrow.line(to: NSPoint(x: 380, y: 265))
arrow.move(to: NSPoint(x: 363, y: 280)); arrow.line(to: NSPoint(x: 380, y: 265)); arrow.line(to: NSPoint(x: 363, y: 250))
arrow.lineWidth = 5; arrow.lineCapStyle = .round; arrow.lineJoinStyle = .round
NSColor(calibratedRed: 0.25, green: 0.51, blue: 0.49, alpha: 1).setStroke(); arrow.stroke()
text("拖动安装", x: 320, y: 222, size: 12, weight: .medium, color: NSColor(calibratedRed: 0.25, green: 0.51, blue: 0.49, alpha: 1))
text("更新前先退出旧版本 · Apple Silicon · macOS 14+", x: 320, y: 12, size: 11, weight: .regular, color: NSColor(calibratedWhite: 0.42, alpha: 1))
NSGraphicsContext.restoreGraphicsState()
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
