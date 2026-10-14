import AppKit
import SwiftUI

/// AX uses top-left screen coordinates; the transparent panel uses AppKit coordinates.
enum TargetGlowGeometry {
    static let padding: CGFloat = 14
    static func frame(rect: CGRect, screen: CGRect, desktopTop: CGFloat) -> CGRect? {
        guard rect.minX.isFinite, rect.minY.isFinite, rect.width.isFinite, rect.height.isFinite,
              rect.width > 1, rect.height > 1 else { return nil }
        let cocoa = CGRect(x: rect.minX, y: desktopTop - rect.maxY, width: rect.width, height: rect.height)
        let clipped = cocoa.intersection(screen)
        guard !clipped.isNull, clipped.width > 1, clipped.height > 1 else { return nil }
        return clipped.insetBy(dx: -padding, dy: -padding)
    }
}

enum TargetGlowStyle: String, CaseIterable {
    case text, image, link, folder, file
    static func forTarget(_ target: PointTarget) -> Self {
        switch target.payload {
        case .text: return .text
        case .image: return .image
        case .link: return .link
        case .file(let url):
            if target.fileKind == .folder || url.hasDirectoryPath { return .folder }
            return target.fileKind == .image ? .image : .file
        }
    }
    var color: Color {
        switch self {
        case .text: return Color(red: 1, green: 0.9, blue: 0.65)
        case .image: return Color(red: 0.45, green: 0.82, blue: 1)
        case .link: return Color(red: 0.4, green: 0.94, blue: 0.76)
        case .folder: return Color(red: 1, green: 0.7, blue: 0.32)
        case .file: return Color(red: 0.73, green: 0.65, blue: 1)
        }
    }
    var radius: CGFloat { self == .text ? 2 : (self == .image ? 3 : 7) }
}

struct TargetGlowLayout: Equatable {
    let frame: CGRect
    /// Local SwiftUI rectangles, with the origin at the panel's upper-left.
    let regions: [CGRect]
    static func make(regions: [CGRect], screen: CGRect, desktopTop: CGFloat) -> Self? {
        let clipped = regions.prefix(24).compactMap { rect -> CGRect? in
            guard let padded = TargetGlowGeometry.frame(rect: rect, screen: screen, desktopTop: desktopTop) else { return nil }
            return padded.insetBy(dx: TargetGlowGeometry.padding, dy: TargetGlowGeometry.padding)
        }
        guard let first = clipped.first else { return nil }
        let frame = clipped.dropFirst().reduce(first) { $0.union($1) }.insetBy(dx: -TargetGlowGeometry.padding, dy: -TargetGlowGeometry.padding)
        return Self(frame: frame, regions: clipped.map { CGRect(x: $0.minX - frame.minX, y: frame.maxY - $0.maxY, width: $0.width, height: $0.height) })
    }
}

@MainActor final class TargetGlowState: ObservableObject {
    @Published var moving = false
}

struct TargetGlowContour: Shape {
    var regions: [CGRect]
    var style: TargetGlowStyle
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let regions = regions.isEmpty ? [rect.insetBy(dx: TargetGlowGeometry.padding, dy: TargetGlowGeometry.padding)] : regions
        for region in regions {
            let r = region.insetBy(dx: -2, dy: -2)
            if style == .link {
                path.move(to: CGPoint(x: r.minX, y: r.maxY)); path.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
            } else if style == .file {
                let length = min(16, min(r.width, r.height) * 0.3)
                for corner in [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY), CGPoint(x: r.minX, y: r.maxY), CGPoint(x: r.maxX, y: r.maxY)] {
                    let dx: CGFloat = corner.x == r.minX ? 1 : -1, dy: CGFloat = corner.y == r.minY ? 1 : -1
                    path.move(to: CGPoint(x: corner.x + dx * length, y: corner.y))
                    path.addLine(to: corner); path.addLine(to: CGPoint(x: corner.x, y: corner.y + dy * length))
                }
            } else {
                path.addRoundedRect(in: r, cornerSize: CGSize(width: style.radius, height: style.radius))
            }
        }
        return path
    }
}

