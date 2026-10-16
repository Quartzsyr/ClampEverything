import AppKit
import SwiftUI
import ClampCore

struct ClipGuideView: View {
    @ObservedObject var playback: GuidePlayback
    @ObservedObject var examples: GuideExamples
    var preferences = AppPreferences()
    var close: () -> Void = {}
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    static let size = CGSize(width: 780, height: 560)
    var motionDisabled: Bool { reduceMotion || preferences.motionIntensity == 0 }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("把万物，夹在手边").font(.system(size: 24, weight: .medium))
                    Text("跟着示例看一遍，也可以暂停慢慢看。").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: close) { Image(systemName: "xmark").frame(width: 28, height: 28).background(.black.opacity(0.05), in: Circle()) }
                    .buttonStyle(.plain).help("结束引导").keyboardShortcut(.cancelAction)
            }
            ScrollViewReader { reader in
                ScrollView(.horizontal) {
                    HStack(spacing: 7) {
                        ForEach(Array(GuidePlayback.kinds.enumerated()), id: \.element) { index, kind in
                            Button { playback.select(index) } label: {
                                Text(shortTitle(kind)).font(.system(size: 11, weight: playback.kind == kind ? .semibold : .regular))
                                    .padding(.horizontal, 11).padding(.vertical, 8)
                                    .foregroundStyle(playback.kind == kind ? Color.white : Color.primary.opacity(0.7))
                                    .background(playback.kind == kind ? ClipStyle.accent : Color.black.opacity(0.04), in: Capsule())
                            }.buttonStyle(.plain).id(kind).accessibilityLabel(kind.title + "示例")
                        }
                    }
                }.scrollIndicators(.hidden)
                    .onChange(of: playback.kind, initial: true) { _, kind in
                        withAnimation(motionDisabled ? nil : .easeInOut(duration: 0.25)) { reader.scrollTo(kind, anchor: .center) }
                    }
            }
            HStack(spacing: 22) {
                GuideScene(kind: playback.kind, stage: playback.stage, examples: examples, preferences: preferences, motionDisabled: motionDisabled)
                    .id(playback.kind).frame(width: 460, height: 332)
                VStack(alignment: .leading, spacing: 13) {
                    Text(String(format: "%02d / %02d", playback.index + 1, GuidePlayback.kinds.count))
                        .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                    Text(playback.kind.title).font(.system(size: 21, weight: .medium))
                    Text(GuideExamples.explanation(playback.kind)).font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(5)
                        .fixedSize(horizontal: false, vertical: true)
                    Divider().padding(.vertical, 3)
                    Text(playback.finished ? "万物都认识了" : playback.stage.title).font(.system(size: 14, weight: .medium)).foregroundStyle(ClipStyle.accent)
                    Text(instruction).font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    if playback.finished { Button("开始使用", action: close).buttonStyle(.borderedProminent).controlSize(.small) }
                }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(.top, 12)
            }
            ProgressView(value: playback.progress).tint(ClipStyle.accent)
            HStack(spacing: 15) {
                Button { playback.previous() } label: { Label("上一类", systemImage: "chevron.left") }.disabled(playback.index == 0)
                Button { playback.playing ? playback.pause() : playback.play() } label: {
                    Label(playback.finished ? "再看一遍" : (playback.playing ? "暂停" : "继续"), systemImage: playback.playing ? "pause.fill" : "play.fill")
                }.keyboardShortcut(.space, modifiers: [])
                Button { playback.replay() } label: { Label("重播本例", systemImage: "arrow.counterclockwise") }
                Spacer()
                Button(playback.index == GuidePlayback.kinds.count - 1 ? "完成" : "下一类") { playback.next() }
                Button("结束引导", action: close)
            }.buttonStyle(.plain).font(.system(size: 12))
        }.padding(26).frame(width: Self.size.width, height: Self.size.height)
            .background(Color(red: 0.95, green: 0.95, blue: 0.92), in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.65), lineWidth: 1))
            .environment(\.colorScheme, .light).tint(ClipStyle.accent)
    }
    private func shortTitle(_ kind: PreviewSizeKind) -> String {
        switch kind { case .document: return "Word"; case .webpage: return "网页"; case .collection: return "收纳夹"; default: return kind.title }
    }
    private var instruction: String {
        if playback.finished { return "设置 → 内容大小，可以分别调整各类型的展开尺寸。随时从菜单重新打开引导。" }
        switch playback.stage {
        case .aim: return "将内容拖向接收夹；文字、图片也可以在设置中启用鼠标夹取。"
        case .grasp: return "松开后夹住内容。示例只在这里演示，不会加入你的资料库。"
        case .hang: return "拖动金属夹移动位置，靠近屏幕边缘松手，留下小缩略图。"
        case .unfold: return "停稳后展开，夹子和内容一起翻转；文稿可滚轮翻页，网页可上下滚动。"
        case .copy: return "直接点照片、文字、文稿预览或文件夹主体，即可复制。"
        case .take: return "拖出内容进行复制，原夹项继续保留；右键可打开或快速预览。"
        }
    }
}

