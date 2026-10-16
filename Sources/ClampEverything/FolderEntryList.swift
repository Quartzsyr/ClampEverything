import AppKit
import SwiftUI
import ClampCore

struct FolderEntryList: NSViewRepresentable {
    let entries: [FolderEntry]
    let directory: URL?
    let store: ClipStore
    var interaction: (Bool) -> Void
    var enter: (FolderEntry) -> Void
    func makeNSView(context: Context) -> FolderListView { FolderListView() }
    func updateNSView(_ view: FolderListView, context: Context) {
        view.store = store; view.interaction = interaction; view.enter = enter
        view.update(entries, directory: directory)
    }
}

/// AppKit owns both the scroll viewport and its recycled rows. The copy/drag
/// surfaces are inside this scroll view, so wheel events cannot hit a dead end.
final class FolderListView: NSScrollView, NSTableViewDataSource, NSTableViewDelegate {
    let table = NSTableView()
    private(set) var entries: [FolderEntry] = []
    private var directory: URL?
    weak var store: ClipStore?
    var interaction: (Bool) -> Void = { _ in }
    var enter: (FolderEntry) -> Void = { _ in }
    override init(frame: NSRect) {
        super.init(frame: frame)
        drawsBackground = false; borderType = .noBorder
        hasVerticalScroller = true; hasHorizontalScroller = false
        autohidesScrollers = true; scrollerStyle = .overlay
        table.style = .plain; table.headerView = nil; table.backgroundColor = .clear
        table.rowHeight = 28; table.intercellSpacing = .zero
        table.selectionHighlightStyle = .none; table.focusRingType = .none
        table.usesAlternatingRowBackgroundColors = false
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        let column = NSTableColumn(identifier: .init("file")); column.minWidth = 0
        table.addTableColumn(column); table.dataSource = self; table.delegate = self
        documentView = table
    }
    convenience init() { self.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
    override func layout() {
        super.layout()
        let width = max(1, contentSize.width)
        if table.frame.width != width { table.setFrameSize(CGSize(width: width, height: table.frame.height)) }
        if table.tableColumns[0].width != width { table.tableColumns[0].width = width }
    }
    override func scrollWheel(with event: NSEvent) {
        // Row copy surfaces forward here. Apply the delivered deltas directly,
        // including trackpad momentum, without relying on responder retargeting
        // across SwiftUI/AppKit hosts. Keep the viewport inside the full list.
        let delta = event.scrollingDeltaY
        guard delta.isFinite, abs(delta) > 0.01 else { return }
        let distance = delta * (event.hasPreciseScrollingDeltas ? 1 : table.rowHeight)
        let y = min(max(0, contentView.bounds.minY - distance), max(0, table.bounds.height - contentSize.height))
        contentView.scroll(to: CGPoint(x: 0, y: y))
        reflectScrolledClipView(contentView)
    }
    func update(_ values: [FolderEntry], directory: URL?) {
        let changedDirectory = self.directory != directory
        guard changedDirectory || entries != values else { return }
        let top = table.row(at: CGPoint(x: 1, y: contentView.bounds.minY + 1))
        let anchor = entries.indices.contains(top) ? entries[top].id : nil
        let offset = top >= 0 ? contentView.bounds.minY - table.rect(ofRow: top).minY : 0
        self.directory = directory; entries = values; table.reloadData()
        layoutSubtreeIfNeeded()
        var y = changedDirectory ? 0 : contentView.bounds.minY
        if !changedDirectory, let anchor, let row = values.firstIndex(where: { $0.id == anchor }) { y = table.rect(ofRow: row).minY + offset }
        contentView.scroll(to: CGPoint(x: 0, y: min(max(0, y), max(0, table.bounds.height - contentSize.height))))
        reflectScrolledClipView(contentView)
    }
    func numberOfRows(in tableView: NSTableView) -> Int { entries.count }
    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { false }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard entries.indices.contains(row) else { return nil }
        let identifier = NSUserInterfaceItemIdentifier("file-row")
        let view = table.makeView(withIdentifier: identifier, owner: self) as? FolderRowView ?? FolderRowView()
        view.identifier = identifier
        let entry = entries[row]
        view.configure(entry)
        view.surface.writer = { [weak self] in self?.store?.pasteboardItem(entry.item) }
        view.surface.copyAction = { [weak self, weak surface = view.surface] in
            guard let store = self?.store else { return }
            surface?.showCopyFeedback(success: store.copy(entry.item))
        }
        view.surface.interaction = { [weak self] active in self?.interaction(active) }
        view.surface.preview = { ContentDragPreview.image(title: entry.url.lastPathComponent, icon: NSWorkspace.shared.icon(forFile: entry.url.path)) }
        view.openFolder = { [weak self] in self?.enter(entry) }
        return view
    }
}

final class FolderRowView: NSTableCellView {
    let surface = ContentDragView()
    private let icon = NSImageView()
    private let name = NSTextField(labelWithString: "")
    let disclosure = NSButton()
    private var entry: FolderEntry?
    var openFolder: () -> Void = {}
    override var isFlipped: Bool { true }
    override init(frame: NSRect) {
        super.init(frame: frame)
        name.font = .systemFont(ofSize: 11); name.lineBreakMode = .byTruncatingMiddle
        name.maximumNumberOfLines = 1; name.textColor = .labelColor.withAlphaComponent(0.88)
        addSubview(icon); addSubview(name)
        surface.showLabel = false; addSubview(surface)
        disclosure.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: "进入文件夹")?
            .withSymbolConfiguration(.init(pointSize: 9, weight: .regular))
        disclosure.contentTintColor = .tertiaryLabelColor
        disclosure.imageScaling = .scaleProportionallyDown
        disclosure.isBordered = false; disclosure.bezelStyle = .inline
        disclosure.target = self; disclosure.action = #selector(enterFolder)
        disclosure.toolTip = "进入文件夹"; addSubview(disclosure)
        let menu = NSMenu()
        for (title, action) in [("打开", #selector(openEntry)), ("快速预览", #selector(previewEntry)), ("在 Finder 中显示", #selector(revealEntry))] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: ""); item.target = self; menu.addItem(item)
        }
        surface.menu = menu
    }
    convenience init() { self.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
    func configure(_ entry: FolderEntry) {
        if self.entry != entry { surface.resetForReuse() }
        self.entry = entry; name.stringValue = entry.url.lastPathComponent
        icon.image = NSWorkspace.shared.icon(forFile: entry.url.path)
        surface.toolTip = entry.url.lastPathComponent + " · 单击复制 · 拖出复制"
        disclosure.isHidden = !entry.folder
        needsLayout = true
    }
    override func layout() {
        super.layout()
        let edge: CGFloat = disclosure.isHidden ? 0 : 22
        icon.frame = CGRect(x: 1, y: (bounds.height - 16) / 2, width: 16, height: 16)
        name.frame = CGRect(x: 25, y: (bounds.height - 16) / 2, width: max(0, bounds.width - 25 - edge - 3), height: 16)
        surface.frame = CGRect(x: 0, y: 0, width: max(0, bounds.width - edge), height: bounds.height)
        disclosure.frame = CGRect(x: bounds.width - 22, y: 0, width: 22, height: bounds.height)
    }
    @objc private func enterFolder() { openFolder() }
    @objc private func openEntry() { if let entry { NSWorkspace.shared.open(entry.url) } }
    @objc private func previewEntry() { if let entry { PreviewController.shared.show(entry.url) } }
    @objc private func revealEntry() { if let entry { NSWorkspace.shared.activateFileViewerSelecting([entry.url]) } }
}
