import AppKit
import Testing
@testable import ClampEverything

@Suite(.serialized) @MainActor struct LaunchPresentationTests {
    @Test func disabledLaunchCompletesWithoutCreatingWindow() {
        let launch = LaunchPresentation()
        var completions = 0
        launch.play(enabled: false) { completions += 1 }
        #expect(completions == 1)
        #expect(launch.panel == nil)
    }

    @Test func cancellingLaunchReleasesWindowAndSuppressesCompletion() async throws {
        _ = NSApplication.shared
        guard NSScreen.main != nil, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        let launch = LaunchPresentation()
        var completed = false
        launch.play(enabled: true) { completed = true }
        let panel = try #require(launch.panel)
        #expect(panel.ignoresMouseEvents)
        #expect(!panel.canBecomeKey)
        launch.cancel()
        try await Task.sleep(nanoseconds: 60_000_000)
        #expect(launch.panel == nil)
        #expect(panel.contentView == nil)
        #expect(!panel.isVisible)
        #expect(!completed)
    }

    @Test func launchFinishesAndRemovesItsPanel() async throws {
        _ = NSApplication.shared
        let launch = LaunchPresentation()
        var completions = 0
        launch.play(enabled: true) { completions += 1 }
        try await Task.sleep(nanoseconds: 2_100_000_000)
        #expect(completions == 1)
        #expect(launch.panel == nil)
    }
}
