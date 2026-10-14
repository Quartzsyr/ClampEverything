import SwiftUI
import AppKit

/// Three ImageGen poses share one physical scale and a left-mouth anchor.
@MainActor enum CursorAtlas {
    struct Pose {
        let image: NSImage
        let size: CGSize
        let offset: CGSize
    }
    static let poses: [Pose] = {
        let atlas = GeneratedAssets.image("cursor-clip-motion-v2")
        guard let cg = atlas.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return [] }
        var crops: [CGImage] = []
        var mouths: [CGPoint] = []
        // Mouth centres measured in the original equal atlas cells. Align the
        // contact point, not the changing silhouette (the handles move too).
        let mouthY: [CGFloat] = [0.50, 0.52, 0.55]
        for column in 0..<3 {
            let left = cg.width * column / 3, right = cg.width * (column + 1) / 3
            let inset = max(2, (right - left) / 80)
            guard let cell = cg.cropping(to: CGRect(x: left + inset, y: 0, width: right - left - 2 * inset, height: cg.height)) else { continue }
            let bounds = alphaBounds(cell)
            guard let cropped = cell.cropping(to: bounds) else { continue }
            crops.append(cropped)
            mouths.append(CGPoint(x: 0, y: CGFloat(cg.height) * mouthY[column] - bounds.minY))
        }
        let width = CGFloat(crops.map(\.width).max() ?? 1), height = CGFloat(crops.map(\.height).max() ?? 1)
        let scale = min(54 / width, 36 / height)
        return crops.enumerated().map { index, image in
            Pose(image: NSImage(cgImage: image, size: .zero),
                 size: CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale),
                 offset: CGSize(width: 0, height: 18 - mouths[index].y * scale))
        }
    }()
    static func alphaBounds(_ image: CGImage) -> CGRect {
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let found: CGRect? = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
                let bytes = buffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return nil }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            var left = width, right = -1, top = height, bottom = -1
            for y in 0..<height {
                for x in 0..<width where bytes[(y * width + x) * 4 + 3] > 24 {
                    left = min(left, x); right = max(right, x); top = min(top, y); bottom = max(bottom, y)
                }
            }
            guard right >= left, bottom >= top else { return nil }
            return CGRect(x: left, y: top, width: right - left + 1, height: bottom - top + 1)
        }
        return found ?? CGRect(x: 0, y: 0, width: width, height: height)
    }
    static func poseIndex(_ openness: Double) -> Int {
        if openness >= 0.75 { return 0 }
        if openness >= 0.25 { return 1 }
        return 2
    }
}

struct ImageGenCursorClip: View, Animatable {
    var openness: Double
    var animatableData: Double { get { openness } set { openness = newValue } }
    var body: some View {
        let index = CursorAtlas.poseIndex(openness)
        Group {
            if CursorAtlas.poses.indices.contains(index) {
                let pose = CursorAtlas.poses[index]
                Image(nsImage: pose.image).resizable().interpolation(.high)
                    .frame(width: pose.size.width, height: pose.size.height)
                    .offset(pose.offset)
                    .frame(width: 54, height: 36, alignment: .topLeading)
            } else { Color.clear.frame(width: 54, height: 36) }
        }.frame(width: 54, height: 36).shadow(color: .black.opacity(0.18), radius: 1, y: 1)
            .accessibilityHidden(true)
    }
}
