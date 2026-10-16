import AppKit
import SwiftUI
import ClampCore

/// A bounded visual lift of the readable object; the source application is never moved.
enum CursorPickupGeometry {
    static func source(bounds: CGRect?, regions: [CGRect], click: CGPoint, screen: CGRect, desktopTop: CGFloat) -> CGRect {
        let readable = regions.isEmpty ? bounds : regions.prefix(24).reduce(CGRect.null) { $0.union($1) }
        let fallback = CGRect(x: click.x - 42, y: click.y - 24, width: 84, height: 48)
        guard let readable, readable.minX.isFinite, readable.minY.isFinite,
              readable.width.isFinite, readable.height.isFinite, readable.width > 1, readable.height > 1 else { return fallback }
        let cocoa = CGRect(x: readable.minX, y: desktopTop - readable.maxY, width: readable.width, height: readable.height)
        let visible = cocoa.intersection(screen)
        guard !visible.isNull, visible.width > 1, visible.height > 1 else { return fallback }
        // A text area may report an entire editor. Lift a local excerpt rather than the whole window.
        let size = CGSize(width: min(260, visible.width), height: min(160, visible.height))
        return CGRect(x: max(visible.minX, min(click.x - size.width / 2, visible.maxX - size.width)),
                      y: max(visible.minY, min(click.y - size.height / 2, visible.maxY - size.height)),
                      width: size.width, height: size.height)
    }
    static func heldFrame(at jaw: CGPoint) -> CGRect {
        CGRect(x: jaw.x - 12, y: jaw.y - 28, width: 22, height: 28)
    }
    static func ease(_ value: Double) -> Double {
        let p = min(1, max(0, value)); return p * p * (3 - 2 * p)
    }
    static func sample(progress: Double, source: CGRect, jaw: CGPoint, material: PhysicalMaterial) -> CursorPickupSample {
        let p = min(1, max(0, progress)), travel = ease((p - 0.28) / 0.58)
        let liftProgress = ease((p - 0.10) / 0.76)
        let lift = liftProgress > 0 && liftProgress < 1 ? sin(.pi * liftProgress) : 0
        let flutter = travel > 0 && travel < 1 ? sin(.pi * travel) : 0
        let pressure = sin(.pi * min(1, p / 0.28)) * (1 - travel)
        let settling = (p - 0.78) / 0.22
        let recoil = settling > 0 && settling < 1 ? -sin(settling * .pi * 2) * exp(-settling * 3) * (1 + material.inertia * 2) : 0
        let destination = heldFrame(at: jaw)
        func mix(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * travel }
        let frame = CGRect(x: mix(source.minX, destination.minX),
                           y: mix(source.minY, destination.minY) + lift * (8 + 7 * material.flexibility),
                           width: mix(source.width, destination.width), height: mix(source.height, destination.height))
        return CursorPickupSample(frame: frame,
            compression: pressure * (0.025 + material.flexibility * 0.045),
            angle: -6 * travel + flutter * material.flexibility * 7 + recoil,
            bend: flutter * material.flexibility * 12,
            miniature: ease((p - 0.38) / 0.40),
            sourceLight: ease(p / 0.08) * (1 - ease((p - 0.12) / 0.35)) * 0.65,
            shadow: 2 + lift * (3 + material.inertia * 3),
            jaw: 1 - ease((p - 0.48) / 0.40) * (1 - material.jawOpening))
    }
}

struct CursorPickupSample {
    let frame: CGRect
    let compression: Double
    let angle: Double
    let bend: Double
    let miniature: Double
    let sourceLight: Double
    let shadow: Double
    let jaw: Double
}

/// The same task is awaited on a quick release. Cancellation invalidates its completion.
@MainActor final class CursorPickupMotion: ObservableObject {
    @Published private(set) var progress: Double = 0
    @Published private(set) var active = false
    @Published private(set) var destination = CGPoint.zero
    private(set) var source = CGRect.zero
    private(set) var material: PhysicalMaterial = .note
    private var task: Task<Void, Never>?
    private var generation = 0
    var onFrame: () -> Void = {}
    var onFinish: () -> Void = {}
    var duration: Double { 0.44 + material.inertia * 0.16 }
    var sample: CursorPickupSample { CursorPickupGeometry.sample(progress: progress, source: source, jaw: destination, material: material) }
    var panelFrame: CGRect {
        let visible = progress < 0.48 ? source.union(sample.frame) : sample.frame
        return visible.insetBy(dx: -28, dy: -28).integral
    }
    func start(source: CGRect, destination: CGPoint, material: PhysicalMaterial, animated: Bool) {
        cancel()
        self.source = source; self.destination = destination; self.material = material
        progress = animated ? 0 : 1; active = animated
        guard animated else { onFinish(); return }
        let token = generation, start = ProcessInfo.processInfo.systemUptime, duration = duration
        onFrame()
        task = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: 16_000_000) } catch { return }
                guard let self, self.generation == token else { return }
                self.progress = min(1, (ProcessInfo.processInfo.systemUptime - start) / duration)
                self.onFrame()
                if self.progress >= 1 {
                    self.active = false; self.task = nil; self.onFinish(); return
                }
            }
        }
    }
    func move(to point: CGPoint) {
        guard active else { return }
        destination = point; onFrame()
    }
    func finish() async throws {
        let pending = task
        await pending?.value
        try Task.checkCancellation()
    }
    func cancel() {
        generation += 1; task?.cancel(); task = nil; active = false
    }
}

