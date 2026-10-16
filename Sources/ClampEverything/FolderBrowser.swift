import AppKit
import SwiftUI
import ClampCore
import Darwin

struct FolderEntry: Identifiable, Equatable, Sendable {
    let url: URL
    let folder: Bool
    var id: String { url.path }
    var item: ClipItem {
        var item = ClipItem(kind: folder ? .folder : .file, title: url.lastPathComponent)
        item.originalPath = url.path; return item
    }
}

enum FolderContents {
    static func read(_ url: URL, hidden: Bool) throws -> [FolderEntry] {
        let urls = try FileManager.default.contentsOfDirectory(at: url.resolvingSymlinksInPath(),
            includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey], options: hidden ? [] : [.skipsHiddenFiles])
        return urls.map { child in
            let values = try? child.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
            // FileManager can return a physical path (e.g. /private/var) for a
            // logical root (/var). Keep navigation and copying under that root.
            let entryURL = url.appendingPathComponent(child.lastPathComponent, isDirectory: values?.isDirectory == true)
            return FolderEntry(url: entryURL, folder: values?.isDirectory == true && values?.isPackage != true)
        }.sorted { a, b in
            a.folder != b.folder ? a.folder : a.url.lastPathComponent.localizedStandardCompare(b.url.lastPathComponent) == .orderedAscending
        }
    }
}

private final class FolderDirectoryWatch {
    private let source: DispatchSourceFileSystemObject
    init?(_ url: URL, change: @escaping @Sendable () -> Void) {
        let descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else { return nil }
        source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: [.write, .delete, .rename], queue: .global(qos: .utility))
        source.setEventHandler(handler: change)
        source.setCancelHandler { close(descriptor) }
        source.resume()
    }
    deinit { source.cancel() }
}

@MainActor final class FolderBrowser: ObservableObject {
    @Published private(set) var root: URL?
    @Published private(set) var current: URL?
    @Published private(set) var entries: [FolderEntry] = []
    @Published private(set) var failure: String?
    @Published private(set) var loading = false
    private var showHidden = false
    private var active = false
    private var parents: [URL] = []
    private var generation = 0
    private var reading: Task<Void, Never>?
    private var refresh: Task<Void, Never>?
    private var watch: FolderDirectoryWatch?
    var canGoBack: Bool { !parents.isEmpty }
    func openRoot(_ url: URL?, hidden: Bool) {
        active = true
        let url = url.map { URL(fileURLWithPath: $0.resolvingSymlinksInPath().standardizedFileURL.path, isDirectory: true) }
        if root != url { root = url; current = url; parents = []; entries = []; watch = nil }
        showHidden = hidden; reload(); startWatching()
    }
    func setHidden(_ hidden: Bool) { guard hidden != showHidden else { return }; showHidden = hidden; reload() }
    func enter(_ entry: FolderEntry) {
        guard entry.folder, entries.contains(entry) else { return }
        if let current { parents.append(current) }
        current = entry.url; entries = []; watch = nil; reload(); startWatching()
    }
    func back() {
        guard let parent = parents.popLast() else { return }
        current = parent; entries = []; watch = nil; reload(); startWatching()
    }
    func goToRoot() {
        guard canGoBack else { return }
        current = root; parents = []; entries = []; watch = nil; reload(); startWatching()
    }
    func reload() {
        generation += 1; let token = generation
        reading?.cancel(); failure = nil
        guard let url = current else { entries = []; loading = false; failure = "原目录不可用，请重新关联。"; return }
        let hidden = showHidden; loading = true
        reading = Task { @MainActor [weak self] in
            let result = await Task.detached(priority: .userInitiated) { Result { try FolderContents.read(url, hidden: hidden) } }.value
            guard let self, !Task.isCancelled, self.generation == token else { return }
            self.loading = false
            switch result {
            case .success(let entries): self.entries = entries
            case .failure(let error): self.entries = []; self.failure = error.localizedDescription
            }
        }
    }
    private func startWatching() {
        guard watch == nil, let current else { return }
        watch = FolderDirectoryWatch(current) { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.active, self.current == current else { return }
                self.scheduleRefresh()
            }
        }
    }
    private func scheduleRefresh() {
        refresh?.cancel()
        refresh = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: 100_000_000) } catch { return }
            self?.reload()
        }
    }
    func stop() { active = false; generation += 1; reading?.cancel(); refresh?.cancel(); watch = nil; loading = false }
    deinit { reading?.cancel(); refresh?.cancel() }
}