struct GuideScene: View {
    let kind: PreviewSizeKind
    let stage: GuideStage
    let examples: GuideExamples
    let preferences: AppPreferences
    var motionDisabled = false
    @State private var location: CGFloat = 0
    @State private var hinge: CGFloat = 1
    @State private var jaw: Double = 1
    @State private var clipOffset = CGSize(width: 30, height: -18)
    @State private var delivery: CGFloat = 0
    @State private var highlight: CGFloat = 0
    var size: CGSize {
        switch kind {
        case .pdf, .document: return CGSize(width: 180, height: 261)
        case .photo: return CGSize(width: 264, height: 203)
        case .webpage: return CGSize(width: 264, height: 203)
        case .folder, .collection: return CGSize(width: 264, height: 261)
        case .audio: return CGSize(width: 264, height: 204)
        case .video: return CGSize(width: 264, height: 193)
        case .archive: return CGSize(width: 244, height: 191)
        default: return CGSize(width: 264, height: 243)
        }
    }
    var pocket: Bool { kind == .folder || kind == .collection }
    var top: CGFloat { ClipOrientation.materialTop(housing: pocket ? .folder : .note, height: size.height) }
    var body: some View {
        GeometryReader { geometry in
            let sourceX: CGFloat = size.width / 2 + 18
            let targetX = geometry.size.width - size.width / 2 - 32
            let centerX = sourceX + (targetX - sourceX) * location
            let centerY: CGFloat = 145
            let originY = centerY - size.height / 2
            ZStack {
                Path { path in path.move(to: CGPoint(x: 430, y: 16)); path.addLine(to: CGPoint(x: 430, y: 294)) }
                    .stroke(.black.opacity(0.10), style: StrokeStyle(lineWidth: 1, dash: [3, 5]))
                Text("屏幕边缘").font(.system(size: 9)).foregroundStyle(.secondary).position(x: 421, y: 310)
                if stage.rawValue >= GuideStage.hang.rawValue {
                    SuspensionNail().position(x: targetX + size.width / 2 - ClipOrientation.edgeAnchor, y: originY + ClipOrientation.compactHookY)
                }
                assembly
                    .modifier(HingeSheetEffect(progress: hinge, isLeft: false))
                    .opacity(stage == .hang && !motionDisabled ? 0 : 1)
                    .position(x: centerX, y: centerY)
                if stage == .hang && !motionDisabled {
                    compact.position(x: targetX + size.width / 2 - ClipOrientation.edgeAnchor + 12, y: originY + 30)
                }
                if stage == .copy {
                    Label("已复制", systemImage: "checkmark.circle.fill").font(.system(size: 12, weight: .medium))
                        .foregroundStyle(ClipStyle.accent).padding(8).background(.white.opacity(0.9), in: Capsule())
                        .position(x: centerX, y: min(290, centerY + size.height / 2 + 15))
                }
                if stage == .take {
                    Image(systemName: "folder.fill").font(.system(size: 38)).foregroundStyle(.blue.opacity(0.65))
                        .overlay(alignment: .bottom) { Text("其他应用").font(.system(size: 9)).foregroundStyle(.secondary).offset(y: 17) }
                        .position(x: 43, y: 281)
                    GuideExampleObject(kind: kind, examples: examples, preferences: preferences, snapshotOnly: true)
                        .frame(width: size.width - 24, height: size.height - ClipOrientation.verticalMargins)
                        .scaleEffect(0.42).opacity(1 - delivery * 0.8)
                        .position(x: centerX + (43 - centerX) * delivery, y: centerY + (281 - centerY) * delivery)
                }
                if stage == .aim || stage == .grasp {
                    Image(systemName: "cursorarrow").font(.system(size: 21)).foregroundStyle(.black)
                        .shadow(color: .white, radius: 1)
                        .position(x: centerX + size.width / 2 - 35 + clipOffset.width, y: originY + 50 + clipOffset.height)
                }
            }.allowsHitTesting(false).accessibilityElement(children: .ignore)
                .accessibilityLabel(kind.title + "示例，" + stage.title)
        }
        .clipped()
        .onChange(of: stage, initial: true) { _, value in update(value) }
    }
    var assembly: some View {
        ZStack(alignment: .topTrailing) {
            object.frame(width: size.width - 24, height: size.height - top - 9)
                .overlay { if stage == .aim || stage == .copy { Rectangle().stroke(ClipStyle.accent.opacity(highlight * 0.8), lineWidth: 2).shadow(color: ClipStyle.accent.opacity(highlight * 0.6), radius: 7) } }
                .shadow(color: .black.opacity(0.20), radius: 7, x: -1, y: 6)
                .padding(.top, top).padding(.leading, 9).padding(.trailing, 15).padding(.bottom, 9)
            HangingMetalClip(openness: jaw).modifier(SuspendedClipScale(scale: ClipOrientation.displayScale))
                .offset(clipOffset).padding(.top, ClipOrientation.top).padding(.trailing, ClipOrientation.inset(isLeft: false))
        }.frame(width: size.width, height: size.height)
    }
    var compact: some View {
        ZStack(alignment: .topTrailing) {
            GuideExampleObject(kind: kind, examples: examples, preferences: preferences, snapshotOnly: true)
                .frame(width: 240, height: 180).scaleEffect(0.125).frame(width: 30, height: 22.5)
                .position(x: 20, y: 55)
            HangingMetalClip(openness: 0.12).modifier(SuspendedClipScale(scale: ClipOrientation.displayScale))
                .padding(.top, ClipOrientation.top).padding(.trailing, ClipOrientation.inset(isLeft: false))
        }.frame(width: 64, height: 60).modifier(HingeSheetEffect(progress: 0, isLeft: false))
    }
    var object: some View { GuideExampleObject(kind: kind, examples: examples, preferences: preferences) }
    private func update(_ value: GuideStage) {
        let animation: Animation? = motionDisabled ? nil : .spring(response: 0.65, dampingFraction: 0.78)
        withAnimation(animation) {
            location = value.rawValue >= GuideStage.hang.rawValue ? 1 : 0
            hinge = value == .hang && !motionDisabled ? 0.08 : 1
            jaw = value == .aim ? 1 : 0.12
            clipOffset = value == .aim ? CGSize(width: 20, height: -12) : .zero
            highlight = value == .aim || value == .copy ? 1 : 0
            delivery = 0
        }
        if value == .take { withAnimation(motionDisabled ? nil : .easeInOut(duration: 1.1)) { delivery = 1 } }
    }
}

