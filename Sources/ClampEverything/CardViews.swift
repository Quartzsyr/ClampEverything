import SwiftUI
import AppKit
import ClampCore

enum ClipStyle {
    static let accent = Color(red: 0.23, green: 0.40, blue: 0.39)
    static let paper = Color(nsColor: .controlBackgroundColor)
}

/// Three mechanically distinct imagegen poses blend through the spring travel.
struct MetalClip: View {
    var opened = false
    var receiver = false
    var openness: Double? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        ClipPoseSprite(openness: openness ?? (opened ? 1 : 0), receiver: receiver)
            .frame(width: 54, height: 32)
            .frame(width: 54, height: 36)
            .shadow(color: .black.opacity(0.22), radius: 1.5, y: 1)
            .animation(reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.78), value: opened)
            .animation(reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.78), value: openness)
            .accessibilityHidden(true)
    }
}

struct ClipPoseSprite: View, Animatable {
    var openness: Double
    var receiver = false
    var animatableData: Double {
        get { openness }
        set { openness = newValue }
    }
    var body: some View {
        let amount = min(1, max(0, openness))
        let base = receiver ? "clip-brass" : "clip-silver"
        ZStack {
            sprite(base).opacity(receiver ? 1 - amount : max(0, 1 - amount * 2))
            if !receiver { sprite("clip-silver-half").opacity(1 - abs(amount * 2 - 1)) }
            sprite(base + "-open").opacity(receiver ? amount : max(0, amount * 2 - 1))
        }
    }
    private func sprite(_ name: String) -> some View {
        Image(nsImage: GeneratedAssets.image(name)).resizable().interpolation(.high).scaledToFit()
    }
}

struct ClipIcon: View {
    let item: ClipItem
    var size: CGFloat = 28
    var body: some View {
        Group {
            if let path = item.originalPath { Image(nsImage: NSWorkspace.shared.icon(forFile: path)).resizable().scaledToFit() }
            else { Image(systemName: item.kind.symbol).resizable().scaledToFit().foregroundStyle(item.kind == .link ? ClipStyle.accent : .secondary) }
        }.frame(width: size, height: size).accessibilityHidden(true)
    }
}

