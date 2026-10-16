import AppKit
import SwiftUI

@MainActor enum ImageSubjectCapture {
    typealias Snapshot = @MainActor (CGRect, CGPoint) async throws -> CGImage
    static func analyze(target: PointTarget, at point: CGPoint, snapshot: @escaping Snapshot = { try await PointCapture.image(in: $0, at: $1) }) async throws -> ImageSubjectSelection? {
        guard let bounds = target.subjectImageBounds, ImageSubjectEligibility.isLarge(bounds), bounds.contains(point),
              let screen = NSScreen.screens.first(where: { $0.frame.contains(PointClampController.cocoaPoint(point)) }) else { return nil }
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        let visible = CGRect(x: screen.frame.minX, y: top - screen.frame.maxY, width: screen.frame.width, height: screen.frame.height)
        let rect = bounds.intersection(visible)
        guard ImageSubjectEligibility.isLarge(rect) else { return nil }
        let image = try await snapshot(rect, point)
        try Task.checkCancellation()
        let normalized = CGPoint(x: (point.x - rect.minX) / rect.width, y: (point.y - rect.minY) / rect.height)
        let worker = Task.detached(priority: .utility) { try ImageSubjectAnalyzer.analyze(image, point: normalized, source: target, rect: rect) }
        return try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
    }
    /// Revalidate at press time. A changed image/window must fall back to a fresh whole-image pickup.
    static func prepare(_ selection: ImageSubjectSelection, at point: CGPoint,
        resolve: @escaping @Sendable (CGPoint) throws -> PointTarget = { try PointCapture.target(at: $0) },
        snapshot: @escaping Snapshot = { try await PointCapture.image(in: $0, at: $1) }
    ) async throws -> PreparedPointTarget? {
        guard selection.contains(point) else { return nil }
        let worker = Task.detached(priority: .userInitiated) { try resolve(point) }
        do {
            let target = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
            try Task.checkCancellation()
            guard sameSource(selection.source, target) else { return nil }
            let fresh = try await snapshot(selection.sourceRect, point)
            try Task.checkCancellation()
            let comparison = Task.detached(priority: .userInitiated) { try ImageSubjectAnalyzer.signature(fresh, sourceRect: selection.sourceRect, focusRect: selection.screenRect) }
            let signature = try await withTaskCancellationHandler { try await comparison.value } onCancel: { comparison.cancel() }
            try Task.checkCancellation()
            guard signature.count == selection.signature.count else { return nil }
            let difference = zip(signature, selection.signature).reduce(0.0) { $0 + Double(abs(Int($1.0) - Int($1.1))) } / Double(signature.count * 255)
            guard difference < 0.018 else { return nil }
            // Reuse the selected silhouette but freeze pixels from the actual press, not the earlier hover.
            let cutout = Task.detached(priority: .userInitiated) {
                try ImageSubjectAnalyzer.compose(fresh, mask: selection.mask, source: target, rect: selection.sourceRect)
            }
            let result = try await withTaskCancellationHandler { try await cutout.value } onCancel: { cutout.cancel() }
            try Task.checkCancellation()
            return result?.prepared()
        } catch is CancellationError { throw CancellationError() }
        catch { return nil }
    }
    static func sameSource(_ a: PointTarget, _ b: PointTarget) -> Bool {
        guard let rect = a.subjectImageBounds, rect == b.subjectImageBounds else { return false }
        switch (a.payload, b.payload) {
        case (.file(let x), .file(let y)): return x == y
        case (.image, .image): return a.title == b.title
        default: return false
        }
    }
}

/// A second, deliberately longer dwell than ordinary aim. Tiny hand tremor does not restart it.
@MainActor final class ImageSubjectAimController {
    typealias Analyzer = @MainActor (PointTarget, CGPoint) async throws -> ImageSubjectSelection?
    private let dwell: UInt64
    private let analyze: Analyzer
    private var target: PointTarget?
    private var anchor: CGPoint?
    private var task: Task<Void, Never>?
    private var generation = 0
    private var attempted = false
    private(set) var selection: ImageSubjectSelection?
    var onSelection: (ImageSubjectSelection?) -> Void = { _ in }
    init(dwell: UInt64 = 1_200_000_000, analyze: @escaping Analyzer = { try await ImageSubjectCapture.analyze(target: $0, at: $1) }) {
        self.dwell = dwell; self.analyze = analyze
    }
    func update(_ candidate: PointTarget?, at point: CGPoint) {
        guard let candidate, let bounds = candidate.subjectImageBounds, ImageSubjectEligibility.isLarge(bounds), bounds.contains(point) else { cancel(); return }
        if let target, ImageSubjectCapture.sameSource(target, candidate) { move(to: point); return }
        cancel(); target = candidate; schedule(at: point)
    }
    func move(to point: CGPoint) {
        guard let target, target.subjectImageBounds?.contains(point) == true else { if target != nil { cancel() }; return }
        if let selection {
            if selection.contains(point) { return }
            // Once highlighted, leaving the silhouette clears immediately, even within tremor tolerance.
        } else if let anchor, hypot(point.x - anchor.x, point.y - anchor.y) <= 6 { return }
        generation += 1; task?.cancel(); task = nil
        selection = nil; onSelection(nil); attempted = false
        schedule(at: point)
    }
    private func schedule(at point: CGPoint) {
        guard let target, !attempted else { return }
        anchor = point; attempted = true
        let token = generation, dwell = dwell, analyze = analyze
        task = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: dwell)
                let selection = try await analyze(target, point)
                try Task.checkCancellation()
                guard let self, self.generation == token else { return }
                self.selection = selection; self.task = nil; self.onSelection(selection)
            } catch {
                guard !Task.isCancelled, let self, self.generation == token else { return }
                self.task = nil; self.selection = nil; self.onSelection(nil)
            }
        }
    }
    func selected(at point: CGPoint) -> ImageSubjectSelection? { selection?.contains(point) == true ? selection : nil }
    func cancel() {
        generation += 1; task?.cancel(); task = nil; target = nil; anchor = nil; attempted = false
        if selection != nil { selection = nil; onSelection(nil) }
    }
}

struct ImageSubjectGlowView: View {
    let selection: ImageSubjectSelection
    var animated: Bool
    @ObservedObject var state = TargetGlowState()
    @State private var visible = false
    var body: some View {
        Image(decorative: selection.highlight, scale: 1).resizable().interpolation(.high)
            .shadow(color: Color(red: 0.35, green: 1, blue: 0.8).opacity(0.9), radius: 4)
            .shadow(color: .white.opacity(0.7), radius: 1)
            .padding(TargetGlowGeometry.padding)
            .opacity(visible ? (state.moving ? 0.65 : 1) : 0)
            .animation(animated ? .easeOut(duration: 0.12) : nil, value: state.moving)
            .onAppear { withAnimation(animated ? .easeOut(duration: 0.18) : nil) { visible = true } }
            .allowsHitTesting(false).accessibilityHidden(true)
    }
}
