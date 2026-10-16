import AppKit
import ImageIO

@MainActor enum GeneratedAssets {
    private static var cache: [String: NSImage] = [:]
    static func image(_ name: String) -> NSImage {
        if let cached = cache[name] { return cached }
        let installed = Bundle.main.resourceURL?.appendingPathComponent("Generated/" + name + ".png")
        let url = installed.flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil }
            ?? Bundle.module.url(forResource: name, withExtension: "png", subdirectory: "Generated")!
        let limit = name.hasPrefix("paper-") ? 1100 : ((name.hasPrefix("cursor-") || name.hasPrefix("hanging-")) ? 1024 : 256)
        let source = CGImageSourceCreateWithURL(url as CFURL, nil)!
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: limit, kCGImageSourceCreateThumbnailWithTransform: true]
        let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)!
        let image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        cache[name] = image
        return image
    }
}
