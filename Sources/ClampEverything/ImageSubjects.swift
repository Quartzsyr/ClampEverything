import AppKit
import Vision
import CoreVideo
import ApplicationServices

/// Only a large content image can opt into subject pickup. File icons retain file identity.
enum ImageSubjectEligibility {
    static func bounds(in candidates: [PointCandidate]) -> CGRect? {
        let containers = ["AXCell", "AXRow", "AXDockItem", "AXMenuItem", "AXButton"]
        guard !candidates.contains(where: { containers.contains($0.role) || $0.thumbnail }) else { return nil }
        guard let image = candidates.first(where: { $0.role == kAXImageRole }), let rect = image.rect,
              isLarge(rect) else { return nil }
        return rect
    }
    static func isThumbnail(role: String?, subrole: String?, description: String?) -> Bool {
        let semantics = [role, subrole].compactMap { $0 }.joined(separator: " ").lowercased()
        if ["thumbnail", "缩略", "icon", "图标"].contains(where: { semantics.contains($0) }) { return true }
        let description = description?.lowercased() ?? ""
        return ["thumbnail of ", "file icon", "缩略图", "文件图标"].contains { description.hasPrefix($0) }
    }
    static func isLarge(_ rect: CGRect) -> Bool {
        rect.minX.isFinite && rect.minY.isFinite && rect.width.isFinite && rect.height.isFinite &&
        min(rect.width, rect.height) >= 96 && max(rect.width, rect.height) >= 360 && rect.width * rect.height >= 60_000
    }
}

struct SubjectRaster {
    let width: Int
    let height: Int
    var rgba: [UInt8]
    init(_ image: CGImage, maximum: Int? = nil) throws {
        let scale = maximum.map { min(1, Double($0) / Double(max(image.width, image.height))) } ?? 1
        width = max(1, Int(Double(image.width) * scale)); height = max(1, Int(Double(image.height) * scale))
        rgba = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = rgba.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
            context.interpolationQuality = .high; context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height)); return true
        }
        if !drawn { throw PointCaptureError.unavailable }
    }
    var signature: [UInt8] {
        (0..<24).flatMap { y in (0..<24).flatMap { x -> [UInt8] in
            let i = (min(height - 1, y * height / 24) * width + min(width - 1, x * width / 24)) * 4
            return Array(rgba[i..<i + 3])
        } }
    }
    static func image(_ bytes: [UInt8], width: Int, height: Int) -> CGImage? {
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}

struct SubjectMask {
    let width: Int
    let height: Int
    let values: [UInt8] // Top-left raster coordinates, matching the source image.
    var bounds: CGRect? {
        var x0 = width, y0 = height, x1 = -1, y1 = -1
        for y in 0..<height { for x in 0..<width where values[y * width + x] > 96 {
            x0 = min(x0, x); x1 = max(x1, x); y0 = min(y0, y); y1 = max(y1, y)
        } }
        guard x1 >= x0, y1 >= y0 else { return nil }
        return CGRect(x: Double(x0) / Double(width), y: Double(y0) / Double(height),
            width: Double(x1 - x0 + 1) / Double(width), height: Double(y1 - y0 + 1) / Double(height))
    }
    func connected(at point: CGPoint) throws -> Self? {
        guard contains(point) else { return nil }
        let sx = min(width - 1, Int(point.x * Double(width))), sy = min(height - 1, Int(point.y * Double(height)))
        let seed = sy * width + sx
        var seen = [UInt8](repeating: 0, count: values.count), queue = [seed], cursor = 0
        seen[seed] = values[seed]
        while cursor < queue.count {
            if cursor % 4096 == 0 { try Task.checkCancellation() }
            let i = queue[cursor]; cursor += 1; let x = i % width, y = i / width
            for dy in -1...1 { for dx in -1...1 {
                let nx = x + dx, ny = y + dy
                if nx >= 0 && nx < width && ny >= 0 && ny < height {
                    let next = ny * width + nx
                    if values[next] > 24 && seen[next] == 0 { seen[next] = values[next]; queue.append(next) }
                }
            } }
        }
        guard queue.count > max(40, width * height / 500), queue.count < width * height * 9 / 10 else { return nil }
        let result = Self(width: width, height: height, values: seen)
        guard let bounds = result.bounds, !(bounds.width > 0.98 && bounds.height > 0.98) else { return nil }
        return result
    }
    func contains(_ normalized: CGPoint) -> Bool {
        guard normalized.x >= 0, normalized.y >= 0, normalized.x < 1, normalized.y < 1 else { return false }
        return values[min(height - 1, Int(normalized.y * Double(height))) * width + min(width - 1, Int(normalized.x * Double(width)))] > 128
    }
}

