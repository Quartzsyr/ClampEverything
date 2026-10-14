import AppKit
import SwiftUI
import ClampCore

extension ClipStore {
    func tactile(_ pattern: NSHapticFeedbackManager.FeedbackPattern = .generic) {
        guard state.preferences.tactileFeedback else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
    }
    var currentScene: WorkScene? { state.scenes.first { $0.id == state.activeSceneID } }
    var sceneItems: [ClipItem] { guard let scene = currentScene else { return active }; return active.filter { scene.itemIDs.contains($0.id) } }
    var sceneGroups: [ClipGroup] {
        guard currentScene != nil else { return state.groups }
        let groupIDs = Set(sceneItems.compactMap(\.groupID))
        return state.groups.filter { groupIDs.contains($0.id) }
    }
    func sceneMembers(_ group: UUID) -> [ClipItem] { sceneItems.filter { $0.groupID == group } }
    func visibleInScene(_ id: UUID) -> Bool { sceneItems.contains { $0.id == id } || sceneGroups.contains { $0.id == id } }
    func includeInCurrentScene(_ id: UUID) {
        guard let index = state.scenes.firstIndex(where: { $0.id == state.activeSceneID }) else { return }
        state.scenes[index].itemIDs.insert(id)
    }
    @discardableResult func createScene(title: String, ids: Set<UUID>) -> UUID? {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard writable, !name.isEmpty else { return nil }
        let scene = WorkScene(title: String(name.prefix(60)), itemIDs: ids.intersection(Set(active.map(\.id))))
        state.scenes.append(scene); state.activeSceneID = scene.id; hidden = false
        changed(immediate: true); return scene.id
    }
    func selectScene(_ id: UUID?) {
        guard writable, id == nil || state.scenes.contains(where: { $0.id == id }) else { return }
        state.activeSceneID = id; hidden = false; changed(immediate: true)
    }
    func renameScene(_ id: UUID, title: String) {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard writable, !name.isEmpty, let index = state.scenes.firstIndex(where: { $0.id == id }) else { return }
        state.scenes[index].title = String(name.prefix(60)); changed(immediate: true)
    }
    func setSceneMember(_ item: UUID, scene: UUID, included: Bool) {
        guard writable, let index = state.scenes.firstIndex(where: { $0.id == scene }), active.contains(where: { $0.id == item }) else { return }
        if included { state.scenes[index].itemIDs.insert(item) } else { state.scenes[index].itemIDs.remove(item) }
        changed(immediate: true)
    }
    func deleteScene(_ id: UUID) {
        guard writable else { return }
        state.scenes.removeAll { $0.id == id }
        if state.activeSceneID == id { state.activeSceneID = nil }
        changed(immediate: true)
    }
    func canCombine(_ source: UUID, with destination: UUID) -> Bool {
        guard writable, source != destination, let sourceItem = item(source), sourceItem.removedAt == nil else { return false }
        if let target = item(destination) {
            guard target.removedAt == nil else { return false }
            return target.groupID == nil || target.groupID != sourceItem.groupID
        }
        return group(destination) != nil && sourceItem.groupID != destination
    }
    /// Only accepts existing library identities; external file drops keep using copy/import.
    @discardableResult func combine(_ source: UUID, with destination: UUID) -> UUID? {
        guard canCombine(source, with: destination), let item = item(source) else { return nil }
        let targetGroup = group(destination)?.id ?? self.item(destination)?.groupID
        if let targetGroup, group(targetGroup) != nil {
            guard item.groupID != targetGroup else { return nil }
            update(source) { $0.groupID = targetGroup; $0.placement.mode = .docked }
            changed(immediate: true); tactile(); onReveal?(targetGroup); return targetGroup
        }
        guard let target = self.item(destination), target.removedAt == nil else { return nil }
        createGroup([source, destination], title: "材料夹 · " + String(target.title.prefix(20)))
        return state.groups.last?.id
    }
    func extract(_ id: UUID) {
        guard writable, let item = item(id), item.removedAt == nil else { return }
        update(id) { $0.groupID = nil; $0.placement.mode = .floating }
        changed(immediate: true); tactile(); onReveal?(id)
    }
}

struct ScenePicker: View {
    @ObservedObject var store: ClipStore
    var body: some View {
        Menu {
            Button("全部材料") { store.selectScene(nil) }
            ForEach(store.state.scenes) { scene in
                Button { store.selectScene(scene.id) } label: {
                    if store.state.activeSceneID == scene.id { Label(scene.title, systemImage: "checkmark") }
                    else { Text(scene.title) }
                }
            }
        } label: { Label(store.currentScene?.title ?? "全部材料", systemImage: "rectangle.3.group") }
    }
}

struct SceneSettingsView: View {
    @ObservedObject var store: ClipStore
    @State private var name = ""
    @State private var rename = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("为写作、报销或旅行留一套材料，切换时只显示这一套。新夹入的内容自动加入当前场景。").font(.system(size: 11)).foregroundStyle(.secondary)
            ScenePicker(store: store)
            HStack {
                TextField("新场景名称", text: $name).textFieldStyle(.roundedBorder)
                Button("保存当前材料") {
                    if store.createScene(title: name, ids: Set(store.sceneItems.map(\.id))) != nil { name = "" }
                }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }.controlSize(.small)
            if let scene = store.currentScene {
                HStack {
                    TextField("场景名称", text: $rename).textFieldStyle(.roundedBorder)
                    Button("改名") { store.renameScene(scene.id, title: rename) }.disabled(rename.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button("删除场景") { store.deleteScene(scene.id) }
                }.controlSize(.small)
                Text("勾选此场景需要的材料（删除场景保留全部夹项）").font(.system(size: 10)).foregroundStyle(.secondary)
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(store.active) { item in
                            Toggle(isOn: Binding(get: { store.currentScene?.itemIDs.contains(item.id) ?? false }, set: { store.setSceneMember(item.id, scene: scene.id, included: $0) })) {
                                HStack { ClipIcon(item: item, size: 20); Text(item.title).lineLimit(1); Spacer(); Text(item.kind.title).foregroundStyle(.secondary) }
                            }.toggleStyle(.checkbox).font(.system(size: 11))
                        }
                        if store.active.isEmpty { Text("先夹入一些材料，再从这里选择。").font(.system(size: 12)).foregroundStyle(.secondary) }
                    }.padding(.vertical, 4)
                }
            } else {
                Text("当前显示全部材料。先保存一个场景，再勾选它需要的内容。").font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }.onAppear { rename = store.currentScene?.title ?? "" }
            .onChange(of: store.state.activeSceneID) { _, _ in rename = store.currentScene?.title ?? "" }
    }
}
