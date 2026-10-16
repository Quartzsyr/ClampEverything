import AppKit
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 640, pixelsHigh: 480, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)!
guard CommandLine.arguments.count > 2, let artwork = NSImage(contentsOfFile: CommandLine.arguments[2]) else {
    fatalError("Missing imagegen paper arrow artwork")
}
NSGraphicsContext.current?.imageInterpolation = .high
artwork.draw(in: NSRect(x: 0, y: 0, width: 640, height: 480), from: .zero, operation: .copy, fraction: 1)
func text(_ value: String, x: CGFloat, y: CGFloat, size: CGFloat, weight: NSFont.Weight, color: NSColor) {
    let text = value as NSString
    let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color]
    let width = text.size(withAttributes: attributes).width
    text.draw(at: NSPoint(x: x - width / 2, y: y), withAttributes: attributes)
}
text("屏幕夹子", x: 320, y: 388, size: 30, weight: .medium, color: NSColor(calibratedWhite: 0.18, alpha: 1))
text("拖入 Applications，安装到应用程序", x: 320, y: 356, size: 15, weight: .regular, color: NSColor(calibratedWhite: 0.42, alpha: 1))
// The folded paper arrow is part of the generated artwork, between the native icons.
text("拖动安装", x: 320, y: 166, size: 12, weight: .medium, color: NSColor(calibratedRed: 0.30, green: 0.37, blue: 0.28, alpha: 1))
text("更新前先退出旧版本 · Apple Silicon · macOS 14+", x: 320, y: 12, size: 11, weight: .regular, color: NSColor(calibratedWhite: 0.42, alpha: 1))
NSGraphicsContext.restoreGraphicsState()
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