/// Conservative operator fallback for separated objects against a consistent background.
/// A textured background is delegated to Vision rather than clipping an arbitrary color patch.
enum ContrastSubjectDetector {
    static func mask(_ image: CGImage, at point: CGPoint) throws -> SubjectMask? {
        let raster = try SubjectRaster(image, maximum: 384), w = raster.width, h = raster.height
        guard w >= 12, h >= 12 else { return nil }
        var border: [Int] = []
        for x in stride(from: 0, to: w, by: 3) { border.append(x); border.append((h - 1) * w + x) }
        for y in stride(from: 0, to: h, by: 3) { border.append(y * w); border.append(y * w + w - 1) }
        let background = (0..<3).map { c in border.map { Int(raster.rgba[$0 * 4 + c]) }.sorted()[border.count / 2] }
        func difference(_ i: Int) -> Int { (0..<3).map { abs(Int(raster.rgba[i * 4 + $0]) - background[$0]) }.max() ?? 0 }
        guard Double(border.filter { difference($0) < 24 }.count) / Double(border.count) > 0.78 else { return nil }
        var foreground = [UInt8](repeating: 0, count: w * h)
        for y in 0..<h {
            if y % 32 == 0 { try Task.checkCancellation() }
            for x in 0..<w { let i = y * w + x; if difference(i) > 35 && raster.rgba[i * 4 + 3] > 64 { foreground[i] = 255 } }
        }
        let seedX = min(w - 1, max(0, Int(point.x * Double(w)))), seedY = min(h - 1, max(0, Int(point.y * Double(h))))
        let seed = seedY * w + seedX
        guard foreground[seed] != 0 else { return nil }
        var selected = [UInt8](repeating: 0, count: w * h), queue = [seed], cursor = 0
        selected[seed] = 255
        while cursor < queue.count {
            if cursor % 4096 == 0 { try Task.checkCancellation() }
            let i = queue[cursor]; cursor += 1; let x = i % w, y = i / w
            for dy in -1...1 { for dx in -1...1 {
                let nx = x + dx, ny = y + dy
                if nx >= 0 && nx < w && ny >= 0 && ny < h {
                    let next = ny * w + nx
                    if foreground[next] != 0 && selected[next] == 0 { selected[next] = 255; queue.append(next) }
                }
            } }
        }
        guard queue.count > max(40, w * h / 350), queue.count < w * h * 4 / 5 else { return nil }
        let mask = SubjectMask(width: w, height: h, values: selected)
        guard let bounds = mask.bounds, bounds.width * Double(w) >= 10, bounds.height * Double(h) >= 10,
              !(bounds.width > 0.95 && bounds.height > 0.95) else { return nil }
        let occupancy = Double(queue.count) / (bounds.width * bounds.height * Double(w * h))
        if occupancy > 0.93 && (bounds.width > 0.90 || bounds.height > 0.90) { return nil }
        // Sobel gradient at the chosen component's silhouette rejects flat/ambiguous patches.
        var gradient = 0.0, edges = 0
        func luminance(_ x: Int, _ y: Int) -> Double {
            let i = (y * w + x) * 4
            return 0.2126 * Double(raster.rgba[i]) + 0.7152 * Double(raster.rgba[i + 1]) + 0.0722 * Double(raster.rgba[i + 2])
        }
        for i in queue {
            let x = i % w, y = i / w
            guard x > 0, x < w - 1, y > 0, y < h - 1,
                  selected[i - 1] == 0 || selected[i + 1] == 0 || selected[i - w] == 0 || selected[i + w] == 0 else { continue }
            let gx = -luminance(x - 1, y - 1) + luminance(x + 1, y - 1) - 2 * luminance(x - 1, y) + 2 * luminance(x + 1, y) - luminance(x - 1, y + 1) + luminance(x + 1, y + 1)
            let gy = -luminance(x - 1, y - 1) - 2 * luminance(x, y - 1) - luminance(x + 1, y - 1) + luminance(x - 1, y + 1) + 2 * luminance(x, y + 1) + luminance(x + 1, y + 1)
            gradient += hypot(gx, gy); edges += 1
        }
        guard edges > 8, gradient / Double(edges) > 50 else { return nil }
        return mask
    }
}