struct RailView: View {
    @ObservedObject var store: ClipStore
    let manager: WindowManager
    let overflow: Int
    @State private var receiving = false
    var body: some View {
        MetalClip(opened: receiving, receiver: true)
            .scaleEffect(x: ClipOrientation.scale(isLeft: false), y: 1)
            .overlay(DropZone(label: "", receive: { store.ingest($0) }, interaction: { receiving = $0 }, click: { store.chooseFiles() }))
            .help(overflow > 0 ? "单击添加 · 拖入夹住；更多夹项在菜单栏" : "单击添加文件 · 拖入内容夹住 · 右键操作")
            .accessibilityLabel("黄铜加号夹子，拖入内容创建新夹子")
            .contextMenu {
                ScenePicker(store: store)
                Divider()
                Button("夹住剪贴板") { store.ingest(.general) }
                Button("添加文件或文件夹…") { store.chooseFiles() }
                Divider()
                Button("夹子使用指引") { manager.showGuide() }
                Button("设置…") { manager.showSettings() }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
    }
}

struct CardSurface: View {
    @ObservedObject var store: ClipStore
    @ObservedObject var model: CardModel
    let manager: WindowManager
    /// Native website exports keep the stationary nail as a separate layer.
    var showsNail = true
    /// WebKit's separately composited backing layer is captured by takeSnapshot
    /// for offline exports, then placed inside the unchanged native paper finish.
    var exportWebSnapshot: NSImage? = nil
    @State private var resizeOriginal: NSSize?
    @State private var hovering = false
    @State private var grouping = false
    @State private var settling: CGFloat = 0
    @State private var hoverPull = PaperPull.resting
    @State private var previousHover: CGPoint?
    @State private var surfaceSize = CGSize.zero
    @State private var fold: CGFloat = 0
    @State private var hoverReset: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var item: ClipItem? { store.item(model.id) }
    var group: ClipGroup? { store.group(model.id) }
    var housing: ContentHousing { ContentHousing.forKind(item?.kind) }
    var physical: PhysicalMaterial { PhysicalMaterial.forItem(item) }
    var layers: Int { item == nil ? max(1, store.sceneMembers(model.id).count) : (physical == .document ? 3 : 1) }
    var restingJaw: Double { min(0.38, physical.jawOpening + (item == nil ? Double(min(8, layers - 1)) * 0.018 : 0)) }
    var isFolder: Bool { housing == .folder || housing == .collection }
    var motionDisabled: Bool { reduceMotion || store.state.preferences.motionIntensity == 0 }
    var placement: ClipPlacement { item?.placement ?? group?.placement ?? ClipPlacement() }
    var title: String { item?.title ?? group?.title ?? "夹项" }
    var wide: Bool { model.expanded || placement.mode == .floating }
    var isLeft: Bool { placement.side == .left }
    var folderProgress: CGFloat {
        wide && placement.mode == .docked && !model.moving && !motionDisabled ? model.revealProgress : 1
    }
    var hingeProgress: CGFloat {
        wide ? (placement.mode == .docked && !model.moving && !motionDisabled ? model.revealProgress : 1) : 0
    }
    var paperPull: PaperPull {
        guard !motionDisabled, !model.moving else { return .resting }
        let strength = CGFloat(store.state.preferences.motionIntensity) * physical.flexibility
        return PaperPull(x: (model.paperPull.x + hoverPull.x) * strength, y: (model.paperPull.y + hoverPull.y + settling) * strength)
    }
    var dragPull: PaperPull {
        guard !motionDisabled else { return .resting }
        let strength = CGFloat(store.state.preferences.motionIntensity)
        return PaperPull(x: model.paperPull.x * strength + hoverPull.x * strength * 0.25,
                         y: model.paperPull.y * strength + hoverPull.y * strength * 0.25)
    }
    var moveGrip: some View {
        HangingMetalClip(openness: grouping || model.mergeReady ? 1 : (model.nearEdge ? 0.65 : (model.moving ? 0.35 : restingJaw)))
            .overlay(MoveHandle(begin: { model.beginMove() }, move: { model.move($0) }, end: { model.endMove() }, click: { if wide { model.close() } else { model.show() } }))
            .help("拖动夹子移动 · 靠近边缘松手夹住 · 单击收放")
            .accessibilityLabel(title + "，拖动移动，单击收放")
    }
    var materialTop: CGFloat {
        ClipOrientation.materialTop(housing: housing, height: model.sheetSize.height)
    }
    var clipPose: SuspendedClipScale {
        SuspendedClipScale(scale: ClipOrientation.displayScale)
    }
    var liftsRightCorner: Bool { PinnedContentForm.forItem(item) == .documentPrint || isLeft }
    var canLiftCorner: Bool { housing.isFlexible || PinnedContentForm.forItem(item).isManuscript }
    var foldGrip: some View {
        Color.clear.frame(width: 36, height: 36)
            .overlay {
                if hovering {
                    Path { path in
                        path.move(to: CGPoint(x: 5, y: 28))
                        path.addQuadCurve(to: CGPoint(x: 28, y: 5), control: CGPoint(x: 6, y: 7))
                    }.stroke(.gray.opacity(0.32), lineWidth: 0.7)
                        .scaleEffect(x: liftsRightCorner ? -1 : 1, y: 1).allowsHitTesting(false)
                }
            }
            .overlay(MoveHandle(begin: { hoverPull = .resting; model.interaction(true) },
                move: { delta in fold = min(1, hypot(delta.x, delta.y) / (physical == .photo ? 155 : 95)) },
                end: { fold = 0; model.interaction(false) }, label: "轻拉自由纸角卷起，松手回落"))
            .help(item?.kind == .image ? "轻拉照片角卷起 · 松手回落" : "轻拉纸角卷起 · 松手回落")
            .padding(8)
    }
    var body: some View {
        ZStack(alignment: isLeft ? .topLeading : .topTrailing) {
            HangingBackJaw().modifier(clipPose)
                .padding(.top, ClipOrientation.top).padding(.leading, isLeft ? 22 : 0)
                .padding(.trailing, ClipOrientation.inset(isLeft: isLeft)).zIndex(0)
            if wide {
                VStack(spacing: 0) {
                    if let item, item.kind == .image { PhotoBody(store: store, item: item, interaction: { model.interaction($0) }, pull: paperPull, fold: fold, isLeft: isLeft) }
                    else if item?.kind == .link, let exportWebSnapshot {
                        Image(nsImage: exportWebSnapshot).resizable().interpolation(.high).scaledToFit()
                            .clipShape(SoftSheetMask())
                            .overlay(SheetLighting(pull: .resting, isLeft: false))
                            .modifier(PaperFlexEffect(pull: .resting, isLeft: false))
                    }
                    else if let item { ItemBody(store: store, item: item, manager: manager, interaction: { model.interaction($0) }).equatable() }
                    else { GroupBody(store: store, groupID: model.id, manager: manager, interaction: { model.interaction($0) }).equatable() }
                }
                .padding(.top, housing == .folder || housing == .collection ? 22 : 0)
                .environment(\.manuscriptMotion, ManuscriptMotion(pull: dragPull, fold: fold, isLeft: isLeft, disabled: motionDisabled,
                                                               turnActivity: { model.documentTurn($0) }))
                .modifier(PinnedObjectFinish(form: .forItem(item), id: model.id, preferences: store.state.preferences,
                                             pull: paperPull, fold: fold, isLeft: isLeft, housing: housing, physical: physical,
                                             opening: folderProgress, layers: layers, dragPull: dragPull, title: item?.kind == .folder ? "" : title))
                .overlay { GripContact(material: physical, isLeft: isLeft, depth: ClipOrientation.contactY - materialTop) }

                .shadow(color: .black.opacity(0.18), radius: 1.8, x: isLeft ? 1 : -1, y: 2)
                .shadow(color: .black.opacity(0.24), radius: 8 + abs(paperPull.y) * 5, x: isLeft ? 2 : -2, y: 7 + abs(paperPull.y) * 5)
                .environment(\.colorScheme, .light)
                .padding(.top, materialTop).padding(.bottom, 9)
                .padding(.leading, isLeft ? 15 : 9).padding(.trailing, isLeft ? 9 : 15)
                .modifier(MaterialMovement(material: physical, pull: dragPull, isLeft: isLeft, disabled: motionDisabled, tracking: model.moving && !model.dragResting))
                .animation(reduceMotion ? nil : .spring(response: 0.52, dampingFraction: 0.73), value: fold)
                .overlay(alignment: liftsRightCorner ? .bottomTrailing : .bottomLeading) {
                    if canLiftCorner && !motionDisabled {
                        // Leave the document's page-navigation buttons unobstructed.
                        foldGrip.offset(y: PinnedContentForm.forItem(item) == .documentPrint ? -34 : 0)
                    }
                }
                .overlay(alignment: isLeft ? .bottomTrailing : .bottomLeading) {
                    if hovering {
                        Button { model.close() } label: { Image(systemName: "chevron.compact.right").rotationEffect(.degrees(isLeft ? 180 : 0)).font(.system(size: 15)).padding(10) }
                            .buttonStyle(.plain).foregroundStyle(.gray).help("收回边缘")
                            .padding(isLeft ? .trailing : .leading, 43)
                    }
                }
                .overlay(alignment: isLeft ? .bottomLeading : .bottomTrailing) {
                    if hovering && placement.mode == .floating {
                        Image(systemName: "line.3.horizontal.decrease").font(.system(size: 10)).foregroundStyle(.gray).frame(width: 22, height: 22)
                            .overlay(MoveHandle(begin: { resizeOriginal = model.panel.frame.size; model.interaction(true) }, move: { delta in if let original = resizeOriginal { manager.resize(model.id, delta: delta, original: original) } }, end: { resizeOriginal = nil; model.interaction(false); store.save() }))
                    }
                }
                .zIndex(1)
            } else {
                CompactClipView(store: store, id: model.id, isLeft: isLeft, open: { model.show() }, interaction: { model.interaction($0) })
                    .zIndex(1)
            }
            moveGrip.modifier(clipPose)
                .padding(.top, ClipOrientation.top).padding(.leading, isLeft ? 22 : 0)
                .padding(.trailing, ClipOrientation.inset(isLeft: isLeft)).zIndex(3)
        }
        .frame(width: model.sheetSize.width > 0 ? model.sheetSize.width : nil,
               height: model.sheetSize.height > 0 ? model.sheetSize.height : nil,
               alignment: isLeft ? .topLeading : .topTrailing)
        // One rotation owns the paper, front jaw, rear jaw and native move handle.
        .modifier(HingeSheetEffect(progress: hingeProgress, isLeft: isLeft))
        .modifier(HingeAssemblyEffect(progress: hingeProgress, isLeft: isLeft))
        .overlay(alignment: isLeft ? .topLeading : .topTrailing) {
            if showsNail && placement.mode == .docked && !model.moving {
                SuspensionNail().padding(.top, ClipOrientation.compactHookY - 3).padding(isLeft ? .leading : .trailing, ClipOrientation.edgeAnchor - 3)
            }
        }
        .contentShape(Rectangle())
        .background(GeometryReader { geometry in
            Color.clear.onAppear { surfaceSize = geometry.size }
                .onChange(of: geometry.size) { _, size in surfaceSize = size }
        }.allowsHitTesting(false))
        .overlay(alignment: isLeft ? .topLeading : .topTrailing) {
            LibraryDropZone(destination: model.id, store: store, highlighted: { grouping = $0; model.interaction($0) }, click: { model.show() },
                            beginMove: { model.beginMove() }, move: { model.move($0) }, endMove: { model.endMove() })
                .frame(width: 26, height: 34).padding(.top, ClipOrientation.top)
                .padding(isLeft ? .leading : .trailing, ClipOrientation.edgeAnchor - 13)
        }
        .overlay(alignment: .top) {
            if model.mergeReady {
                Text("松手夹成一组").font(.system(size: 10, weight: .medium)).padding(7)
                    .background(ClipStyle.accent, in: Capsule()).foregroundStyle(.white).padding(.top, wide ? 8 : 16).allowsHitTesting(false)
            }
        }
        .contextMenu { actions }
        .onHover { hovering = $0; model.hover($0) }
        .onContinuousHover { phase in
            switch phase {
            case .active(let point):
                if wide, !model.busy, !model.moving, !motionDisabled {
                    hoverPull = SoftSheetGeometry.hover(at: point, previous: previousHover, size: surfaceSize, isLeft: isLeft)
                    hoverReset?.cancel()
                    hoverReset = Task { @MainActor in
                        do { try await Task.sleep(nanoseconds: 90_000_000) } catch { return }
                        hoverPull = .resting
                    }
                }
                previousHover = point
            case .ended: hoverReset?.cancel(); previousHover = nil; hoverPull = .resting
            }
        }
        .help(title)
        .task(id: wide) {
            guard wide, !motionDisabled else { settling = 0; return }
            settling = 0.25
            do { try await Task.sleep(nanoseconds: 70_000_000) } catch { return }
            settling = 0
        }
        .onAppear { if let item, item.kind == .image { store.loadThumbnail(item) } }
        .onDisappear { hoverReset?.cancel() }
        .tint(ClipStyle.accent)
        .padding(.top, model.pageTurnInset)
        .padding(.horizontal, model.pageTurnSideInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: isLeft ? .topLeading : .topTrailing)
    }
    @ViewBuilder var actions: some View {
        Button("编辑名称与备注") { manager.edit(model.id) }
        if let item {
            Menu("夹入材料组") {
                ForEach(store.state.groups.filter { $0.id != item.groupID }) { group in
                    Button(group.title) { _ = store.combine(item.id, with: group.id) }
                }
                Button("建立新的材料组") { store.createGroup([item.id], title: "材料夹 · " + String(item.title.prefix(20))) }
            }
        }
        if let item {
            Button("打开") { store.open(item) }.disabled(item.kind == .text)
            Button("复制") { store.copy(item) }
            if let url = store.fileURL(item) {
                Button("在 Finder 中显示") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                Button("复制路径") { store.copyPath(item) }
                Button("快速预览") { PreviewController.shared.show(url) }
            }
            if item.bookmark != nil { Button("重新关联位置…") { store.relink(item) } }
            if item.groupID != nil { Button("移出项目组") { store.update(item.id) { $0.groupID = nil } } }
            Button("上移") { store.reorder(item.id, by: -1) }
            Button("下移") { store.reorder(item.id, by: 1) }
            Divider()
            Button("取消固定") { store.remove(item.id) }
        } else { Button("解散项目组（保留成员）") { store.dissolve(model.id) } }
    }
}

struct PhotoBody: View {
    @ObservedObject var store: ClipStore
    let item: ClipItem
    var interaction: (Bool) -> Void
    var pull = PaperPull.resting
    var fold: CGFloat = 0
    var isLeft = false
    var body: some View {
        Group {
            if let image = store.images[item.id] {
                SoftImageSurface(image: image, pull: pull, isLeft: isLeft)
                    .aspectRatio(image.size, contentMode: .fit)
                    .modifier(PhotoFinish(cutout: item.imageIsCutout == true, pull: pull, isLeft: isLeft))
                    .overlay(ContentDragHandle(item: item, store: store, interaction: interaction, showLabel: false))
                    .help("轻点复制，拖动照片交给其他应用；右键查看更多操作")
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "photo").font(.system(size: 30, weight: .light))
                    Text(store.status(item) ?? "正在显影…").font(.system(size: 11))
                }.frame(maxWidth: .infinity, maxHeight: .infinity).background { QuietPaper() }
            }
        }.frame(maxWidth: .infinity, alignment: .top)
    }
}

