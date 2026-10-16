import SwiftUI
import ClampCore

enum GuideStage: Int, CaseIterable {
    case aim, grasp, hang, unfold, copy, take
    var title: String {
        switch self {
        case .aim: return "靠近，先瞄准"
        case .grasp: return "合拢，夹住内容"
        case .hang: return "靠边，挂在钉子上"
        case .unfold: return "悬停，翻开查看"
        case .copy: return "点内容，复制原件"
        case .take: return "拖出内容，交给其他应用"
        }
    }
    var duration: Double {
        switch self { case .aim: return 1.2; case .grasp: return 0.8; case .hang: return 1; case .unfold: return 1.5; case .copy: return 1.2; case .take: return 1.5 }
    }
}

/// One cancellable clock owns the tour. Navigation and pause never leave an old
/// delayed step running, and completion holds the final example on screen.
@MainActor final class GuidePlayback: ObservableObject {
    static let kinds: [PreviewSizeKind] = [.text, .photo, .pdf, .document, .webpage, .code, .folder, .collection, .audio, .video, .archive, .file]
    @Published private(set) var index = 0
    @Published private(set) var stage: GuideStage = .aim
    @Published private(set) var playing = false
    @Published private(set) var finished = false
    private var clock: Task<Void, Never>?
    private var generation = 0
    var kind: PreviewSizeKind { Self.kinds[index] }
    var progress: Double { finished ? 1 : (Double(index * GuideStage.allCases.count + stage.rawValue) / Double(Self.kinds.count * GuideStage.allCases.count)) }
    func play() {
        guard !playing else { return }
        if finished { index = 0; stage = .aim; finished = false }
        playing = true; schedule()
    }
    func pause() { playing = false; cancelClock() }
    func select(_ index: Int) {
        guard Self.kinds.indices.contains(index) else { return }
        cancelClock(); self.index = index; stage = .aim; finished = false
        if playing { schedule() }
    }
    func previous() { select(max(0, index - 1)) }
    func next() { if index == Self.kinds.count - 1 { complete() } else { select(index + 1) } }
    func replay() { let resume = playing; select(index); if !resume { play() } }
    func advance() {
        guard !finished else { return }
        if let next = GuideStage(rawValue: stage.rawValue + 1) { stage = next }
        else if index + 1 < Self.kinds.count { index += 1; stage = .aim }
        else { complete() }
    }
    private func complete() { finished = true; pause() }
    private func schedule() {
        cancelClock(); let token = generation
        clock = Task { @MainActor [weak self] in
            while let self, self.playing, self.generation == token {
                let delay = self.stage.duration
                do { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) } catch { return }
                guard !Task.isCancelled, self.generation == token, self.playing else { return }
                self.advance()
            }
        }
    }
    private func cancelClock() { generation += 1; clock?.cancel(); clock = nil }
}
