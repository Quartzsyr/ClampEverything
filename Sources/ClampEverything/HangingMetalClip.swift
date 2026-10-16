import AppKit
import SwiftUI

/// Reference-based silver clip, with its original teardrop loop raised at the hinges.
@MainActor enum HangingClipAtlas {
    struct Pose {
        let image: NSImage
        let size: CGSize
        let offset: CGSize
    }
    static let poses: [Pose] = {
        let atlas = GeneratedAssets.image("hanging-clip-silver")
        guard let cg = atlas.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return [] }
        let crops: [CGImage] = (0..<3).compactMap { column in
            let x = cg.width * column / 3, end = cg.width * (column + 1) / 3
            guard let cell = cg.cropping(to: CGRect(x: x, y: 0, width: end - x, height: cg.height)) else { return nil }
            return cell.cropping(to: CursorAtlas.alphaBounds(cell))
        }
        let scale = min(40 / CGFloat(crops.map(\.width).max() ?? 1), 52 / CGFloat(crops.map(\.height).max() ?? 1))
        return crops.map { cg in
            let size = CGSize(width: CGFloat(cg.width) * scale, height: CGFloat(cg.height) * scale)
            // The inside crown of the loop, rather than its outer silhouette,
            // rests against the underside of the nail head in every pose.
            return Pose(image: NSImage(cgImage: cg, size: .zero), size: size,
                        offset: CGSize(width: ClipOrientation.hook.x - size.width / 2,
                                       height: ClipOrientation.hook.y - size.height * 0.055))
        }
    }()
}

struct HangingMetalClip: View, Animatable {
    var openness: Double = 0
    var animatableData: Double { get { openness } set { openness = newValue } }
    var body: some View {
        let p = max(0, min(1, openness)) * 2
        ZStack(alignment: .topLeading) {
            ForEach(HangingClipAtlas.poses.indices, id: \.self) { index in
                let pose = HangingClipAtlas.poses[index]
                Image(nsImage: pose.image).resizable().interpolation(.high)
                    .frame(width: pose.size.width, height: pose.size.height)
                    .offset(pose.offset)
                    .opacity(max(0, 1 - abs(p - Double(index))))
            }
        }
        .frame(width: ClipOrientation.size.width, height: ClipOrientation.size.height, alignment: .topLeading)
        .shadow(color: .black.opacity(0.2), radius: 1, y: 1)
        .accessibilityHidden(true)
    }
}

struct HangingBackJaw: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(LinearGradient(colors: [Color(white: 0.55), Color(white: 0.9), Color(white: 0.45)], startPoint: .top, endPoint: .bottom))
            .frame(width: 37, height: 7).position(x: 22, y: 56)
            .frame(width: ClipOrientation.size.width, height: ClipOrientation.size.height)
            .allowsHitTesting(false).accessibilityHidden(true)
    }
}

/// Kept outside the rotating assembly, so the metal loop moves around this head.
struct SuspensionNail: View {
    var body: some View {
        Circle()
            .fill(RadialGradient(colors: [Color(white: 0.99), Color(white: 0.72), Color(white: 0.33)], center: .topLeading, startRadius: 0, endRadius: 5))
            .overlay(Circle().strokeBorder(.black.opacity(0.28), lineWidth: 0.5))
            .frame(width: 6, height: 6)
            .shadow(color: .black.opacity(0.45), radius: 1, x: 0.5, y: 1.5)
            .allowsHitTesting(false).accessibilityHidden(true)
    }
}