struct ImageSubjectSelection {
    let source: PointTarget
    let sourceRect: CGRect
    let screenRect: CGRect
    let image: CGImage
    let highlight: CGImage
    let mask: SubjectMask
    let signature: [UInt8]
    func contains(_ point: CGPoint) -> Bool {
        mask.contains(CGPoint(x: (point.x - sourceRect.minX) / sourceRect.width, y: (point.y - sourceRect.minY) / sourceRect.height))
    }
    func prepared() -> PreparedPointTarget {
        PreparedPointTarget(target: PointTarget(payload: .image(screenRect), title: source.title + " · 主体", bounds: screenRect), image: image, isSubject: true)
    }
}

enum ImageSubjectAnalyzer {
    private static let lock = NSLock()
    static func analyze(_ image: CGImage, point: CGPoint, source: PointTarget, rect: CGRect, useVision: Bool = true) throws -> ImageSubjectSelection? {
        lock.lock(); defer { lock.unlock() }
        try Task.checkCancellation()
        let mask: SubjectMask?
        if let contrast = try ContrastSubjectDetector.mask(image, at: point) { mask = contrast }
        else if useVision { mask = try visionMask(image, at: point)?.connected(at: point) }
        else { mask = nil }
        try Task.checkCancellation()
        guard let mask, mask.contains(point) else { return nil }
        return try compose(image, mask: mask, source: source, rect: rect)
    }
    static func visionMask(_ image: CGImage, at point: CGPoint) throws -> SubjectMask? {
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request]); try Task.checkCancellation()
        guard let observation = request.results?.first else { return nil }
        let instances = observation.instanceMask
        CVPixelBufferLockBaseAddress(instances, .readOnly)
        let w = CVPixelBufferGetWidth(instances), h = CVPixelBufferGetHeight(instances)
        let x = min(w - 1, max(0, Int(point.x * Double(w)))), y = min(h - 1, max(0, Int(point.y * Double(h))))
        let label = CVPixelBufferGetBaseAddress(instances).map { $0.assumingMemoryBound(to: UInt8.self)[y * CVPixelBufferGetBytesPerRow(instances) + x] } ?? 0
        CVPixelBufferUnlockBaseAddress(instances, .readOnly)
        guard label != 0, observation.allInstances.contains(Int(label)) else { return nil }
        let scaled = try observation.generateScaledMaskForImage(forInstances: IndexSet(integer: Int(label)), from: handler)
        CVPixelBufferLockBaseAddress(scaled, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(scaled, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(scaled) else { return nil }
        let fullWidth = CVPixelBufferGetWidth(scaled), fullHeight = CVPixelBufferGetHeight(scaled)
        let factor = min(1, 640.0 / Double(max(fullWidth, fullHeight)))
        let width = max(1, Int(Double(fullWidth) * factor)), height = max(1, Int(Double(fullHeight) * factor))
        let rowBytes = CVPixelBufferGetBytesPerRow(scaled), format = CVPixelBufferGetPixelFormatType(scaled)
        guard format == kCVPixelFormatType_OneComponent8 || format == kCVPixelFormatType_OneComponent32Float else { return nil }
        var bytes = [UInt8](repeating: 0, count: width * height)
        for y in 0..<height { for x in 0..<width {
            let sy = min(fullHeight - 1, y * fullHeight / height), sx = min(fullWidth - 1, x * fullWidth / width)
            let row = base.advanced(by: sy * rowBytes)
            bytes[y * width + x] = format == kCVPixelFormatType_OneComponent8 ? row.assumingMemoryBound(to: UInt8.self)[sx] :
                UInt8(max(0, min(255, row.assumingMemoryBound(to: Float.self)[sx] * 255)))
        } }
        return SubjectMask(width: width, height: height, values: bytes)
    }
    static func signature(_ image: CGImage, sourceRect: CGRect, focusRect: CGRect) throws -> [UInt8] {
        let focus = CGRect(x: (focusRect.minX - sourceRect.minX) / sourceRect.width * Double(image.width),
            y: (focusRect.minY - sourceRect.minY) / sourceRect.height * Double(image.height),
            width: focusRect.width / sourceRect.width * Double(image.width), height: focusRect.height / sourceRect.height * Double(image.height))
            .integral.intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard let crop = image.cropping(to: focus) else { throw PointCaptureError.unavailable }
        return try SubjectRaster(image, maximum: 192).signature + SubjectRaster(crop, maximum: 192).signature
    }
    static func compose(_ image: CGImage, mask: SubjectMask, source: PointTarget, rect: CGRect) throws -> ImageSubjectSelection? {
        guard let bounds = mask.bounds else { return nil }
        let raster = try SubjectRaster(image)
        let crop = CGRect(x: bounds.minX * Double(raster.width), y: bounds.minY * Double(raster.height),
            width: bounds.width * Double(raster.width), height: bounds.height * Double(raster.height))
            .insetBy(dx: -2, dy: -2).integral.intersection(CGRect(x: 0, y: 0, width: raster.width, height: raster.height))
        let w = Int(crop.width), h = Int(crop.height)
        guard w > 2, h > 2 else { return nil }
        var output = [UInt8](repeating: 0, count: w * h * 4)
        func opacity(_ x: Int, _ y: Int) -> UInt8 {
            let px = (Double(x) + 0.5) * Double(mask.width) / Double(raster.width) - 0.5
            let py = (Double(y) + 0.5) * Double(mask.height) / Double(raster.height) - 0.5
            let x0 = Int(floor(px)), y0 = Int(floor(py)), fx = px - floor(px), fy = py - floor(py)
            func value(_ x: Int, _ y: Int) -> Double {
                guard x >= 0, x < mask.width, y >= 0, y < mask.height else { return 0 }
                return Double(mask.values[y * mask.width + x])
            }
            let a = value(x0, y0) * (1 - fx) + value(x0 + 1, y0) * fx
            let b = value(x0, y0 + 1) * (1 - fx) + value(x0 + 1, y0 + 1) * fx
            return UInt8(min(255, max(0, a * (1 - fy) + b * fy)))
        }
        for y in 0..<h {
            if y % 64 == 0 { try Task.checkCancellation() }
            for x in 0..<w {
                let sx = Int(crop.minX) + x, sy = Int(crop.minY) + y, alpha = Int(opacity(sx, sy))
                let input = (sy * raster.width + sx) * 4, out = (y * w + x) * 4
                for c in 0..<4 { output[out + c] = UInt8(Int(raster.rgba[input + c]) * alpha / 255) }
            }
        }
        guard let cutout = SubjectRaster.image(output, width: w, height: h) else { return nil }
        // Highlight uses the exact same crop as the exported object.
        let hw = max(1, Int(ceil(crop.width / Double(raster.width) * Double(mask.width))))
        let hh = max(1, Int(ceil(crop.height / Double(raster.height) * Double(mask.height))))
        var light = [UInt8](repeating: 0, count: hw * hh * 4)
        for y in 0..<hh { for x in 0..<hw {
            let mx = min(mask.width - 1, max(0, Int((crop.minX + Double(x) / Double(hw) * crop.width) / Double(raster.width) * Double(mask.width))))
            let my = min(mask.height - 1, max(0, Int((crop.minY + Double(y) / Double(hh) * crop.height) / Double(raster.height) * Double(mask.height))))
            let a = Int(mask.values[my * mask.width + mx])
            var low = a, high = a
            for dy in -1...1 { for dx in -1...1 {
                let nx = mx + dx, ny = my + dy
                let value = nx >= 0 && nx < mask.width && ny >= 0 && ny < mask.height ? Int(mask.values[ny * mask.width + nx]) : 0
                low = min(low, value); high = max(high, value)
            } }
            let alpha = UInt8(min(245, max(a / 7, high - low))), i = (y * hw + x) * 4
            light[i] = UInt8(Int(alpha) * 110 / 255); light[i + 1] = alpha; light[i + 2] = UInt8(Int(alpha) * 207 / 255); light[i + 3] = alpha
        } }
        guard let highlight = SubjectRaster.image(light, width: hw, height: hh) else { return nil }
        let screenRect = CGRect(x: rect.minX + crop.minX / Double(raster.width) * rect.width,
            y: rect.minY + crop.minY / Double(raster.height) * rect.height,
            width: crop.width / Double(raster.width) * rect.width, height: crop.height / Double(raster.height) * rect.height)
        return ImageSubjectSelection(source: source, sourceRect: rect, screenRect: screenRect, image: cutout, highlight: highlight,
            mask: mask, signature: try signature(image, sourceRect: rect, focusRect: screenRect))
    }
}
