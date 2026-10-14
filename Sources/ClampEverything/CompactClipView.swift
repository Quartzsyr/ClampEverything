import SwiftUI
import ClampCore

struct CompactClipView: View {
    @ObservedObject var store: ClipStore
    let id: UUID
    let isLeft: Bool
    var open: () -> Void
    var interaction: (Bool) -> Void
    var item: ClipItem? { store.item(id) }
    var body: some View {
        thumbnail.frame(width: 36, height: 27)
            .rotationEffect(.degrees(isLeft ? -3 : 3))
            .overlay {
                if let item { ContentDragHandle(item: item, store: store, interaction: interaction, showLabel: false) }
            }
            .padding(.top, 12).padding(.bottom, 3)
            .padding(isLeft ? .leading : .trailing, 19)
            .frame(maxWidth: .infinity, alignment: isLeft ? .leading : .trailing)
            .help(item == nil ? "点击展开材料夹" : "拖出缩略图直接使用 · 轻点复制")
    }
    @ViewBuilder var thumbnail: some View {
        if let item, item.kind == .image, let image = store.images[id] {
            Image(nsImage: image).resizable().scaledToFill().frame(width: 36, height: 27).clipped().modifier(PhotoFinish())
        } else {
            ZStack {
                if item == nil {
                    FolderMaterial(tint: store.state.preferences.folderTint).offset(x: -3, y: -3)
                    FolderMaterial(tint: store.state.preferences.folderTint).offset(x: -1, y: -1)
                }
                HousingMaterial(housing: ContentHousing.forKind(item?.kind), id: id, preferences: store.state.preferences, material: PhysicalMaterial.forItem(item), layers: item == nil ? store.sceneMembers(id).count : 1)
                if let item { ClipIcon(item: item, size: 14) }

            }.onTapGesture { if item == nil { open() } }
        }
    }
}

