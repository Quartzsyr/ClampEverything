import AppKit
import SwiftUI
import Combine
import ClampCore
import ApplicationServices
import Carbon

@main enum ClampEverythingApp {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    var store: ClipStore!
    var windows: WindowManager!
    var status: NSStatusItem!
    var isDemo = false
    private let launchPresentation = LaunchPresentation()
    private var feedback: AnyCancellable?
    private var statusMenu: NSMenu?
    private let sceneMenu = NSMenu(title: "工作场景")
    func applicationDidFinishLaunching(_ notification: Notification) {
        let arguments = CommandLine.arguments
        if let exportIndex = arguments.firstIndex(of: "--export-website"), arguments.indices.contains(exportIndex + 1) {
            Task { @MainActor in
                do { try await WebsiteAssetExporter.export(to: URL(fileURLWithPath: arguments[exportIndex + 1])); NSApp.terminate(nil) }
                catch { fputs("Website export failed: \(error)\n", stderr); exit(1) }
            }
            return
        }
        isDemo = arguments.contains("--demo") || arguments.contains("--export-design") || arguments.contains("--export-customization") || arguments.contains("--export-workbench") || arguments.contains("--export-physical")
        let root: URL
        if let override = ProcessInfo.processInfo.environment["CLAMP_DATA_ROOT"] { root = URL(fileURLWithPath: override, isDirectory: true) }
        else if isDemo { root = URL(fileURLWithPath: "/private/tmp").appendingPathComponent("ClampDemo-" + UUID().uuidString.prefix(8)) }
        else { root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("ClampEverything", isDirectory: true) }
        store = ClipStore(root: root)
        if isDemo { installDemo() }
        windows = WindowManager(store: store)
        configureMenu()
        if arguments.contains("--request-accessibility") { windows.pointClamp.requestAccessibility() }
        // Report from the actual app process so TCC checks use its signed identity.
        if let index = arguments.firstIndex(of: "--permission-report"), arguments.indices.contains(index + 1) {
            let reportURL = URL(fileURLWithPath: arguments[index + 1])
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                self.windows.pointClamp.refreshConfiguration()
                let report: [String: Any] = [
                    "bundlePath": Bundle.main.bundlePath,
                    "pid": ProcessInfo.processInfo.processIdentifier,
                    "accessibility": AXIsProcessTrusted(),
                    "screenCapture": CGPreflightScreenCaptureAccess(),
                    "listenEvents": CGPreflightListenEventAccess(),
                    "postEvents": CGPreflightPostEventAccess(),
                    "secureInput": IsSecureEventInputEnabled(),
                    "enabled": self.store.state.preferences.holdToClampEnabled,
                    "running": self.windows.pointClamp.running,
                    "status": self.windows.pointClamp.status
                ]
                if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
                    try? data.write(to: reportURL, options: .atomic)
                }
            }
        }
        let needsGuide = !isDemo && (arguments.contains("--guide") || (store.active.isEmpty && store.state.groups.isEmpty && !arguments.contains("--settings")))
        launchPresentation.play(enabled: !isDemo && !arguments.contains("--settings") && store.state.preferences.motionIntensity > 0) { [weak self] in
            if needsGuide { self?.windows.showGuide() }
        }
        if arguments.contains("--settings") { windows.showSettings() }
        if let shortcut = store.state.preferences.shortcut, let error = ShortcutManager.shared.register(shortcut, action: { [weak self] in self?.windows.toggleVisibility() }) { store.notify(error) }
        if let index = arguments.firstIndex(of: "--export-physical"), arguments.indices.contains(index + 1) {
            store.hidden = true; windows.sync()
            Task { @MainActor in
                do { try await DesignExporter.exportPhysical(store: store, manager: windows, to: URL(fileURLWithPath: arguments[index + 1])); NSApp.terminate(nil) }
                catch { fputs("Physical export failed: \(error)\n", stderr); exit(1) }
            }
        }
        if let index = arguments.firstIndex(of: "--export-workbench"), arguments.indices.contains(index + 1) {
            store.hidden = true; windows.sync()
            Task { @MainActor in
                do { try await DesignExporter.exportWorkbench(store: store, manager: windows, to: URL(fileURLWithPath: arguments[index + 1])); NSApp.terminate(nil) }
                catch { fputs("Workbench export failed: \(error)\n", stderr); exit(1) }
            }
        }
        if let index = arguments.firstIndex(of: "--export-customization"), arguments.indices.contains(index + 1) {
            store.hidden = true; windows.sync()
            Task { @MainActor in
                do { try await DesignExporter.exportCustomization(store: store, manager: windows, to: URL(fileURLWithPath: arguments[index + 1])); NSApp.terminate(nil) }
                catch { fputs("Customization export failed: \(error)\n", stderr); exit(1) }
            }
        }
        if let exportIndex = arguments.firstIndex(of: "--export-design"), arguments.indices.contains(exportIndex + 1) {
            store.hidden = true; windows.sync()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                Task { @MainActor in
                    do { try await DesignExporter.export(store: self.store, manager: self.windows, to: URL(fileURLWithPath: arguments[exportIndex + 1])); NSApp.terminate(nil) }
                    catch { fputs("Design export failed: \(error)\n", stderr); exit(1) }
                }
            }
        }
    }
    func applicationWillTerminate(_ notification: Notification) { launchPresentation.cancel(); store?.save(); windows?.shutdown(); ShortcutManager.shared.unregister() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { store.hidden = false; windows.sync(); return true }
    private func configureMenu() {
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        status.button?.image = Self.menuClipImage()
        status.button?.target = self
        status.button?.action = #selector(statusClicked(_:))
        status.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        status.button?.toolTip = "屏幕夹子 · 夹住手边的万物"
        let menu = NSMenu()
        add("夹住剪贴板", action: #selector(clipboard), to: menu)
        add("添加文件或文件夹…", action: #selector(addFiles), to: menu)
        add("夹项与恢复…", action: #selector(library), to: menu)
        let scenes = NSMenuItem(title: "工作场景", action: nil, keyEquivalent: "")
        scenes.submenu = sceneMenu; menu.addItem(scenes)
        menu.addItem(.separator())
        add("显示 / 隐藏全部夹子", action: #selector(toggle), to: menu)
        add("撤销取消固定", action: #selector(undoRemove), to: menu)
        menu.addItem(.separator())
        add("设置…", action: #selector(settings), to: menu)
        add("夹子使用指引", action: #selector(guide), to: menu)
        add("重新保存资料库", action: #selector(save), to: menu)
        add("退出屏幕夹子", action: #selector(quit), to: menu, key: "q")
        let feedbackItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        feedbackItem.isHidden = true
        menu.insertItem(feedbackItem, at: 0)
        feedback = store.$message.sink { [weak self, weak feedbackItem] message in
            feedbackItem?.title = message ?? ""
            feedbackItem?.isHidden = message == nil
            self?.status.button?.toolTip = message ?? "屏幕夹子 · 拖入边缘夹子，右键操作"
        }
        statusMenu = menu
        let mainMenu = NSMenu()
        let appMenu = NSMenu(); add("设置…", action: #selector(settings), to: appMenu, key: ","); appMenu.addItem(.separator()); add("退出屏幕夹子", action: #selector(quit), to: appMenu, key: "q")
        let appItem = NSMenuItem(); appItem.submenu = appMenu; mainMenu.addItem(appItem)
        let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let editItem = NSMenuItem(title: "编辑", action: nil, keyEquivalent: ""); editItem.submenu = editMenu; mainMenu.addItem(editItem)
        NSApp.mainMenu = mainMenu
    }
    @objc private func statusClicked(_ sender: NSStatusBarButton) {
        guard let menu = statusMenu else { return }
        sceneMenu.removeAllItems()
        let all = NSMenuItem(title: "全部材料", action: #selector(selectWorkScene(_:)), keyEquivalent: "")
        all.target = self; all.state = store.state.activeSceneID == nil ? .on : .off; sceneMenu.addItem(all)
        for scene in store.state.scenes {
            let entry = NSMenuItem(title: scene.title, action: #selector(selectWorkScene(_:)), keyEquivalent: "")
            entry.target = self; entry.representedObject = scene.id
            entry.state = scene.id == store.state.activeSceneID ? .on : .off; sceneMenu.addItem(entry)
        }
        sceneMenu.addItem(.separator()); add("管理场景…", action: #selector(manageScenes), to: sceneMenu)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.minY - 3), in: sender)
    }
    static func menuClipImage() -> NSImage {
        let image = GeneratedAssets.image("clip-silver").copy() as! NSImage
        image.size = NSSize(width: 25, height: 13)
        image.isTemplate = false
        image.accessibilityDescription = "屏幕夹子，点击或右键打开设置与操作"
        return image
    }
    private func add(_ title: String, action: Selector, to menu: NSMenu, key: String = "") { let item = NSMenuItem(title: title, action: action, keyEquivalent: key); item.target = self; menu.addItem(item) }
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool { menuItem.action == #selector(undoRemove) ? store.undo.canUndo : true }
    @objc func selectWorkScene(_ sender: NSMenuItem) { store.selectScene(sender.representedObject as? UUID) }
    @objc func clipboard() { store.ingest(.general) }
    @objc func addFiles() { store.chooseFiles() }
    @objc func library() { windows.showLibrary() }
    @objc func toggle() { windows.toggleVisibility() }
    @objc func undoRemove() { store.undo.undo(); windows.sync() }
    @objc func manageScenes() { windows.showSettings(section: "工作场景") }
    @objc func settings() { windows.showSettings() }
    @objc func guide() { windows.showGuide() }
    @objc func save() { store.save() }
    @objc func quit() { NSApp.terminate(nil) }

    func installDemo() {
        do {
            let project = store.storage.root.appendingPathComponent("论文项目", isDirectory: true)
            try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
            try Data("屏幕夹子示例文档。\n所有演示内容都在独立资料库里。".utf8).write(to: project.appendingPathComponent("研究笔记.txt"))
            try FileManager.default.createDirectory(at: project.appendingPathComponent("配图", isDirectory: true), withIntermediateDirectories: true)
            store.importFiles([project, project.appendingPathComponent("研究笔记.txt")])
            if let folder = store.active.first { store.update(folder.id) { $0.note = "论文材料，随时打开"; $0.tags = ["论文", "常用"] } }
            store.addTextOrLink("周五前完成方法章节。\n\n核对引用、整理配图，再把材料拖到邮件里。\n\n用金属夹移动卡片，用内容把手交接材料。")
            store.addTextOrLink("https://developer.apple.com/documentation/appkit")
            let image = DesignExporter.demoImage()
            var picture = ClipItem(kind: .image, title: "参考截图 · 交互草图")
            picture.assetName = picture.id.uuidString + ".png"; picture.note = "边看边写，保持原始比例"; picture.tags = ["参考"]
            picture.placement.mode = .floating
            if let screen = NSScreen.main { picture.placement.position.screenID = screen.stableID }
            picture.placement.position.x = 0.42; picture.placement.position.y = 0.45
            if let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]), let name = picture.assetName { try png.write(to: store.storage.assetURL(name)); store.state.items.append(picture); store.images[picture.id] = image }
            store.createGroup(Set(store.active.map(\.id)), title: "论文 · 本周工作")
            store.message = nil; store.save()
        } catch { store.notify("演示内容创建失败：\(error.localizedDescription)") }
    }
}
