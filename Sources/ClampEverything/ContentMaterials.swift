import SwiftUI
import ClampCore

extension FolderTint {
    var base: Color {
        switch self {
        case .kraft: return Color(red: 0.76, green: 0.57, blue: 0.31)
        case .ocean: return Color(red: 0.39, green: 0.61, blue: 0.72)
        case .sage: return Color(red: 0.51, green: 0.65, blue: 0.48)
        }
    }
    var face: Color {
        switch self {
        case .kraft: return Color(red: 0.92, green: 0.79, blue: 0.57)
        case .ocean: return Color(red: 0.72, green: 0.84, blue: 0.89)
        case .sage: return Color(red: 0.79, green: 0.85, blue: 0.70)
        }
    }
}

struct FolderSilhouette: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        let tab = min(24, h * 0.18), r = min(9, w * 0.08)
        var path = Path()
        path.move(to: CGPoint(x: r, y: tab))
        path.addLine(to: CGPoint(x: w * 0.10, y: tab))
        path.addQuadCurve(to: CGPoint(x: w * 0.14, y: 0), control: CGPoint(x: w * 0.11, y: 0))
        path.addLine(to: CGPoint(x: w * 0.52, y: 0))
        path.addQuadCurve(to: CGPoint(x: w * 0.59, y: tab), control: CGPoint(x: w * 0.56, y: 0))
        path.addLine(to: CGPoint(x: w - r, y: tab))
        path.addQuadCurve(to: CGPoint(x: w, y: tab + r), control: CGPoint(x: w, y: tab))
        path.addLine(to: CGPoint(x: w, y: h - r))
        path.addQuadCurve(to: CGPoint(x: w - r, y: h), control: CGPoint(x: w, y: h))
        path.addLine(to: CGPoint(x: r, y: h))
        path.addQuadCurve(to: CGPoint(x: 0, y: h - r), control: CGPoint(x: 0, y: h))
        path.addLine(to: CGPoint(x: 0, y: tab + r))
        path.addQuadCurve(to: CGPoint(x: r, y: tab), control: CGPoint(x: 0, y: tab))
        path.closeSubpath()
        return path
    }
}