struct FolderBody: View {
    @ObservedObject var store: ClipStore
    let item: ClipItem
    var interaction: (Bool) -> Void
    @StateObject private var browser = FolderBrowser()
    @State private var receivingFiles = false
    var root: URL? { store.fileURL(item) }
    var folderItem: ClipItem {
        guard let current = browser.current else { return item }
        var copy = item; copy.originalPath = current.path
        if current != browser.root { copy.bookmark = nil; copy.assetName = nil; copy.title = current.lastPathComponent }
        return copy
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                if browser.canGoBack {
                    Button { browser.back() } label: { Image(systemName: "chevron.left").font(.system(size: 10, weight: .medium)).frame(width: 18, height: 22) }
                        .buttonStyle(.plain).help("返回上一级")
                }
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text(browser.current?.lastPathComponent ?? item.title).font(.system(size: 12, weight: .medium)).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 0)
                    Text(browser.loading ? "…" : "\(browser.entries.count) 项").font(.system(size: 9)).monospacedDigit().foregroundStyle(.tertiary)
                }.frame(height: 23)
                    .overlay(ContentDragHandle(item: folderItem, store: store, interaction: interaction, showLabel: false))
                    .help((browser.current?.path ?? item.title) + " · 单击复制文件夹 · 拖出复制")
                Menu {
                    if browser.canGoBack { Button("回到根目录") { browser.goToRoot() }; Divider() }
                    Button("在 Finder 中打开") { if let current = browser.current { NSWorkspace.shared.open(current) } }
                    Button("刷新") { browser.reload() }
                    Toggle("显示隐藏文件", isOn: Binding(get: { store.state.preferences.showHiddenFiles }, set: { store.state.preferences.showHiddenFiles = $0; store.changed() }))
                } label: { Image(systemName: "ellipsis").font(.system(size: 11)) }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            }
            ZStack {
                FolderEntryList(entries: browser.entries, directory: browser.current, store: store, interaction: interaction, enter: { browser.enter($0) })
                if let failure = browser.failure { Text(failure).font(.system(size: 11)).foregroundStyle(.secondary).padding(10).frame(maxWidth: .infinity, maxHeight: .infinity).allowsHitTesting(false) }
                else if browser.entries.isEmpty {
                    if browser.loading { ProgressView().controlSize(.small).allowsHitTesting(false) }
                    else { Text("空文件夹").font(.system(size: 11)).foregroundStyle(.secondary).allowsHitTesting(false) }
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
            if receivingFiles { Text("松手复制到此文件夹").font(.system(size: 10)).foregroundStyle(ClipStyle.accent) }
            if let progress = store.copies[item.id], progress.running || progress.results.contains(where: { $0.error != nil }) {
                HStack(spacing: 6) {
                    if progress.running { ProgressView(value: Double(progress.completed), total: Double(max(1, progress.total))).frame(maxWidth: 70) }
                    Text(progress.running ? "\(progress.completed)/\(progress.total)" : "部分文件未复制")
                    Spacer()
                    if progress.running { Button("停止") { store.copies[item.id]?.cancelRequested = true } }
                    else { Button("重试") { store.retryCopy(item.id) } }
                }.font(.system(size: 9)).buttonStyle(.borderless)
                    .help(progress.results.compactMap { $0.error }.joined(separator: "\n"))
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(receivingFiles ? ClipStyle.accent : .clear, lineWidth: 1).allowsHitTesting(false))
        .onDrop(of: ["public.file-url"], isTargeted: $receivingFiles) { providers in
            guard let current = browser.current else { return false }
            interaction(true)
            Task { @MainActor in
                let urls = await DroppedFileURLs.read(providers); interaction(false)
                if !urls.isEmpty { store.startCopy(urls, to: current, for: item.id) }
            }
            return true
        }
        .onAppear { browser.openRoot(root, hidden: store.state.preferences.showHiddenFiles) }
        .onChange(of: root) { _, url in browser.openRoot(url, hidden: store.state.preferences.showHiddenFiles) }
        .onChange(of: store.state.preferences.showHiddenFiles) { _, hidden in browser.setHidden(hidden) }
        .onChange(of: store.copies[item.id]?.running) { _, running in if running == false { browser.reload() } }
        .onDisappear { browser.stop() }
    }
}