struct GuideExampleObject: View {
    let kind: PreviewSizeKind
    let examples: GuideExamples
    let preferences: AppPreferences
    var snapshotOnly = false
    @ViewBuilder var body: some View {
        if [.text, .pdf, .document, .webpage, .code, .file].contains(kind) {
            object.modifier(ManuscriptPaper(seed: UInt64(GuidePlayback.kinds.firstIndex(of: kind) ?? 0) + 31,
                boundLeft: kind == .pdf || kind == .document))
        } else { object }
    }
    @ViewBuilder var object: some View {
        switch kind {
        case .text:
            Text(GuideExamples.note).font(.system(size: 14)).lineSpacing(6).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(17).background { QuietPaper(stock: preferences.noteStock) }
        case .photo:
            Image(nsImage: examples.photo).resizable().scaledToFill().clipped().modifier(PhotoFinish())
        case .pdf, .document:
            if let image = kind == .pdf ? examples.pdf : examples.document { Image(nsImage: image).resizable().scaledToFit() }
        case .webpage:
            if snapshotOnly {
                if let image = examples.webPage.image { Image(nsImage: image).resizable().scaledToFit() }
                else { QuietPaper().overlay(Text("田野手记").font(.system(size: 12))) }
            } else { GuideWebExample(page: examples.webPage) }
        case .code:
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(GuideExamples.code.components(separatedBy: "\n").enumerated()), id: \.offset) { number, line in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("\(number + 1)").foregroundStyle(.gray.opacity(0.6)).frame(width: 14, alignment: .trailing)
                        Text(CodeColoring.highlight(line)).frame(maxWidth: .infinity, alignment: .leading)
                    }.font(.system(size: 10, design: .monospaced))
                }
            }.padding(13).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).background { QuietPaper() }
        case .folder, .collection:
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(GuideExamples.filename(kind)).font(.system(size: 12, weight: .medium))
                    Spacer()
                    Text("3 项").font(.system(size: 9)).foregroundStyle(.secondary)
                }
                Label("旅行手记.pdf", systemImage: "doc.richtext")
                Label("山间湖泊.png", systemImage: "photo")
                Label(kind == .collection ? "周末的小计划" : "出行计划.docx", systemImage: "doc.text")
            }.font(.system(size: 12)).padding(18).padding(.top, 28)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background { FolderMaterial(tint: preferences.folderTint, layers: kind == .collection ? 3 : 1) }
        case .audio: MinimalMediaObject(form: .cassette, title: GuideExamples.filename(kind))
        case .video: MinimalMediaObject(form: .filmStrip, title: GuideExamples.filename(kind), image: examples.photo)
        case .archive: MinimalMediaObject(form: .parcel, title: GuideExamples.filename(kind))
        case .file:
            VStack(spacing: 12) {
                Image(systemName: "doc.fill").font(.system(size: 42)).foregroundStyle(.gray.opacity(0.6))
                Text(GuideExamples.filename(kind)).font(.system(size: 12, weight: .medium))
                Text("相机的自定义配置\n保留原文件引用").font(.system(size: 10)).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }.frame(maxWidth: .infinity, maxHeight: .infinity).background { QuietPaper() }
        }
    }
}

private struct GuideWebExample: View {
    @ObservedObject var page: WebPagePreviewModel
    var body: some View {
        ZStack {
            if let image = page.image { Image(nsImage: image).resizable().scaledToFit() }
            else {
                WebPageSnapshotView(model: page, url: URL(string: "https://guide.clamp.invalid/")!, html: GuideExamples.html)
                if page.failed { Text("田野手记\n把日常的风景，留在手边。").padding().background { QuietPaper() } }
            }
        }.onDisappear { page.cancel() }
    }
}
