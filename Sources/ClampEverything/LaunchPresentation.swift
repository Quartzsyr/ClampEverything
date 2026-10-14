import AppKit
import SwiftUI

/// A paper tag turns out from the screen-edge jaw, then folds back into it.
/// Its panel never becomes key and releases its hosting view after completion.
@MainActor final class LaunchPresentation: ObservableObject {
    @Published var progress: CGFloat = 0
    @Published var jawOpening: Double = 0.75
    private(set) var panel: FloatingPanel?
    private var playback: Task<Void, Never>?

    func play(enabled: Bool, completion: @escaping @MainActor () -> Void) {
        cancel()
        guard enabled, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
              let screen = NSScreen.main else { completion(); return }
        progress = 0; jawOpening = 0.75
        let size = CGSize(width: 300, height: 192)
        let height = HingeReveal.swingHeight(size: size, isLeft: false)
        let panel = FloatingPanel()
        panel.ignoresMouseEvents = true
        panel.animationBehavior = .none
        panel.contentView = NSHostingView(rootView: LaunchTag(presentation: self, size: size))
        panel.setFrame(NSRect(x: screen.frame.maxX - size.width,
                              y: screen.visibleFrame.maxY - 72 - height,
                              width: size.width, height: height), display: true)
        self.panel = panel
        panel.orderFrontRegardless()
        playback = Task { @MainActor [weak self] in
            do {
                // Let the folded first frame reach the window before starting.
                try await Task.sleep(nanoseconds: 32_000_000)
                guard let self else { return }
                withAnimation(.spring(response: HingeReveal.duration, dampingFraction: 0.72)) {
                    self.progress = 1
                    self.jawOpening = 0.12
                }
                try await Task.sleep(nanoseconds: 1_550_000_000)
                withAnimation(.easeInOut(duration: HingeReveal.closeDuration)) { self.progress = 0 }
                try await Task.sleep(nanoseconds: 300_000_000)
                self.cancel()
                completion()
            } catch { /* Cancellation also removes the panel. */ }
        }
    }

    func cancel() {
        playback?.cancel(); playback = nil
        panel?.orderOut(nil); panel?.contentView = nil; panel = nil
    }
}

private struct LaunchTag: View {
    @ObservedObject var presentation: LaunchPresentation
    let size: CGSize
    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 12) {
                Text("CLAMP EVERYTHING")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(2)
                    .foregroundStyle(.secondary)
                Text("屏幕夹子").font(.system(size: 30, weight: .medium, design: .serif))
                Rectangle().fill(Color.brown.opacity(0.22)).frame(height: 1)
                Text("夹住手边的万物").font(.system(size: 13)).foregroundStyle(.secondary)
            }
            .padding(26).padding(.top, 10)
            .frame(width: size.width - 24, height: size.height - 18, alignment: .leading)
            .background {
                Image(nsImage: GeneratedAssets.image("paper-natural")).resizable()
            }
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .shadow(color: .black.opacity(0.22), radius: 8, x: -2, y: 6)
            .padding(.top, 9).padding(.leading, 9).padding(.trailing, 15).padding(.bottom, 9)
            .modifier(HingeSheetEffect(progress: presentation.progress, isLeft: false))
            MetalClip(openness: presentation.jawOpening).padding(.top, 12).padding(.trailing, 10)
        }
        .frame(width: size.width, height: size.height, alignment: .topTrailing)
        .modifier(HingeAssemblyEffect(progress: presentation.progress, isLeft: false))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .environment(\.colorScheme, .light)
        .accessibilityLabel("屏幕夹子，夹住手边的万物")
    }
}
