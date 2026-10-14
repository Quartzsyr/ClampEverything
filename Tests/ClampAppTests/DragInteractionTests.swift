import AppKit
import Testing
import ClampCore
@testable import ClampEverything

struct DragSamplerTests {
    @Test func motionIsConsistentAcrossInputRates() {
        func finalPull(rate: Double) -> PaperPull {
            var sampler = DragMotionSampler(); sampler.reset(at: 0)
            for step in 1...Int(rate) {
                let time = Double(step) / rate
                _ = sampler.sample(delta: CGPoint(x: time * 180, y: time * -90), at: time, inertia: 0.68)
            }
            return sampler.pull
        }
        let slow = finalPull(rate: 60), fast = finalPull(rate: 240)
        #expect(abs(slow.x - fast.x) < 0.01)
        #expect(abs(slow.y - fast.y) < 0.01)
        #expect(abs(slow.x - 0.2) < 0.01)
    }
    @Test func rapidEventsAreCoalescedAndExtremeVelocityIsBounded() {
        var sampler = DragMotionSampler(); sampler.reset(at: 0)
        #expect(sampler.sample(delta: CGPoint(x: 2, y: 0), at: 0.001, inertia: 0.4) == nil)
        let pull = sampler.sample(delta: CGPoint(x: 100000, y: -100000), at: 0.02, inertia: 0.4)
        #expect(pull != nil)
        #expect(abs(sampler.pull.x) <= 1 && abs(sampler.pull.y) <= 1)
    }
}

@Suite(.serialized) @MainActor struct DragInteractionTests {
    @Test func windowFollowsEveryEventEvenWhenVisualUpdateIsCoalesced() async throws {
        _ = NSApplication.shared
        let root = URL(fileURLWithPath: "/private/tmp/ClampDragRegression-" + UUID().uuidString)
        let store = ClipStore(root: root); store.hidden = true
        store.addTextOrLink("drag test")
        let manager = WindowManager(store: store)
        defer { manager.shutdown(); try? FileManager.default.removeItem(at: root) }
        let card = manager.model(try #require(store.active.first?.id))
        card.beginMove()
        let origin = card.panel.frame.origin
        for step in 1...20 {
            let delta = NSPoint(x: step * 3, y: step * 2)
            card.move(delta)
            #expect(card.panel.frame.origin == NSPoint(x: origin.x + delta.x, y: origin.y + delta.y))
        }
        try await Task.sleep(nanoseconds: 25_000_000)
        card.move(NSPoint(x: 100, y: 40))
        try await Task.sleep(nanoseconds: 160_000_000)
        #expect(card.dragResting && card.paperPull == .resting)
        card.retire()
        let retiredOrigin = card.panel.frame.origin
        card.move(NSPoint(x: 500, y: 500))
        #expect(card.panel.frame.origin == retiredOrigin)
    }
    @Test func edgeDropFoldsAndAQuickPickupCancelsTheOldClose() async throws {
        _ = NSApplication.shared
        let screen = try #require(NSScreen.screens.first)
        let root = URL(fileURLWithPath: "/private/tmp/ClampDropFoldRegression-" + UUID().uuidString)
        let store = ClipStore(root: root); store.hidden = true
        store.addTextOrLink("edge test")
        let manager = WindowManager(store: store)
        defer { manager.shutdown(); try? FileManager.default.removeItem(at: root) }
        let id = try #require(store.active.first?.id), card = manager.model(id)
        store.update(id) { $0.placement.mode = .floating }
        card.beginMove()
        card.moving = false; card.busy = false
        manager.finishMove(card, at: CGPoint(x: screen.frame.maxX - 8, y: screen.visibleFrame.midY))
        #expect(store.item(id)?.placement.mode == .docked)
        #expect(card.expanded && card.revealInFlight)
        card.beginMove()
        let origin = card.panel.frame.origin
        card.move(NSPoint(x: -80, y: 20))
        try await Task.sleep(nanoseconds: 350_000_000)
        #expect(card.moving && card.expanded)
        #expect(card.panel.frame.origin == NSPoint(x: origin.x - 80, y: origin.y + 20))
    }
    @Test func batchPublishesOnlyFinalPlacementIncludingNestedChanges() throws {
        let root = URL(fileURLWithPath: "/private/tmp/ClampBatchRegression-" + UUID().uuidString)
        let store = ClipStore(root: root)
        defer { try? FileManager.default.removeItem(at: root) }
        var modes: [PlacementMode] = []
        store.onChange = { if let mode = store.active.first?.placement.mode { modes.append(mode) } }
        store.batchChanges {
            store.addTextOrLink("batched")
            store.batchChanges { store.update(store.active[0].id) { $0.placement.mode = .floating } }
            #expect(modes.isEmpty)
        }
        #expect(modes == [.floating])
        store.update(store.active[0].id) { $0.placement.mode = .docked }
        #expect(modes == [.floating, .docked])
    }
    @Test func cursorClosesOnlyAfterMaterialIsReadyAndRespectsThickness() {
        let pose = CursorClipPose(); pose.gripping = true; pose.openness = 0
        #expect(pose.effectiveOpenness == 1)
        pose.hasMaterial = true
        for material in PhysicalMaterial.allCases {
            pose.material = material
            #expect(pose.effectiveOpenness == material.jawOpening)
        }
        pose.failed = true
        #expect(pose.effectiveOpenness == 1)
    }
}