/// Shared by the flying object and the carried object so the handoff has identical pixels and anchor.
struct CursorHeldMaterial: View {
    @ObservedObject var pose: CursorClipPose
    var size = CGSize(width: 22, height: 28)
    private var detailScale: CGFloat { min(size.width / 22, size.height / 28) }
    var body: some View {
        Group {
            if pose.isCutout { Color.clear }
            else if pose.material.isPocket { FolderMaterial(tint: .kraft, opening: 0.6, layers: 2) }
            else if pose.material == .bookmark { BookmarkMaterial() }
            else if pose.material == .note || pose.material == .photo { RoundedRectangle(cornerRadius: 2).fill(Color(red: 0.99, green: 0.97, blue: 0.9)) }
            else { FileMaterial(material: pose.material) }
        }
        .frame(width: size.width, height: size.height)
        .overlay {
            if let preview = pose.preview { Image(nsImage: preview).resizable().scaledToFit().padding(3 * detailScale) }
            else { Text(pose.text).font(.system(size: 5 * detailScale)).foregroundStyle(.black).lineLimit(3).padding(2 * detailScale) }
        }
    }
}

struct CursorPickupView: View {
    @ObservedObject var motion: CursorPickupMotion
    @ObservedObject var pose: CursorClipPose
    var body: some View {
        CursorPickupArtwork(sample: motion.sample, source: motion.source, panel: motion.panelFrame, pose: pose,
                            visibility: CursorPickupGeometry.ease(motion.progress / 0.10))
    }
}

struct CursorPickupArtwork: View {
    let sample: CursorPickupSample
    let source: CGRect
    let panel: CGRect
    @ObservedObject var pose: CursorClipPose
    var visibility: Double = 1
    var body: some View {
        let frame = sample.frame
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: pose.material == .note ? 2 : 6)
                .fill(light.opacity(sample.sourceLight * 0.3))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(light.opacity(sample.sourceLight), lineWidth: 1.4))
                .frame(width: source.width, height: source.height)
                .position(x: source.midX - panel.minX, y: panel.maxY - source.midY)
            ZStack {
                sourceObject.frame(width: frame.width, height: frame.height).opacity(1 - sample.miniature)
                CursorHeldMaterial(pose: pose, size: frame.size)
                    .opacity(sample.miniature)
            }
            .frame(width: frame.width, height: frame.height)
            .scaleEffect(x: 1 + sample.compression * 0.28, y: 1 - sample.compression, anchor: .top)
            .rotation3DEffect(.degrees(sample.bend), axis: (x: 1, y: 0, z: 0), anchor: .top, perspective: 0.3)
            .rotationEffect(.degrees(sample.angle), anchor: UnitPoint(x: 12 / 22.0, y: 0))
            .shadow(color: .black.opacity(0.22), radius: sample.shadow, y: sample.shadow * 0.6)
            .opacity(visibility)
            .position(x: frame.midX - panel.minX, y: panel.maxY - frame.midY)
        }
        .frame(width: panel.width, height: panel.height)
        .allowsHitTesting(false).accessibilityHidden(true)
    }
    private var light: Color { pose.material == .note ? .yellow : (pose.material.isPocket ? .orange : .cyan) }
    @ViewBuilder private var sourceObject: some View {
        if pose.material == .note {
            Text(pose.text).font(.system(size: 13)).foregroundStyle(Color.black.opacity(0.85))
                .padding(5).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(Color(red: 1, green: 0.98, blue: 0.88), in: RoundedRectangle(cornerRadius: 3))
                .clipped()
        } else if let preview = pose.preview {
            Image(nsImage: preview).resizable().scaledToFit()
        } else {
            CursorHeldMaterial(pose: pose).scaleEffect(2)
        }
    }
}
