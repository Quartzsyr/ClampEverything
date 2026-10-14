import AppKit
import SwiftUI
import UniformTypeIdentifiers
import QuickLookUI
import QuickLookThumbnailing
import ClampCore

struct CopyProgress {
    var target: URL
    var total: Int
    var completed = 0
    var results: [CopyResult] = []
    var running = true
    var cancelRequested = false
}

@MainActor final class ClipStore: ObservableObject {
    @Published var state = LibraryState()
    @Published var message: String?
    @Published var hidden = false
    @Published var copies: [UUID: CopyProgress] = [:]
    @Published var images: [UUID: NSImage] = [:]
    let storage: LibraryStorage
    let undo = UndoManager()
    let copyQueue = FileCopyQueue()
    var writable = true
    var onReveal: ((UUID) -> Void)?
    var onChange: (() -> Void)?
    private var saving: Timer?
    private var cleanupTimer: Timer?
    private var messageTimer: Timer?
    private var thumbnailPaths: [UUID: String] = [:]

    init(root: URL) {
        storage = LibraryStorage(root: root)
        do { try storage.prepare(); state = try storage.load() }
        catch { writable = false; message = "资料库未能读取：\(error.localizedDescription) 请检查 \(storage.stateURL.path)。为保护数据，已停止写入。" }
        prune()
        cleanupTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in Task { @MainActor in self?.prune() } }
    }
    var active: [ClipItem] { state.activeItems }
    var recovery: [ClipItem] { state.items.filter { $0.removedAt != nil }.sorted { ($0.removedAt ?? .distantPast) > ($1.removedAt ?? .distantPast) } }
    func item(_ id: UUID) -> ClipItem? { state.items.first { $0.id == id } }
    func group(_ id: UUID) -> ClipGroup? { state.groups.first { $0.id == id } }
    func members(_ id: UUID) -> [ClipItem] { active.filter { $0.groupID == id } }
    func notify(_ text: String) {
        messageTimer?.invalidate(); message = text
        messageTimer = Timer.scheduledTimer(withTimeInterval: 8, repeats: false) { [weak self] _ in Task { @MainActor in if self?.writable == true { self?.message = nil } } }
    }
    func changed(immediate: Bool = false) {
        guard writable else { return }
        onChange?()
        saving?.invalidate()
        if immediate { save() }
        else { saving = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: false) { [weak self] _ in Task { @MainActor in self?.save() } } }
    }
    func save() {
        guard writable else { return }
        do { try storage.save(state) } catch { notify("保存失败：\(error.localizedDescription)。当前内容仍在内存中，请重试保存。") }
    }
    func update(_ id: UUID, _ body: (inout ClipItem) -> Void) {
        guard writable, let index = state.items.firstIndex(where: { $0.id == id }) else { return }
        body(&state.items[index]); changed()
    }
    func updateGroup(_ id: UUID, _ body: (inout ClipGroup) -> Void) {
        guard writable, let index = state.groups.firstIndex(where: { $0.id == id }) else { return }
        body(&state.groups[index]); changed()
    }
    func setScreenForNew(_ item: inout ClipItem) {
        includeInCurrentScene(item.id)
        item.placement.side = state.preferences.defaultSide
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main { item.placement.position.screenID = screen.stableID }
    }
    func importFiles(_ urls: [URL], to groupID: UUID? = nil) {
        guard writable else { return }
        var count = 0
        for url in urls where url.isFileURL {
            do {
                guard FileManager.default.fileExists(atPath: url.path) else { notify("无法夹住：\(url.lastPathComponent)，文件不存在或设备未连接。"); continue }
                if let duplicate = active.first(where: { candidate in
                    guard candidate.bookmark != nil, let existing = fileURL(candidate) else { return false }
                    return FileReference.same(url, existing)
                }) { notify("已夹住「\(duplicate.title)」"); onReveal?(duplicate.id); continue }
                let resource = try url.resourceValues(forKeys: [.isDirectoryKey, .contentTypeKey])
                let kind: ClipKind = resource.isDirectory == true ? .folder : (resource.contentType?.conforms(to: .image) == true ? .image : .file)
                var item = ClipItem(kind: kind, title: url.lastPathComponent)
                item.bookmark = try FileReference.bookmark(for: url); item.originalPath = url.path; item.groupID = groupID
                setScreenForNew(&item); state.items.append(item); count += 1
            } catch { notify("无法夹住「\(url.lastPathComponent)」：\(error.localizedDescription)") }
        }
        if count > 0 { changed(immediate: true); notify("已夹住 \(count) 项") }
    }
    func fileURL(_ item: ClipItem) -> URL? {
        if let asset = item.assetName { return try? storage.assetURL(asset) }
        if let bookmark = item.bookmark, let result = try? FileReference.resolve(bookmark) { return result.url }
        return item.originalPath.map { URL(fileURLWithPath: $0) }
    }
    func refreshReference(_ id: UUID) {
        guard let item = item(id), let data = item.bookmark, let result = try? FileReference.resolve(data) else { return }
        if result.refreshed != nil || item.originalPath != result.url.path {
            update(id) { $0.bookmark = result.refreshed ?? data; $0.originalPath = result.url.path }
        }
    }
    func status(_ item: ClipItem) -> String? {
        guard item.bookmark != nil || item.assetName != nil else { return nil }
        guard let url = fileURL(item), FileManager.default.fileExists(atPath: url.path) else {
            if item.originalPath?.hasPrefix("/Volumes/") == true { return "设备未连接或原文件已失效，可重新关联" }
            return "原内容不可用，可重新关联位置"
        }
        if let values = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]),
           values.ubiquitousItemDownloadingStatus == .notDownloaded { return "云文件尚未下载，打开后由系统下载" }
        return nil
    }
    func ingest(_ board: NSPasteboard) {
        guard writable else { return }
        if let urls = board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty { importFiles(urls); return }
        if let image = NSImage(pasteboard: board), let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
           let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) {
            do {
                var item = ClipItem(kind: .image, title: "截图 · " + Date().formatted(date: .omitted, time: .shortened))
                let name = item.id.uuidString + ".png"
                try png.write(to: storage.assetURL(name), options: .atomic)
                item.assetName = name; setScreenForNew(&item); state.items.append(item); changed(immediate: true); notify("图片已夹住")
            } catch { notify("保存图片失败：\(error.localizedDescription)") }
            return
        }
        if let string = board.string(forType: .string), !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { addTextOrLink(string); return }
        if let url = board.readObjects(forClasses: [NSURL.self], options: nil)?.first as? URL { addTextOrLink(url.absoluteString); return }
        notify("没有可夹住的内容。请先复制文件、图片、文字或网页链接。")
    }
    func addCapturedImage(_ image: CGImage, title: String) {
        guard writable else { return }
        do {
            guard let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { notify("无法保存图片"); return }
            var item = ClipItem(kind: .image, title: title)
            let name = item.id.uuidString + ".png"
            try png.write(to: storage.assetURL(name), options: .atomic)
            item.assetName = name; setScreenForNew(&item); state.items.append(item)
            images[item.id] = NSImage(cgImage: image, size: .zero)
            changed(immediate: true); notify("图片已夹住")
        } catch { notify("图片保存失败：\(error.localizedDescription)") }
    }
    func addTextOrLink(_ string: String) {
        guard writable else { return }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        let url = URL(string: trimmed)
        let isLink = !trimmed.contains(where: \.isWhitespace) && ["http", "https"].contains(url?.scheme?.lowercased() ?? "") && !(url?.host ?? "").isEmpty
        if isLink, let duplicate = active.first(where: { $0.link == url?.absoluteString }) { notify("已夹住「\(duplicate.title)」"); onReveal?(duplicate.id); return }
        var item = ClipItem(kind: isLink ? .link : .text, title: isLink ? (url?.host ?? trimmed) : String(trimmed.split(separator: "\n").first.map(String.init)?.prefix(36) ?? "文字"))
        if isLink { item.link = url?.absoluteString } else { item.text = string }
        setScreenForNew(&item); state.items.append(item); changed(immediate: true); notify("\(item.kind.title)已夹住")
    }
    func chooseFiles() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = true; panel.allowsMultipleSelection = true; panel.prompt = "夹住"; panel.message = "原文件保持原位，屏幕夹子保存访问引用。"
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK { importFiles(panel.urls) }
    }
    func relink(_ item: ClipItem) {
        let panel = NSOpenPanel(); panel.canChooseDirectories = item.kind == .folder; panel.canChooseFiles = item.kind != .folder; panel.prompt = "重新关联"
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url {
            do { let bookmark = try FileReference.bookmark(for: url); update(item.id) { $0.bookmark = bookmark; $0.originalPath = url.path; $0.assetName = nil }; images[item.id] = nil; thumbnailPaths[item.id] = nil }
            catch { notify(error.localizedDescription) }
        }
    }
    func open(_ item: ClipItem) {
        if let link = item.link, let url = URL(string: link) { NSWorkspace.shared.open(url); return }
        guard let url = fileURL(item), FileManager.default.fileExists(atPath: url.path) else { notify("原内容不可用，请重新关联。"); return }
        refreshReference(item.id)
        NSWorkspace.shared.open(url, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            if let error { Task { @MainActor in self.notify("打开失败：\(error.localizedDescription)") } }
        }
    }
    func copy(_ item: ClipItem) {
        let board = NSPasteboard.general
        guard let writer = pasteboardItem(item) else { return }
        board.clearContents(); board.writeObjects([writer]); notify("已复制「\(item.title)」")
    }
    func copyPath(_ item: ClipItem) {
        guard let url = fileURL(item) else { return }
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(url.path, forType: .string); notify("路径已复制")
    }
    func pasteboardItem(_ item: ClipItem) -> NSPasteboardItem? {
        let writer = NSPasteboardItem()
        if self.item(item.id)?.removedAt == nil, self.item(item.id) != nil { writer.setString(item.id.uuidString, forType: .clampItemID) }
        if let text = item.text { writer.setString(text, forType: .string) }
        else if let link = item.link { writer.setString(link, forType: .URL); writer.setString(link, forType: .string) }
        else if let url = fileURL(item), FileManager.default.fileExists(atPath: url.path) {
            writer.setString(url.absoluteString, forType: .fileURL)
            if item.kind == .image, let image = NSImage(contentsOf: url), let tiff = image.tiffRepresentation { writer.setData(tiff, forType: .tiff) }
        } else { notify("无法拖出或复制：原内容不可用。"); return nil }
        return writer
    }
    func remove(_ id: UUID) {
        guard let item = item(id), item.removedAt == nil else { return }
        update(id) { $0.removedAt = Date() }
        save()
        undo.registerUndo(withTarget: self) { store in MainActor.assumeIsolated { store.restore(id) } }; undo.setActionName("取消固定")
        notify(item.ownsContent ? "已取消固定，内部副本可在恢复区找回，7 天后清理。" : "已取消固定，原文件保持原位。")
    }
    func restore(_ id: UUID) {
        update(id) { item in item.removedAt = nil; if let group = item.groupID, self.group(group) == nil { item.groupID = nil } }
        changed(immediate: true); onReveal?(id)
    }
    func prune() {
        guard writable else { return }
        var next = state
        let expired = next.purgeExpired()
        guard !expired.isEmpty else { return }
        do { try storage.save(next); state = next; try storage.deleteAssets(of: expired, remaining: state.items) }
        catch { notify("恢复区清理失败：\(error.localizedDescription)") }
        onChange?()
    }
    func createGroup(_ ids: Set<UUID>, title: String = "新项目") {
        guard writable, !ids.isEmpty else { return }
        var group = ClipGroup(title: title)
        if let first = active.first(where: { ids.contains($0.id) }) { group.placement = first.placement; group.placement.mode = .docked }
        state.groups.append(group)
        for index in state.items.indices where ids.contains(state.items[index].id) { state.items[index].groupID = group.id }
        changed(immediate: true); tactile(); onReveal?(group.id)
    }
    func dissolve(_ id: UUID) {
        guard writable else { return }; state.dissolve(id); changed(immediate: true)
    }
    func reorder(_ id: UUID, by delta: Int) {
        guard writable, let item = item(id) else { return }
        let peers = active.filter { $0.groupID == item.groupID }
        guard let index = peers.firstIndex(where: { $0.id == id }), peers.indices.contains(index + delta),
              let a = state.items.firstIndex(where: { $0.id == id }), let b = state.items.firstIndex(where: { $0.id == peers[index + delta].id }) else { return }
        state.items.swapAt(a, b); changed()
    }
    func startCopy(_ urls: [URL], to directory: URL, for id: UUID) {
        guard copies[id]?.running != true, !urls.isEmpty else { notify("该文件夹正在复制，请稍候。"); return }
        copies[id] = CopyProgress(target: directory, total: urls.count)
        Task {
            for source in urls {
                if copies[id]?.cancelRequested == true { break }
                let result = await copyQueue.copy(source, into: directory)
                copies[id]?.results.append(result); copies[id]?.completed += 1
            }
            copies[id]?.running = false
            let errors = copies[id]?.results.filter { $0.error != nil }.count ?? 0
            notify(errors == 0 ? "复制任务已结束，原内容保持原位。" : "\(errors) 项复制失败，可在卡片中查看并重试。")
        }
    }
    func retryCopy(_ id: UUID) {
        guard let progress = copies[id] else { return }
        startCopy(progress.results.filter { $0.error != nil }.map(\.source), to: progress.target, for: id)
    }
    func loadThumbnail(_ item: ClipItem) {
        guard [.file, .image].contains(item.kind), let url = fileURL(item), FileManager.default.fileExists(atPath: url.path), thumbnailPaths[item.id] != url.path else { return }
        thumbnailPaths[item.id] = url.path
        let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: 1000, height: 800), scale: 1, representationTypes: .thumbnail)
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, _ in
            guard let image = representation?.nsImage else { return }
            Task { @MainActor in self.images[item.id] = image }
        }
    }
    func reconcileScreens() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let ids = Set(NSScreen.screens.map(\.stableID))
        var didChange = false
        for index in state.items.indices {
            let old = state.items[index].placement
            state.items[index].placement.reconcile(available: ids, primary: screen.stableID)
            didChange = didChange || old != state.items[index].placement
        }
        for index in state.groups.indices {
            let old = state.groups[index].placement
            state.groups[index].placement.reconcile(available: ids, primary: screen.stableID)
            didChange = didChange || old != state.groups[index].placement
        }
        if didChange { changed(immediate: true) }
    }
}

extension NSScreen {
    var stableID: String {
        guard let number = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
              let uuid = CGDisplayCreateUUIDFromDisplayID(number.uint32Value)?.takeRetainedValue() else { return "main" }
        return CFUUIDCreateString(nil, uuid) as String
    }
}
