import Foundation
import AppKit
import Testing
import ClampCore
@testable import ClampEverything

@Suite(.serialized) @MainActor struct PanelTests {
    @Test func brassReceiverDefaultsOffAndToggleImmediatelyUpdatesEveryScreen() throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ClampBrass-" + UUID().uuidString)
        let store = ClipStore(root: root); store.hidden = false
        store.state.preferences.hideInFullScreen = false
        store.addTextOrLink("保留已有夹项")
        let manager = WindowManager(store: store)
        defer { manager.shutdown(); try? FileManager.default.removeItem(at: root) }
        #expect(!manager.rails.isEmpty)
        #expect(manager.rails.values.allSatisfy { !$0.isVisible && $0.contentView == nil })
        let id = try #require(store.active.first?.id)
        for enabled in [true, false, true, false] {
            store.state.preferences.showBrassClip = enabled
            store.changed(immediate: true)
            #expect(manager.rails.values.allSatisfy { $0.isVisible == enabled && ($0.contentView != nil) == enabled })
            #expect(manager.cards[id]?.panel.isVisible == true)
            let reopened = ClipStore(root: root)
            #expect(reopened.state.preferences.showBrassClip == enabled)
        }
        manager.showGuide()
        #expect(manager.rails.values.allSatisfy { !$0.isVisible })
        manager.dismissGuide()
        #expect(manager.rails.values.allSatisfy { !$0.isVisible })
    }
    @Test func referencePanelDoesNotReplaceEditingKeyWindow() {
        _ = NSApplication.shared
        let editing = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 200, height: 100), styleMask: [.titled], backing: .buffered, defer: false)
        editing.isReleasedWhenClosed = false
        editing.makeKey()
        let before = NSApp.keyWindow
        let panel = FloatingPanel(); panel.isReleasedWhenClosed = false
        panel.setFrame(NSRect(x: 50, y: 50, width: 112, height: 44), display: false)
        panel.orderFrontRegardless()
        #expect(NSApp.keyWindow === before)
        #expect(!panel.canBecomeKey)
        panel.close(); editing.close()
    }
    @Test func removedClipCannotReappearFromPendingHoverOrThumbnail() async throws {
        _ = NSApplication.shared
        let root = URL(fileURLWithPath: "/private/tmp/ClampPanelTests-" + UUID().uuidString)
        let store = ClipStore(root: root)
        store.state.preferences.hideInFullScreen = false
        store.addTextOrLink("remove regression")
        let id = try #require(store.active.first?.id)
        let manager = WindowManager(store: store)
        defer { manager.shutdown(); try? FileManager.default.removeItem(at: root) }
        for _ in 0..<2 {
            let card = manager.model(id)
            card.show(); card.hover(true)
            store.remove(id)
            // Simulate delayed hover / thumbnail / menu callbacks holding the old model.
            card.hover(true); card.show(); manager.layout(card); manager.reveal(id)
            try await Task.sleep(nanoseconds: 550_000_000)
            #expect(manager.cards[id] == nil)
            #expect(card.panel.contentView == nil)
            #expect(!card.panel.isVisible)
            let reopened = ClipStore(root: root)
            #expect(reopened.active.isEmpty)
            store.restore(id)
            #expect(manager.cards[id] !== card)
            #expect(manager.cards[id]?.expanded == true)
        }
    }

    @Test func explicitCloseCancelsHoverUntilReentryOrClick() async throws {
        _ = NSApplication.shared
        let root = URL(fileURLWithPath: "/private/tmp/ClampCloseTests-" + UUID().uuidString)
        let store = ClipStore(root: root); store.hidden = true
        store.addTextOrLink("close regression")
        let manager = WindowManager(store: store)
        defer { manager.shutdown(); try? FileManager.default.removeItem(at: root) }
        let id = try #require(store.active.first?.id)
        let card = manager.model(id)
        for _ in 0..<2 {
            card.show(); card.hover(true); card.close(); card.hover(true)
            try await Task.sleep(nanoseconds: 550_000_000)
            #expect(!card.expanded)
            #expect(card.hoverSuppressed)
            card.show()
            #expect(card.expanded)
            #expect(!card.hoverSuppressed)
        }
    }

    @Test func paperAppearancePersistsWithIdentity() {
        let id = UUID(uuidString: "A31A31A3-1111-4444-8888-000000000001")!
        let restored = UUID(uuidString: id.uuidString)!
        let first = PaperGrain(id: id), reopened = PaperGrain(id: restored)
        let other = PaperGrain(id: UUID(uuidString: "A31A31A3-1111-4444-8888-000000000002")!)
        #expect((0..<1000).allSatisfy { first.value($0) == reopened.value($0) })
        #expect((0..<72).contains { first.value($0) != other.value($0) })
        #expect((0..<1000).allSatisfy { (0..<1).contains(first.value($0)) })
    }

    @Test func unavailableScreenClampsSavedCoordinates() {
        var placement = ClipPlacement()
        // Model screen fallback clamps invalid saved fractions before window layout.
        placement.position = ScreenPosition(screenID: "gone", x: -1, y: 4)
        placement.reconcile(available: ["present"], primary: "present")
        #expect(placement.position.x == 0); #expect(placement.position.y == 1)
    }
    @Test func photoPanelFitsImageWithOnlyThinSheetMargins() throws {
        _ = NSApplication.shared
        let root = URL(fileURLWithPath: "/private/tmp/ClampPhotoLayoutTests-" + UUID().uuidString)
        let store = ClipStore(root: root); store.hidden = true
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 800, pixelsHigh: 450,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        store.addCapturedImage(try #require(bitmap.cgImage), title: "photo geometry")
        let id = try #require(store.active.first?.id)
        store.update(id) { $0.placement.mode = .floating; $0.placement.width = 456; $0.placement.height = 620 }
        let manager = WindowManager(store: store)
        defer { manager.shutdown(); try? FileManager.default.removeItem(at: root) }
        let card = manager.model(id)
        manager.layout(card)
        let frame = card.panel.frame
        #expect(abs((frame.width - 24) / (frame.height - ClipOrientation.verticalMargins) - 800.0 / 450.0) < 0.001)
    }
    @Test func reopeningCancelsPendingFoldBackBeforeWindowShrinks() async throws {
        _ = NSApplication.shared
        let root = URL(fileURLWithPath: "/private/tmp/ClampRevealTests-" + UUID().uuidString)
        let store = ClipStore(root: root); store.hidden = true
        store.addTextOrLink("reveal regression")
        let manager = WindowManager(store: store)
        defer { manager.shutdown(); try? FileManager.default.removeItem(at: root) }
        let id = try #require(store.active.first?.id)
        let card = manager.model(id)
        card.present(animated: false)
        card.close()
        card.show()
        try await Task.sleep(nanoseconds: 380_000_000)
        #expect(card.expanded)
        #expect(card.revealProgress == 1)
        #expect(card.panel.frame.width > 64)
        card.close()
        store.remove(id)
        try await Task.sleep(nanoseconds: 350_000_000)
        #expect(!card.panel.isVisible)
        #expect(card.panel.contentView == nil)
    }
    @Test(arguments: [ClipKind.text, .folder, .file, .link, .image])
    func hingeSpacePreservesSheetSizeAndReleasesAfterSettling(kind: ClipKind) async throws {
        _ = NSApplication.shared
        let root = URL(fileURLWithPath: "/private/tmp/ClampHingeSpaceTests-" + UUID().uuidString)
        let store = ClipStore(root: root); store.hidden = true
        store.addTextOrLink("hinge bounds")
        let itemID = try #require(store.active.first?.id)
        store.update(itemID) { $0.kind = kind }
        let manager = WindowManager(store: store)
        defer { manager.shutdown(); try? FileManager.default.removeItem(at: root) }
        let card = manager.model(try #require(store.active.first?.id))
        card.present(animated: false)
        let sheet = card.sheetSize, top = card.panel.frame.maxY
        card.close(); card.show()
        #expect(card.sheetSize == sheet)
        #expect(card.panel.frame.height >= HingeReveal.swingHeight(size: sheet, isLeft: false))
        #expect(card.panel.frame.maxY == top)
        try await Task.sleep(nanoseconds: 900_000_000)
        #expect(!card.revealInFlight)
        #expect(card.panel.frame.size == sheet)
        #expect(card.panel.frame.maxY == top)
        card.close()
        try await Task.sleep(nanoseconds: 350_000_000)
        #expect(!card.expanded && !card.revealInFlight)
        #expect(card.panel.frame.width == manager.compactWidth)
    }
}

@Suite(.serialized) @MainActor struct CapturedPlacementTests {
    @Test func dropPositionPersistsAndDockHeightSurvivesReload() throws {
        _ = NSApplication.shared
        let screen = try #require(NSScreen.screens.first)
        let root = URL(fileURLWithPath: "/private/tmp/ClampDropTests-" + UUID().uuidString)
        let store = ClipStore(root: root); store.hidden = true
        store.addTextOrLink("drop position")
        let manager = WindowManager(store: store)
        defer { manager.shutdown(); try? FileManager.default.removeItem(at: root) }
        let id = try #require(store.active.first?.id)
        let drop = CGPoint(x: screen.frame.minX + 10, y: screen.visibleFrame.midY)
        manager.placeCaptured(id, at: drop)
        #expect(store.item(id)?.placement.mode == .docked)
        #expect(store.item(id)?.placement.side == .left)
        #expect(abs(manager.model(id).panel.frame.midY - drop.y) < 1)
        let restored = ClipStore(root: root)
        #expect(restored.item(id)?.placement.dockHeight == store.item(id)?.placement.dockHeight)
        manager.placeCaptured(id, at: CGPoint(x: screen.frame.midX, y: screen.frame.midY))
        #expect(store.item(id)?.placement.mode == .floating)
        #expect(manager.model(id).expanded)
        store.state.preferences.autoSnap = false
        manager.placeCaptured(id, at: drop)
        #expect(store.item(id)?.placement.mode == .floating)
        store.state.preferences.motionIntensity = 0
        manager.model(id).present()
        #expect(!manager.model(id).revealInFlight)
    }

    @Test func disabledHoverStillAllowsExplicitOpen() async throws {
        _ = NSApplication.shared
        let root = URL(fileURLWithPath: "/private/tmp/ClampHoverSetting-" + UUID().uuidString)
        let store = ClipStore(root: root); store.hidden = true
        store.state.preferences.hoverToExpand = false
        store.state.preferences.hoverDelay = 0.1
        store.addTextOrLink("click only")
        let manager = WindowManager(store: store)
        defer { manager.shutdown(); try? FileManager.default.removeItem(at: root) }
        let card = manager.model(try #require(store.active.first?.id))
        card.hover(true)
        try await Task.sleep(nanoseconds: 160_000_000)
        #expect(!card.expanded)
        card.show()
        #expect(card.expanded)
    }

    @Test func oldPlacementsRemainDecodable() throws {
        var placement = ClipPlacement()
        placement.dockHeight = 0.35
        let encoded = try JSONEncoder().encode(placement)
        #expect(try JSONDecoder().decode(ClipPlacement.self, from: encoded).dockHeight == 0.35)
        var fields = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        fields.removeValue(forKey: "dockHeight")
        let legacy = try JSONSerialization.data(withJSONObject: fields)
        #expect(try JSONDecoder().decode(ClipPlacement.self, from: legacy).dockHeight == nil)
    }
}
