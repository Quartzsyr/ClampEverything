import AppKit
import SwiftUI
import ClampCore

@MainActor final class DocumentReadingModel: ObservableObject {
    @Published private(set) var image: NSImage?
    @Published private(set) var previous: NSImage?
    @Published private(set) var index = 0
    @Published private(set) var count = 0
    @Published private(set) var loading = false
    @Published private(set) var unavailable = false
    @Published private(set) var turning = false
    @Published private(set) var turn: CGFloat = 0
    private(set) var direction = 1
    private var pages: DocumentPages?
    private var generation = 0
    private var work: Task<Void, Never>?
    private var wheel = PageScrollGate()
    var onPage: (Int) -> Void = { _ in }
    var busy: Bool { loading || turning }
    func load(_ url: URL, initialIndex: Int = 0) async {
        cancel(); let token = generation; image = nil; count = 0; index = 0; loading = true; unavailable = false
        let source = DocumentPages(url: url); pages = source
        do {
            let count = try await source.pageCount()
            let index = max(0, min(count - 1, initialIndex))
            let image = try await source.image(at: index)
            guard generation == token, !Task.isCancelled else { return }
            self.count = count; self.index = index; self.image = image
            loading = false; unavailable = image == nil
        } catch { if generation == token { loading = false; unavailable = true } }
    }
    func scroll(_ event: PreviewScroll, animated: Bool) {
        if let direction = wheel.direction(for: event) { move(direction, animated: animated) }
    }
    func move(_ direction: Int, animated: Bool) {
        let target = index + direction
        guard let pages, !busy, (0..<count).contains(target) else { return }
        let token = generation; loading = true; self.direction = direction
        work = Task { @MainActor [weak self] in
            do {
                let next = try await pages.image(at: target)
                guard let self, self.generation == token, !Task.isCancelled else { return }
                guard let next else { self.loading = false; return }
                self.previous = animated ? self.image : nil
                self.image = next; self.index = target; self.onPage(target); self.loading = false
                guard animated else { return }
                self.turn = 0; self.turning = true
                try await Task.sleep(nanoseconds: 16_000_000)
                guard self.generation == token else { return }
                withAnimation(.easeInOut(duration: 0.48)) { self.turn = 1 }
                try await Task.sleep(nanoseconds: 500_000_000)
                guard self.generation == token else { return }
                self.previous = nil; self.turning = false
            } catch { if let self, self.generation == token { self.loading = false; self.previous = nil; self.turning = false } }
        }
    }
    func cancel() {
        generation += 1; work?.cancel(); work = nil; pages = nil
        previous = nil; turning = false; loading = false; wheel = PageScrollGate()
    }
}

