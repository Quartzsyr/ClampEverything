import SwiftUI
import AppKit
import ClampCore

/// Stable per-item variation: never use Swift's process-randomized Hasher here.
struct PaperGrain {
    let seed: UInt64
    init(id: UUID) {
        seed = id.uuidString.utf8.reduce(UInt64(14695981039346656037)) { ($0 ^ UInt64($1)) &* 1099511628211 }
    }
    func value(_ index: Int) -> Double {
        var n = seed &+ UInt64(index) &* 0x9E3779B97F4A7C15
        n = (n ^ (n >> 30)) &* 0xBF58476D1CE4E5B9
        n = (n ^ (n >> 27)) &* 0x94D049BB133111EB
        return Double((n ^ (n >> 31)) >> 11) / Double(UInt64(1) << 53)
    }
}

struct PaperEdge: Shape {
    let grain: PaperGrain
    var pull = PaperPull.resting
    var isLeft = false
    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(pull.x, pull.y) }
        set { pull = PaperPull(x: newValue.first, y: newValue.second) }
    }
    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: 2, dy: 2)
        let amount = min(2.4, min(r.width, r.height) * 0.025)
        var points: [CGPoint] = []
        for side in 0..<4 {
            for step in 0..<18 {
                let t = CGFloat(step) / 18
                let wobble = CGFloat(grain.value(side * 18 + step) - 0.5) * amount
                switch side {
                case 0: points.append(CGPoint(x: r.minX + r.width * t, y: r.minY + wobble))
                case 1: points.append(CGPoint(x: r.maxX + wobble, y: r.minY + r.height * t))
                case 2: points.append(CGPoint(x: r.maxX - r.width * t, y: r.maxY + wobble))
                default: points.append(CGPoint(x: r.minX + wobble, y: r.maxY - r.height * t))
                }
            }
        }
        points = points.map { SoftSheetGeometry.point($0, size: rect.size, pull: pull, isLeft: isLeft) }
        return Path { p in p.addLines(points); p.closeSubpath() }
    }
}

struct PaperMaterial: View {
    let id: UUID
    var pull = PaperPull.resting
    var isLeft = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var effectivePull: PaperPull { reduceMotion ? .resting : pull }
    var stock: NoteStock = .natural
    var grain: PaperGrain { PaperGrain(id: id) }
    var body: some View {
        SoftImageSurface(image: GeneratedAssets.image("paper-calm-v2"), pull: effectivePull, isLeft: isLeft)
            .brightness(grain.value(82) * 0.015)
            .overlay {
                if stock != .natural { Color(red: 1, green: 0.98, blue: 0.92).opacity(0.8) }
                if stock == .ruled {
                    Canvas { context, size in
                        for y in stride(from: 52.0, to: size.height, by: 25) {
                            var line = Path(); line.move(to: CGPoint(x: 12, y: y)); line.addLine(to: CGPoint(x: size.width - 12, y: y))
                            context.stroke(line, with: .color(.blue.opacity(0.12)), lineWidth: 0.6)
                        }
                    }
                }
            }
            .overlay {
                Canvas { context, size in
                    // A unique, quiet fold supplements the generated cotton-paper texture.
                    let y = size.height * (0.25 + grain.value(900) * 0.5)
                    var fold = Path(); fold.move(to: CGPoint(x: 7, y: y))
                    fold.addQuadCurve(to: CGPoint(x: size.width - 7, y: y + 14), control: CGPoint(x: size.width * 0.6, y: y - 10))
                    context.stroke(fold, with: .color(.brown.opacity(0.025)), lineWidth: 1)
                    // Short tension creases and contact shade originate underneath the jaw.
                    let grip = CGPoint(x: isLeft ? 28 : size.width - 5, y: 8)
                    let direction: CGFloat = isLeft ? 1 : -1
                    let tension = abs(effectivePull.x) + abs(effectivePull.y)
                    for index in 0..<2 {
                        var crease = Path(); crease.move(to: grip)
                        crease.addQuadCurve(to: CGPoint(x: grip.x + direction * (28 + CGFloat(index) * 16), y: 40 + CGFloat(index) * 10), control: CGPoint(x: grip.x + direction * 10, y: 20))
                        context.stroke(crease, with: .color(.brown.opacity(0.025 + Double(tension) * 0.025)), lineWidth: 1)
                    }
                    let contact = Path(ellipseIn: CGRect(x: grip.x - 14, y: 2, width: 28, height: 9))
                    context.addFilter(.blur(radius: 3))
                    context.fill(contact, with: .color(.black.opacity(0.1)))
                }.padding(7)
            }
            .clipShape(PaperEdge(grain: grain, pull: effectivePull, isLeft: isLeft))
            .animation(reduceMotion ? nil : .spring(response: 0.46, dampingFraction: 0.64), value: pull)
            .allowsHitTesting(false)
    }
}

struct PhotoFinish: ViewModifier {
    var cutout = false
    var pull = PaperPull.resting
    var isLeft = false
    @ViewBuilder func body(content: Content) -> some View {
        if cutout { content.shadow(color: .black.opacity(0.16), radius: 1.5, y: 1) }
        else { content
            .clipShape(SoftSheetMask(pull: pull, isLeft: isLeft))
            .overlay {
                LinearGradient(stops: [.init(color: .white.opacity(0.08), location: 0), .init(color: .white.opacity(0.01), location: max(0.08, min(0.7, 0.28 + Double(pull.x) * 0.16))), .init(color: .clear, location: 0.75), .init(color: .white.opacity(0.025), location: 1)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .allowsHitTesting(false)
            }
            .overlay(SoftSheetMask(pull: pull, isLeft: isLeft).stroke(LinearGradient(colors: [.white.opacity(0.65), .white.opacity(0.12), .black.opacity(0.16), .white.opacity(0.4)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.65).allowsHitTesting(false))
            .background(SoftSheetMask(pull: pull, isLeft: isLeft).fill(Color(white: 0.93)).offset(y: 1.2))
        }
    }
}

extension View {
    @ViewBuilder func settingsGlass() -> some View {
        if #available(macOS 26.0, *) { self.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 26)) }
        else { self.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 26)).overlay(RoundedRectangle(cornerRadius: 26).stroke(.white.opacity(0.4), lineWidth: 0.75)) }
    }
}
