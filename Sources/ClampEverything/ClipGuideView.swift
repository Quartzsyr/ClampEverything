import SwiftUI

/// The guide is a transparent annotation around the real receiving clip.
/// No card, sheet, toolbar or modal chrome is introduced.
struct ClipGuideView: View {
    var isLeft = false
    var includeClip = true
    static let size = CGSize(width: 350, height: 250)
    static let anchor = CGPoint(x: 320, y: 34)
    var body: some View {
        GeometryReader { geometry in
            let anchor = CGPoint(x: isLeft ? 30 : geometry.size.width - 30, y: 34)
            ZStack {
                Canvas { context, _ in
                    let direction: CGFloat = isLeft ? 1 : -1
                    for (index, y) in [CGFloat(8), 95, 151, 202].enumerated() {
                        let length: CGFloat = index < 2 ? 100 : 136
                        var line = Path()
                        line.move(to: CGPoint(x: anchor.x + direction * length, y: y))
                        line.addQuadCurve(to: CGPoint(x: anchor.x + direction * 25, y: anchor.y + CGFloat(index) * 6),
                            control: CGPoint(x: anchor.x + direction * 42, y: y))
                        context.stroke(line, with: .color(.white.opacity(0.48)), lineWidth: 0.75)
                    }
                }.shadow(color: .black.opacity(0.55), radius: 2, y: 1)
                label("单击 · 添加", x: anchor.x + (isLeft ? 146 : -146), y: 8)
                label("拖入 · 夹住", x: anchor.x + (isLeft ? 152 : -152), y: 95)
                label("右键 · 更多操作", x: anchor.x + (isLeft ? 179 : -179), y: 151)
                label("内容夹 · 悬停看，拖动拉出", x: anchor.x + (isLeft ? 177 : -177), y: 202)
                if includeClip {
                    MetalClip(receiver: true)
                        .scaleEffect(x: ClipOrientation.scale(isLeft: isLeft), y: 1)
                        .position(anchor)
                }
            }
        }.frame(width: Self.size.width, height: Self.size.height)
    }
    private func label(_ text: String, x: CGFloat, y: CGFloat) -> some View {
        Text(text).font(.system(size: 12, weight: .medium))
            .foregroundStyle(.white.opacity(0.92))
            .shadow(color: .black.opacity(0.65), radius: 3, y: 1)
            .position(x: x, y: y)
    }
}
