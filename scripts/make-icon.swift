import AppKit

let image = NSImage(size: NSSize(width: 1024, height: 1024))
image.lockFocus()
let background = NSBezierPath(roundedRect: NSRect(x: 40, y: 40, width: 944, height: 944), xRadius: 205, yRadius: 205)
NSGradient(starting: NSColor(calibratedRed: 0.28, green: 0.46, blue: 0.45, alpha: 1), ending: NSColor(calibratedRed: 0.15, green: 0.29, blue: 0.3, alpha: 1))!.draw(in: background, angle: -90)
let shadow = NSShadow(); shadow.shadowBlurRadius = 30; shadow.shadowOffset = NSSize(width: 0, height: -12); shadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
NSGraphicsContext.saveGraphicsState(); shadow.set()
NSColor(calibratedWhite: 0.97, alpha: 1).setFill(); NSBezierPath(roundedRect: NSRect(x: 225, y: 185, width: 574, height: 625), xRadius: 30, yRadius: 30).fill()
NSGraphicsContext.restoreGraphicsState()
NSColor(calibratedRed: 0.91, green: 0.84, blue: 0.57, alpha: 1).setFill(); NSBezierPath(roundedRect: NSRect(x: 280, y: 260, width: 360, height: 65), xRadius: 6, yRadius: 6).fill()
for line in 0..<4 { NSColor.gray.withAlphaComponent(0.18).setFill(); NSBezierPath(roundedRect: NSRect(x: 280, y: 390 + line * 65, width: line == 3 ? 280 : 460, height: 16), xRadius: 8, yRadius: 8).fill() }
let metal = NSBezierPath(roundedRect: NSRect(x: 404, y: 694, width: 216, height: 205), xRadius: 24, yRadius: 24)
NSGradient(colors: [NSColor(white: 0.65, alpha: 1), NSColor(white: 0.97, alpha: 1), NSColor(white: 0.57, alpha: 1), NSColor(white: 0.8, alpha: 1)])!.draw(in: metal, angle: 0)
NSColor(white: 0.43, alpha: 1).setStroke(); let wire = NSBezierPath(roundedRect: NSRect(x: 462, y: 812, width: 100, height: 125), xRadius: 25, yRadius: 25); wire.lineWidth = 11; wire.stroke()
image.unlockFocus()
let data = NSBitmapImageRep(data: image.tiffRepresentation!)!.representation(using: .png, properties: [:])!
try data.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