struct DocumentReadingPreview: View {
    @ObservedObject var store: ClipStore
    let item: ClipItem
    var interaction: (Bool) -> Void
    @StateObject private var reader = DocumentReadingModel()
    @State private var hovering = false
    @State private var pressing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.manuscriptMotion) private var motion
    var animated: Bool { !reduceMotion && store.state.preferences.motionIntensity != 0 }
    var body: some View {
        ZStack {
            if let image = reader.image {
                PageTurnPreview(image: image, previous: reader.previous, progress: reader.turn, direction: reader.direction,
                                seed: PaperWearGeometry.seed(item.id), page: reader.index)
            } else { FileThumbnailPreview(store: store, item: item)
                .modifier(ManuscriptPaper(seed: PaperWearGeometry.seed(item.id), boundLeft: true)) }
            if reader.loading && reader.image == nil { ProgressView().controlSize(.small) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(ContentDragHandle(item: item, store: store, interaction: { active in
            pressing = active; interaction(active || reader.busy)
        }, showLabel: false, scroll: { reader.scroll($0, animated: animated) }, stabilizeWhilePressed: true))
        .overlay(alignment: .bottom) {
            if hovering && reader.count > 1 {
                HStack {
                    pageButton("chevron.left", step: -1).disabled(reader.index == 0)
                    Spacer()
                    Text("\(reader.index + 1) / \(reader.count)").font(.system(size: 10, design: .monospaced))
                        .padding(.horizontal, 7).padding(.vertical, 5).background(.regularMaterial, in: Capsule()).allowsHitTesting(false)
                    Spacer()
                    pageButton("chevron.right", step: 1).disabled(reader.index + 1 == reader.count)
                }.padding(5).disabled(reader.busy)
            } else if hovering && reader.unavailable, let url = store.fileURL(item) {
                Button("系统预览") { PreviewController.shared.show(url) }.font(.system(size: 10)).buttonStyle(.bordered).padding(5)
            }
        }
        .onHover { hovering = $0 }
        .help("滚轮 / 触控板翻页 · 两侧页角翻页 · 中间单击复制 · 拖出原文件")
        .task(id: store.fileURL(item)) {
            guard let url = store.fileURL(item) else { return }
            reader.onPage = { store.documentPageIndices[item.id] = $0 }
            await reader.load(url, initialIndex: store.documentPageIndices[item.id] ?? 0)
        }
        .onChange(of: reader.busy) { _, busy in interaction(busy || pressing) }
        .onChange(of: reader.turning) { _, turning in motion.turnActivity(turning) }
        .onDisappear { pressing = false; reader.cancel(); motion.turnActivity(false); interaction(false) }
    }
    private func pageButton(_ symbol: String, step: Int) -> some View {
        Button { reader.move(step, animated: animated) } label: {
            Image(systemName: symbol).font(.system(size: 11, weight: .semibold)).frame(width: 27, height: 29)
                .background(.regularMaterial, in: UnevenRoundedRectangle(topLeadingRadius: step < 0 ? 1 : 9, bottomLeadingRadius: 1,
                    bottomTrailingRadius: 1, topTrailingRadius: step > 0 ? 1 : 9))
        }.buttonStyle(.plain).help(step < 0 ? "上一页" : "下一页")
    }
}

/// Forward lifts the outgoing page toward the viewer from the left binding.
/// Backward lays that lifted sheet down, reversing the physical operation.
struct PageTurnPreview: View, Animatable {
    let image: NSImage
    var previous: NSImage?
    var progress: CGFloat
    var direction: Int
    var seed: UInt64 = 37
    var page: Int = 0
    @Environment(\.manuscriptMotion) private var motion
    var animatableData: CGFloat { get { progress } set { progress = newValue } }
    private var amount: CGFloat { LeftBindingPageGeometry.amount(progress: progress, direction: direction) }
    private var wave: CGFloat { sin(amount * CGFloat.pi) }
    private var oldPage: Int { direction >= 0 ? page - 1 : page + 1 }
    var body: some View {
        ZStack(alignment: .leading) {
            if let previous {
                paper(direction >= 0 ? image : previous, page: direction >= 0 ? page : oldPage)
                paper(direction >= 0 ? previous : image, page: direction >= 0 ? oldPage : page, moving: true)
                    .shadow(color: .black.opacity(0.23 * Double(wave)), radius: 5 + 5 * wave, x: 7 * wave, y: 3 * wave)
                    .opacity(LeftBindingPageGeometry.opacity(amount: amount))
                    .allowsHitTesting(false)
            } else { paper(image, page: page) }
        }
        .overlay(alignment: .leading) {
            LinearGradient(colors: [.black.opacity(previous == nil ? 0.06 : 0.12), .clear], startPoint: .leading, endPoint: .trailing)
                .frame(width: 5).allowsHitTesting(false)
        }
    }
    private func paper(_ image: NSImage, page: Int, moving: Bool = false) -> some View {
        GeometryReader { geometry in
            let outset = moving ? LeftBindingPageGeometry.drawingOutset(height: geometry.size.height) : 0
            let sideOutset = moving ? ceil(geometry.size.width * 0.055 + 2) : 0
            SoftImageSurface(image: image, pull: moving ? PaperPull(x: wave * 0.7, y: wave * 0.6) : .resting, isLeft: true, boundLeft: true, turnAmount: moving ? amount : 0, verticalOutset: outset, horizontalOutset: sideOutset)
            .overlay(LinearGradient(colors: [.black.opacity(moving ? 0.12 * Double(wave) : 0), .clear, .white.opacity(moving ? 0.20 * Double(wave) : 0)], startPoint: .leading, endPoint: .trailing).allowsHitTesting(false))
            .modifier(ManuscriptPaper(seed: seed &+ UInt64(bitPattern: Int64(page)), boundLeft: true,
                pull: motion.disabled ? .resting : motion.pull,
                fold: motion.disabled ? 0 : min(1, motion.fold + (moving ? wave * 0.20 : 0)), clipOnLeft: motion.isLeft, turnAmount: moving ? amount : 0, verticalOutset: outset, horizontalOutset: sideOutset))
            .frame(width: geometry.size.width + sideOutset * 2, height: geometry.size.height + outset * 2)
            .offset(x: -sideOutset, y: -outset)
        }.aspectRatio(image.size, contentMode: .fit)
    }
}