/// Code-drawn layers keep the tab, seams and pocket crisp at every window size.
struct FolderMaterial: View {
    var tint: FolderTint
    var title = ""
    var opening: CGFloat = 1
    var layers: Int = 1
    var dragPull = PaperPull.resting
    var motionDisabled = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        GeometryReader { geometry in
            let compact = geometry.size.width < 100
            let tabHeight: CGFloat = compact ? 5 : 24
            ZStack(alignment: .topLeading) {
                FolderSilhouette().fill(LinearGradient(colors: [tint.base, tint.base.opacity(0.88)], startPoint: .top, endPoint: .bottom))
                RoundedRectangle(cornerRadius: compact ? 2 : 8)
                    .fill(Color.white.opacity(0.34)).padding(.horizontal, compact ? 3 : 10)
                    .padding(.top, tabHeight + (compact ? 2 : 7)).padding(.bottom, compact ? 3 : 12)
                    .shadow(color: .black.opacity(0.13), radius: 2, y: -1)
                if !compact {
                    ForEach(0..<min(4, max(1, layers)), id: \.self) { layer in
                        RoundedRectangle(cornerRadius: 5).fill(Color(white: 0.96 - Double(layer) * 0.035))
                            .overlay(RoundedRectangle(cornerRadius: 5).stroke(.black.opacity(0.08), lineWidth: 0.5))
                            .padding(.horizontal, 13 + CGFloat(layer) * 2)
                            .padding(.top, 40 - PocketGeometry.amount(opening) * 12 + CGFloat(layer) * PocketGeometry.mouthGap(opening) * 0.5)
                            .padding(.bottom, 9)
                            .offset(x: dragPull.x * CGFloat(layer + 1) * 1.5, y: dragPull.y * CGFloat(layer + 1) * 1.2)
                    }
                }
                PocketFront(opening: compact ? 0 : opening - abs(dragPull.x) * 0.3 + dragPull.y * 0.2)
                    .fill(LinearGradient(colors: [tint.face, tint.face.opacity(0.98), tint.base.opacity(0.82)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(PocketFront(opening: compact ? 0 : opening - abs(dragPull.x) * 0.3 + dragPull.y * 0.2).stroke(.white.opacity(0.45), lineWidth: 0.7))
                    .shadow(color: .black.opacity(0.16), radius: compact ? 1 : 1 + PocketGeometry.mouthGap(opening) * 0.25, y: -2)
                    .overlay(alignment: .bottom) {
                        VStack(spacing: 3) {
                            ForEach(0..<3) { _ in Capsule().fill(.black.opacity(0.045)).frame(height: 1).shadow(color: .white.opacity(0.6), radius: 0, y: 1) }
                        }.padding(.horizontal, compact ? 4 : 15).padding(.bottom, compact ? 3 : 12)
                    }
                if !compact {
                    Text(title).font(.system(size: 10, weight: .semibold)).lineLimit(1)
                        .foregroundStyle(Color.black.opacity(0.65))
                        .padding(.horizontal, 10).frame(width: geometry.size.width * 0.43, height: 23)
                        .background(.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 4))
                        .offset(x: geometry.size.width * 0.13, y: 1)
                }
                Canvas { context, size in
                    for x in stride(from: 4.0, to: size.width, by: 4) {
                        var line = Path(); line.move(to: CGPoint(x: x, y: tabHeight + 20)); line.addLine(to: CGPoint(x: x, y: size.height))
                        context.stroke(line, with: .color(.brown.opacity(0.025)), lineWidth: 0.4)
                    }
                }
            }.clipShape(FolderSilhouette())
                .overlay(FolderSilhouette().stroke(.black.opacity(0.18), lineWidth: 0.8))
        }.allowsHitTesting(false)
            .animation(reduceMotion || motionDisabled ? nil : .spring(response: 0.55, dampingFraction: 0.65), value: dragPull)
    }
}

struct HousingMaterial: View {
    let housing: ContentHousing
    let id: UUID
    let preferences: AppPreferences
    var title = ""
    var pull = PaperPull.resting
    var isLeft = false
    var material: PhysicalMaterial = .file
    var opening: CGFloat = 1
    var layers: Int = 1
    var dragPull = PaperPull.resting
    var body: some View {
        switch housing {
        case .folder, .collection: FolderMaterial(tint: preferences.folderTint, title: title, opening: opening, layers: layers, dragPull: dragPull, motionDisabled: preferences.motionIntensity == 0)
        case .note: PaperMaterial(id: id, pull: pull, isLeft: isLeft, stock: preferences.noteStock)
        case .file: FileMaterial(material: material)
        case .link: BookmarkMaterial()
        case .photo: Color.clear
        }
    }
}

struct HousingFinish: ViewModifier {
    let housing: ContentHousing
    var pull: PaperPull
    var fold: CGFloat
    var isLeft: Bool
    @ViewBuilder func body(content: Content) -> some View {
        if housing.isFlexible {
            content
                .overlay { SheetLighting(pull: pull, isLeft: isLeft, photo: housing == .photo) }
                .clipShape(SoftSheetMask(pull: pull, fold: fold, isLeft: isLeft))
                .contentShape(SoftSheetMask(pull: pull, fold: fold, isLeft: isLeft))
                .overlay { SheetFoldFace(amount: fold, pull: pull, isLeft: isLeft, photo: housing == .photo) }
        } else if housing == .folder || housing == .collection {
            content.clipShape(FolderSilhouette()).contentShape(FolderSilhouette())
        } else if housing == .link {
            content.clipShape(BookmarkShape(), style: FillStyle(eoFill: true)).contentShape(BookmarkShape(), eoFill: true)
        } else {
            content.clipShape(RoundedRectangle(cornerRadius: 12)).contentShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}
