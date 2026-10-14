import SwiftUI
import ClampCore

struct MaterialCatalogView: View {
    @ObservedObject var store: ClipStore
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("能夹什么 · 对应的拟物形态").font(.system(size: 14, weight: .semibold))
            Text("拖动左侧样品，感受不同材质的摆动与回弹。实际使用时拖动金属夹移动材料；拖出内容则交给其他应用。").font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            ForEach(PhysicalMaterial.allCases, id: \.self) { material in
                HStack(alignment: .center, spacing: 16) {
                    MaterialSample(material: material, preferences: store.state.preferences)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(material.title).font(.system(size: 12, weight: .medium))
                        Text(material.supportedContent).font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        Text(material.motionDescription).font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                if material != PhysicalMaterial.allCases.last { Divider() }
            }
            Text("音频、视频和压缩包显示对应的拟物外观；打开时仍使用系统关联应用。").font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct MaterialSample: View {
    let material: PhysicalMaterial
    let preferences: AppPreferences
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pull = PaperPull.resting
    private let sampleID = UUID(uuidString: "89DD011C-E5A5-43AA-8A87-D0BFE30D7942")!
    private var disabled: Bool { reduceMotion || preferences.motionIntensity == 0 }
    private var effectivePull: PaperPull {
        disabled ? .resting : PaperPull(x: pull.x * preferences.motionIntensity, y: pull.y * preferences.motionIntensity)
    }
    private var housing: ContentHousing {
        switch material {
        case .note: return .note
        case .photo: return .photo
        case .folder: return .folder
        case .collection: return .collection
        case .bookmark: return .link
        default: return .file
        }
    }
    var body: some View {
        ZStack(alignment: .topTrailing) {
            ZStack {
                if material == .photo {
                    RoundedRectangle(cornerRadius: 2).fill(Color.white)
                        .overlay(RoundedRectangle(cornerRadius: 2).stroke(Color.gray.opacity(0.3)))
                    Image(systemName: "mountain.2.fill").font(.system(size: 32)).foregroundStyle(.white)
                        .frame(width: 78, height: 65)
                        .background(LinearGradient(colors: [.cyan.opacity(0.6), .teal], startPoint: .top, endPoint: .bottom))
                } else {
                    HousingMaterial(housing: housing, id: sampleID, preferences: preferences,
                                    pull: effectivePull, material: material,
                                    layers: material == .collection ? 3 : 1, dragPull: effectivePull)
                    if [.audio, .film, .archive].contains(material) {
                        Image(systemName: material == .audio ? "waveform" : (material == .film ? "film" : "archivebox"))
                            .font(.system(size: 24)).foregroundStyle(.white.opacity(0.9))
                            .frame(width: 55, height: 38).background(Color.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 5))
                            .padding(.top, 12)
                    }
                }
            }
            .frame(width: 94, height: 92).padding(9)
            .modifier(MaterialMovement(material: material, pull: effectivePull, isLeft: false, disabled: disabled))
            MetalClip(openness: material.jawOpening).padding(.top, 12).padding(.trailing, 10)
        }
        .frame(width: 112, height: 110).padding(8)
        .environment(\.colorScheme, .light)
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 1)
            .onChanged { value in
                pull = PaperPull(x: max(-1, min(1, value.translation.width / 60)),
                                 y: max(-1, min(1, -value.translation.height / 60)))
            }
            .onEnded { _ in pull = .resting })
        .help("拖动试试，松手回弹")
        .accessibilityLabel(material.title + "，可拖动预览")
    }
}