struct ItemBody: View, Equatable {
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.item == rhs.item && lhs.store === rhs.store && lhs.manager === rhs.manager }
    @ObservedObject var store: ClipStore
    let item: ClipItem
    let manager: WindowManager
    var interaction: (Bool) -> Void = { _ in }
    var body: some View {
        Group {
            if item.kind == .folder {
                FolderBody(store: store, item: item, interaction: interaction)
                    .padding(.horizontal, 12).padding(.top, 12).padding(.bottom, 20)
            } else if item.kind == .image {
                PhotoBody(store: store, item: item, interaction: interaction)
            } else {
                MinimalPinnedContent(store: store, item: item, interaction: interaction)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct GroupBody: View, Equatable {
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.groupID == rhs.groupID && lhs.store === rhs.store && lhs.manager === rhs.manager }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var store: ClipStore
    let groupID: UUID
    let manager: WindowManager
    var interaction: (Bool) -> Void
    @State private var selected: UUID?
    var body: some View {
        VStack(spacing: 0) {
            if let selected, let item = store.item(selected), item.removedAt == nil, item.groupID == groupID, store.visibleInScene(item.id) {
                HStack { Button("返回项目夹", systemImage: "chevron.left") { self.selected = nil }; Spacer(); Button("拉出常驻") { manager.float(item.id) } }.controlSize(.small).padding(10)
                ItemBody(store: store, item: item, manager: manager, interaction: interaction)
            } else {
                ScrollView {
                    VStack(spacing: 7) {
                        ForEach(store.sceneMembers(groupID)) { item in
                            HStack(spacing: 10) {
                                HStack(spacing: 10) {
                                    Group {
                                        if let image = store.images[item.id], [.image, .file].contains(item.kind) {
                                            Image(nsImage: image).resizable().scaledToFill().frame(width: 28, height: 28).clipped().modifier(PhotoFinish())
                                        } else { ClipIcon(item: item) }
                                    }.onAppear { store.loadThumbnail(item) }
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(item.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                                        Text(item.note.isEmpty ? item.kind.title : item.note).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                                    }.frame(maxWidth: .infinity, alignment: .leading)
                                }.overlay(ContentDragHandle(item: item, store: store, interaction: interaction, showLabel: false))
                                    .help("单击复制 · 拖出复制")
                                Button { selected = item.id } label: { Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(.secondary) }
                                    .buttonStyle(.plain).help("查看内容")
                                Menu {
                                    Button("拉出常驻（保留分组）") { manager.float(item.id) }
                                    Button("从组中抽出") { store.extract(item.id) }
                                    Button("上移") { store.reorder(item.id, by: -1) }
                                    Button("下移") { store.reorder(item.id, by: 1) }
                                } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                            }.padding(10).background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 7))
                                .transition(.modifier(active: HingeSheetEffect(progress: 0, isLeft: true), identity: HingeSheetEffect(progress: 1, isLeft: true)))
                        }
                        if store.sceneMembers(groupID).isEmpty { Text("项目夹里还没有内容。\n在全部夹项中选择内容加入。 ").foregroundStyle(.secondary).padding(20) }
                    }.padding(12).animation(reduceMotion || store.state.preferences.motionIntensity == 0 ? nil : .spring(response: HingeReveal.duration, dampingFraction: 0.72), value: store.sceneMembers(groupID).map(\.id))
                }
            }
        }.frame(maxHeight: .infinity)
    }
}