@MainActor struct TargetGlowView: View {
    var animated = true
    var style: TargetGlowStyle = .image
    var regions: [CGRect] = []
    @ObservedObject var state = TargetGlowState()
    @State private var visible = false
    var body: some View {
        let light = LinearGradient(colors: [style.color, .white.opacity(0.9), style.color.opacity(0.75)], startPoint: .topLeading, endPoint: .bottomTrailing)
        ZStack {
            if style == .text {
                TargetGlowContour(regions: regions, style: .text)
                    .fill(Color(red: 1, green: 0.78, blue: 0.18).opacity(state.moving ? 0.22 : 0.46))
                TargetGlowContour(regions: regions, style: .text)
                    .stroke(Color(red: 0.9, green: 0.54, blue: 0.06).opacity(0.65), lineWidth: 1)
            }
            TargetGlowContour(regions: regions, style: style)
                .stroke(light, style: StrokeStyle(lineWidth: style == .link ? 2.8 : (style == .text ? 1.3 : 2), lineCap: .round, lineJoin: .round))
                .shadow(color: style.color.opacity(0.85), radius: style == .text ? 3 : 5)
                .shadow(color: style.color.opacity(0.5), radius: style == .text ? 6 : 10)
        }
            .opacity(visible ? (state.moving ? (style == .text ? 0.75 : 0.42) : 1) : 0)
            .animation(animated ? .easeOut(duration: state.moving ? 0.1 : 0.2) : nil, value: state.moving)
            .onAppear { withAnimation(animated ? .easeOut(duration: 0.18) : nil) { visible = true } }
            .allowsHitTesting(false).accessibilityHidden(true)
    }
}

/// Debounces movement; stale reads cannot light up a previously hovered object.
@MainActor final class TargetAimController {
    typealias Reader = @Sendable (CGPoint) async throws -> PointTarget
    private let read: Reader
    private let dwell: UInt64
    private let hintDelay: UInt64
    private var task: Task<Void, Never>?
    private var point: CGPoint?
    private var generation = 0
    private var lastTarget: PointTarget?
    var onTarget: (PointTarget?) -> Void = { _ in }
    var onHint: (Bool) -> Void = { _ in }
    var onMotion: (Bool) -> Void = { _ in }
    init(dwell: UInt64 = 280_000_000, hintDelay: UInt64 = 420_000_000,
         read: @escaping Reader = { point in
             let worker = Task.detached(priority: .utility) { try PointCapture.target(at: point) }
             return try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
         }) {
        self.dwell = dwell; self.hintDelay = hintDelay; self.read = read
    }
    func update(at point: CGPoint) {
        guard self.point != point else { return }
        generation += 1; task?.cancel(); task = nil
        self.point = point; onHint(false)
        let targetBounds = lastTarget?.bounds ?? lastTarget?.regions.reduce(CGRect.null) { $0.union($1) }
        if targetBounds?.contains(point) == true { onMotion(true) }
        else { lastTarget = nil; onTarget(nil); onMotion(false) }
        let token = generation, read = read, dwell = dwell, hintDelay = hintDelay
        task = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: dwell)
                while !Task.isCancelled {
                    let target = try await read(point)
                    try Task.checkCancellation()
                    guard let self, self.generation == token else { return }
                    self.lastTarget = target
                    self.onTarget(target); self.onMotion(false)
                    try await Task.sleep(nanoseconds: hintDelay)
                    guard self.generation == token else { return }
                    self.onHint(true)
                    // Revalidate a stationary target in case its window or content changes.
                    try await Task.sleep(nanoseconds: 800_000_000)
                }
            } catch {
                guard !Task.isCancelled, let self, self.generation == token else { return }
                self.lastTarget = nil; self.onTarget(nil); self.onHint(false); self.onMotion(false)
            }
        }
    }
    func cancel() {
        generation += 1; task?.cancel(); task = nil; point = nil
        lastTarget = nil; onTarget(nil); onHint(false); onMotion(false)
    }
}
