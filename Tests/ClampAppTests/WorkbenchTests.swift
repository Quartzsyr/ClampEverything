import AppKit
import Testing
import ClampCore
@testable import ClampEverything

@Suite(.serialized) @MainActor struct WorkbenchTests {
    func setup() -> (ClipStore, URL) {
        _ = NSApplication.shared
        let root = URL(fileURLWithPath: "/private/tmp/ClampWorkbench-" + UUID().uuidString)
        let store = ClipStore(root: root); store.hidden = true
        store.addTextOrLink("First note"); store.addTextOrLink("Second note")
        return (store, root)
    }
    @Test func scenesPersistShareItemsAndIncludeNewCaptures() throws {
        let (store, root) = setup(); defer { try? FileManager.default.removeItem(at: root) }
        let first = store.active[0].id, second = store.active[1].id
        let scene = try #require(store.createScene(title: "Write", ids: [first]))
        #expect(store.sceneItems.map(\.id) == [first])
        store.addTextOrLink("new capture")
        #expect(store.sceneItems.count == 2)
        #expect(store.active.count == 3)
        store.setSceneMember(second, scene: scene, included: true)
        #expect(store.sceneItems.count == 3)
        let restored = ClipStore(root: root)
        #expect(restored.currentScene?.id == scene)
        #expect(restored.sceneItems.count == 3)
        store.deleteScene(scene)
        #expect(store.active.count == 3)
        #expect(store.currentScene == nil)
    }
    @Test func groupingExtractionAndOutgoingIdentityPreserveContent() throws {
        let (store, root) = setup(); defer { try? FileManager.default.removeItem(at: root) }
        let a = store.active[0].id, b = store.active[1].id
        let group = try #require(store.combine(a, with: b))
        #expect(store.members(group).count == 2)
        #expect(!store.canCombine(a, with: b))
        let source = try #require(store.item(a))
        let writer = try #require(store.pasteboardItem(source))
        #expect(writer.string(forType: .clampItemID) == a.uuidString)
        #expect(writer.string(forType: .string) == "First note")
        store.extract(a)
        #expect(store.item(a)?.groupID == nil)
        #expect(store.item(a)?.placement.mode == .floating)
        #expect(store.item(a)?.text == "First note")
        #expect(store.members(group).count == 1)
        store.remove(b)
        #expect(store.combine(a, with: b) == nil)
        #expect(store.active.count == 1)
    }
    @Test func sceneSwitchRetiresPendingHoverAndFiltersGroupContents() async throws {
        let (store, root) = setup()
        let a = store.active[0].id, b = store.active[1].id
        let group = try #require(store.combine(a, with: b))
        let manager = WindowManager(store: store)
        defer { manager.shutdown(); try? FileManager.default.removeItem(at: root) }
        let old = manager.model(group); old.hover(true)
        let empty = try #require(store.createScene(title: "Empty", ids: []))
        old.show()
        try await Task.sleep(nanoseconds: 400_000_000)
        #expect(manager.cards[group] == nil)
        #expect(!old.panel.isVisible)
        store.setSceneMember(a, scene: empty, included: true)
        #expect(store.sceneMembers(group).map(\.id) == [a])
        #expect(store.members(group).count == 2)
        #expect(manager.cards[group] != nil)
        store.selectScene(nil)
        #expect(store.sceneMembers(group).count == 2)
    }
    @Test func collapsedClipsAlwaysStayCompact() throws {
        let (store, root) = setup()
        let manager = WindowManager(store: store)
        defer { manager.shutdown(); try? FileManager.default.removeItem(at: root) }
        let card = manager.model(store.active[0].id)
        manager.layout(card)
        #expect(card.panel.frame.width == 64)
        // Old saved label preferences must not reintroduce expanded edge labels.
        let json = Data(#"{"showEdgeLabels":true}"#.utf8)
        store.state.preferences = try JSONDecoder().decode(AppPreferences.self, from: json)
        store.changed(immediate: true)
        #expect(card.panel.frame.width == 64)
    }
    @Test func groupFlipsWithSwingSpaceAndSettlesToSheetSize() async throws {
        let (store, root) = setup()
        store.createGroup(Set(store.active.map(\.id)))
        let manager = WindowManager(store: store)
        defer { manager.shutdown(); try? FileManager.default.removeItem(at: root) }
        let group = try #require(store.state.groups.first)
        let card = manager.model(group.id)
        card.present()
        #expect(card.panel.frame.height >= HingeReveal.swingHeight(size: card.sheetSize, isLeft: false))
        try await Task.sleep(nanoseconds: 900_000_000)
        #expect(!card.revealInFlight)
        #expect(card.expanded)
        card.close()
        try await Task.sleep(nanoseconds: 300_000_000)
        #expect(!card.expanded)
        #expect(card.panel.frame.width == 64)
    }
    @Test func legacyLibraryLoadsWithoutScenes() throws {
        let json = Data(#"{"version":1,"items":[],"groups":[],"preferences":{}}"#.utf8)
        let state = try JSONDecoder().decode(LibraryState.self, from: json)
        #expect(state.scenes.isEmpty)
        #expect(state.activeSceneID == nil)
    }
}
