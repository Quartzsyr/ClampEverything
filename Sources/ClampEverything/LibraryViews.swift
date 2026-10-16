import SwiftUI
import AppKit
import Carbon
import ClampCore

struct LibraryView: View {
    @ObservedObject var store: ClipStore
    let manager: WindowManager
    @State private var query = ""
    @State private var scope = "全部"
    @State private var selected: Set<UUID> = []
    var filtered: [ClipItem] {
        let items = scope == "恢复区" ? store.recovery : store.active
        return items.filter { item in
            item.matches(query) && (scope == "全部" || scope == "恢复区" || item.kind.title == scope || item.groupID?.uuidString == scope)
        }
    }
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) { MetalClip(); VStack(alignment: .leading, spacing: 3) { Text("屏幕夹子").font(.system(size: 17, weight: .semibold)); Text("夹住手边的万物").font(.system(size: 10)).foregroundStyle(.secondary) } }.padding(.bottom, 20)
                sidebar("全部", symbol: "square.stack.3d.up", count: store.active.count)
                ForEach(ClipKind.allCases, id: \.rawValue) { kind in sidebar(kind.title, symbol: kind.symbol, count: store.active.filter { $0.kind == kind }.count) }
                Divider().padding(.vertical, 10)
                Text("项目夹").font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                ScrollView {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(store.state.groups) { group in
                            Button { scope = group.id.uuidString; selected = [] } label: { HStack { Image(systemName: "square.stack"); Text(group.title).lineLimit(1); Spacer(); Text("\(store.members(group.id).count)").foregroundStyle(.secondary) }.padding(8).background(scope == group.id.uuidString ? ClipStyle.accent.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 6)) }.buttonStyle(.plain)
                                .contextMenu { Button("编辑名称") { manager.edit(group.id) }; Button("展开项目夹") { manager.reveal(group.id) }; Button("解散（保留成员）") { store.dissolve(group.id); scope = "全部" } }
                        }
                    }
                }
                Spacer(minLength: 8)
                sidebar("恢复区", symbol: "arrow.uturn.backward", count: store.recovery.count)
                Button("设置", systemImage: "gearshape") { manager.showSettings() }.buttonStyle(.plain).padding(8)
            }.font(.system(size: 12)).padding(17).frame(width: 185).frame(maxHeight: .infinity, alignment: .top).background(.regularMaterial)
            Divider()
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(store.state.groups.first { $0.id.uuidString == scope }?.title ?? scope).font(.system(size: 25, weight: .semibold))
                        Text(scope == "恢复区" ? "取消固定的内容保留 7 天；清理不会删除原文件。" : "常用入口与当前材料，一起留在手边。 ").font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    ScenePicker(store: store).controlSize(.small)
                    Button { store.ingest(.general) } label: { Label("夹住剪贴板", systemImage: "clipboard") }.keyboardShortcut("v", modifiers: [.command, .shift])
                    Button { store.chooseFiles() } label: { Image(systemName: "plus") }.help("添加文件或文件夹").keyboardShortcut("o", modifiers: .command)
                }
                TextField("搜索名称、备注、标签或内容", text: $query).textFieldStyle(.roundedBorder)
                if let message = store.message {
                    HStack(alignment: .top) { Image(systemName: "info.circle"); Text(message).textSelection(.enabled); Spacer(); if store.writable { Button { store.message = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain) } }.font(.system(size: 11)).padding(10).background(ClipStyle.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
                }
                if filtered.isEmpty {
                    VStack(spacing: 15) {
                        Image(systemName: query.isEmpty ? "paperclip" : "magnifyingglass").font(.system(size: 44, weight: .ultraLight)).foregroundStyle(ClipStyle.accent)
                        Text(query.isEmpty ? (scope == "恢复区" ? "恢复区是空的" : "把常用的东西夹在手边") : "没有找到匹配的夹项").font(.system(size: 18, weight: .medium))
                        Text(query.isEmpty ? "拖文件到屏幕右侧的「＋夹住」区域。\n也可以复制图片、文字或链接，再点「夹住剪贴板」。" : "试试文件名、用途备注或分类标签。 ").font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center).lineSpacing(5)
                        if scope != "恢复区" && query.isEmpty { Button("添加文件或文件夹…") { store.chooseFiles() }.buttonStyle(.borderedProminent) }
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(selection: $selected) {
                        ForEach(filtered) { item in
                            HStack(spacing: 11) {
                                ClipIcon(item: item, size: 35)
                                VStack(alignment: .leading, spacing: 5) {
                                    HStack { Text(item.title).font(.system(size: 13, weight: .medium)); if item.placement.mode == .floating { Text("常驻").font(.system(size: 9)).padding(.horizontal, 5).padding(.vertical, 2).background(ClipStyle.accent.opacity(0.12), in: Capsule()) } }
                                    Text(item.note.isEmpty ? (item.link ?? item.originalPath ?? item.kind.title) : item.note).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                                    if let expiry = item.expiresAt() { Text("保留至 " + expiry.formatted(date: .abbreviated, time: .shortened)).font(.system(size: 10)).foregroundStyle(.secondary) }
                                    else if !item.tags.isEmpty || item.groupID != nil { Text(([item.groupID.flatMap { store.group($0)?.title }].compactMap { $0 } + item.tags).joined(separator: " · ")).font(.system(size: 10)).foregroundStyle(ClipStyle.accent) }
                                }
                                Spacer()
                                if scope == "恢复区" { Button("恢复") { store.restore(item.id) } }
                                else {
                                    Button { manager.reveal(item.id) } label: { Image(systemName: "eye") }.help("展开查看")
                                    Button { manager.edit(item.id) } label: { Image(systemName: "tag") }.help("编辑名称与备注")
                                    Button { manager.float(item.id) } label: { Image(systemName: "arrow.up.left.and.arrow.down.right") }.help("拉出常驻")
                                }
                            }.padding(.vertical, 7).tag(item.id).accessibilityElement(children: .contain)
                                .contextMenu {
                                    if scope != "恢复区" {
                                        Button("打开") { store.open(item) }.disabled(item.kind == .text)
                                        Button("复制") { store.copy(item) }
                                        Button("上移") { store.reorder(item.id, by: -1) }; Button("下移") { store.reorder(item.id, by: 1) }
                                        if item.groupID != nil { Button("移出项目组") { store.update(item.id) { $0.groupID = nil } } }
                                        Button("取消固定") { store.remove(item.id) }
                                    }
                                }
                        }
                    }.listStyle(.inset).background(ClipStyle.paper, in: RoundedRectangle(cornerRadius: 8))
                }
                if scope != "恢复区" {
                    HStack {
                        Text(selected.isEmpty ? "⌘ / ⇧ 点击选择多项" : "已选择 \(selected.count) 项").font(.system(size: 11)).foregroundStyle(.secondary)
                        Spacer()
                        Button("夹成项目组") {
                            store.createGroup(selected)
                            if let group = store.state.groups.last { manager.edit(group.id) }
                            selected = []
                        }.disabled(selected.isEmpty)
                        Menu("加入项目组") { ForEach(store.state.groups) { group in Button(group.title) { for id in selected { store.update(id) { $0.groupID = group.id } }; selected = [] } } }.disabled(selected.isEmpty || store.state.groups.isEmpty)
                        Button("取消固定") { for id in selected { store.remove(id) }; selected = [] }.disabled(selected.isEmpty)
                    }.controlSize(.small)
                }
            }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
        }.background(Color(nsColor: .windowBackgroundColor)).tint(ClipStyle.accent).frame(minWidth: 760, minHeight: 500)
            .onChange(of: scope) { _, _ in selected = [] }
    }
    func sidebar(_ title: String, symbol: String, count: Int) -> some View {
        Button { scope = title } label: { HStack(spacing: 9) { Image(systemName: symbol).frame(width: 16); Text(title); Spacer(); Text("\(count)").font(.system(size: 10)).foregroundStyle(.secondary) }.padding(8).background(scope == title ? ClipStyle.accent.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 6)) }.buttonStyle(.plain)
    }
}

struct EditorView: View {
    @ObservedObject var store: ClipStore
    let id: UUID
    var done: () -> Void
    @State private var title = ""
    @State private var note = ""
    @State private var tags = ""
    @State private var text = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { MetalClip(); Text("名称与用途备注").font(.system(size: 18, weight: .medium)) }
            Text("这些改动只保存在屏幕夹子里。原文件名和 Finder 标签保持不变。").font(.system(size: 11)).foregroundStyle(.secondary)
            TextField("显示名称", text: $title).textFieldStyle(.roundedBorder)
            if store.item(id) != nil {
                TextField("用途备注，例如：周五前交给财务", text: $note).textFieldStyle(.roundedBorder)
                TextField("分类标签，以逗号分隔", text: $tags).textFieldStyle(.roundedBorder)
                if store.item(id)?.kind == .text {
                    Text("文字副本").font(.system(size: 11)).foregroundStyle(.secondary)
                    TextEditor(text: $text).font(.system(size: 13)).frame(minHeight: 100).overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.secondary.opacity(0.2)))
                }
            }
            Spacer(minLength: 0)
            HStack { Button("取消") { done() }.keyboardShortcut(.cancelAction); Spacer(); Button("保存") { save(); done() }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
        }.padding(24).tint(ClipStyle.accent).onAppear {
            if let item = store.item(id) { title = item.title; note = item.note; tags = item.tags.joined(separator: ", "); text = item.text ?? "" }
            else { title = store.group(id)?.title ?? "" }
        }
    }
    func save() {
        let cleaned = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if store.item(id) != nil {
            store.update(id) { item in
                item.title = cleaned; item.note = note
                var seen: Set<String> = []
                item.tags = tags.components(separatedBy: CharacterSet(charactersIn: ",，")).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty && seen.insert($0).inserted }
                if item.kind == .text { item.text = text }
            }
        } else { store.updateGroup(id) { $0.title = cleaned } }
        store.save()
    }
}

struct SettingsView: View {
    @ObservedObject var store: ClipStore
    let manager: WindowManager
    @State private var shortcutError: String?
    @State private var section = "使用习惯"
    private let sampleID = UUID(uuidString: "869296C5-CC21-47C4-85AE-1F4549763260")!
    init(store: ClipStore, manager: WindowManager, initialSection: String = "使用习惯") {
        self.store = store; self.manager = manager
        _section = State(initialValue: initialSection)
    }
    var body: some View {
        HStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 10) {
                MetalClip(receiver: true).rotationEffect(.degrees(-12)).padding(.top, 18).padding(.bottom, 8)
                Text("屏幕夹子").font(.system(size: 20, weight: .semibold))
                Text("留一点空间，\n给手边的东西。").font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(5).padding(.bottom, 26)
                ScrollView {
                    VStack(spacing: 7) {
                navigation("使用习惯", symbol: "slider.horizontal.3")
                navigation("鼠标夹取", symbol: "cursorarrow.click")
                navigation("内容大小", symbol: "arrow.up.left.and.arrow.down.right")
                navigation("夹子与材质", symbol: "sparkles")
                navigation("能夹什么", symbol: "square.stack.3d.up")
                navigation("工作场景", symbol: "rectangle.3.group")
                navigation("资料与恢复", symbol: "arrow.uturn.backward")
                navigation("开发者信息", symbol: "person.crop.circle")
                    }
                }.scrollIndicators(.hidden)
                Spacer(minLength: 0)
                Text("只在需要时打开设置").font(.system(size: 10)).foregroundStyle(.tertiary)
            }.frame(width: 150).padding(20)
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text(section).font(.system(size: 25, weight: .medium))
                    Spacer()
                    Button { manager.settingsWindow?.close() } label: { Image(systemName: "xmark").font(.system(size: 11, weight: .semibold)).frame(width: 28, height: 28).background(.quaternary, in: Circle()) }.buttonStyle(.plain).help("关闭设置").keyboardShortcut(.cancelAction)
                }
                if section == "使用习惯" { habits }
                else if section == "鼠标夹取" { HoldSettingsView(store: store, controller: manager.pointClamp) }
                else if section == "内容大小" { previewSizes }
                else if section == "夹子与材质" { materials }
                else if section == "能夹什么" { ScrollView { MaterialCatalogView(store: store).padding(.trailing, 6) } }
                else if section == "工作场景" { SceneSettingsView(store: store) }
                else if section == "开发者信息" { developerInfo }
                else { storage }
                Spacer(minLength: 0)
            }.padding(.vertical, 30).padding(.trailing, 28).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .settingsGlass()
        .overlay(alignment: .top) { MetalClip().rotationEffect(.degrees(90)).offset(y: -8).allowsHitTesting(false) }
        .padding(18)
        .frame(minWidth: 680, minHeight: 500)
        .tint(ClipStyle.accent)
    }
    func navigation(_ title: String, symbol: String) -> some View {
        Button { section = title } label: {
            Label(title, systemImage: symbol).font(.system(size: 12, weight: section == title ? .semibold : .regular))
                .frame(maxWidth: .infinity, alignment: .leading).padding(11)
                .background(section == title ? Color.primary.opacity(0.07) : .clear, in: RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(.plain)
    }
    private func preference<Value>(_ keyPath: WritableKeyPath<AppPreferences, Value>) -> Binding<Value> {
        Binding(get: { store.state.preferences[keyPath: keyPath] }, set: {
            store.state.preferences[keyPath: keyPath] = $0
            store.changed(immediate: true)
        })
    }
    var developerInfo: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Quartz").font(.system(size: 22, weight: .semibold))
                Text("UESTC").font(.system(size: 13)).foregroundStyle(.secondary)
            }
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Text("联系邮箱").font(.system(size: 12)).foregroundStyle(.secondary)
                Link("SYRQuartz@gmail.com", destination: URL(string: "mailto:SYRQuartz@gmail.com")!)
                    .font(.system(size: 14))
                    .help("使用邮件应用联系开发者")
            }
        }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    var habits: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("调整夹子的停靠与展开方式，修改后立即生效。").font(.system(size: 12)).foregroundStyle(.secondary)
                Toggle("显示黄铜接收夹", isOn: preference(\.showBrassClip))
                Text("屏幕右上角的添加入口，默认关闭；关闭后仍可从菜单栏添加内容。")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                Toggle("全屏时隐藏夹子", isOn: Binding(get: { store.state.preferences.hideInFullScreen }, set: { store.state.preferences.hideInFullScreen = $0; store.changed(immediate: true); manager.detectFullScreen() }))
                Toggle("显示文件夹里的隐藏文件", isOn: preference(\.showHiddenFiles))
                Picker("新夹子默认停靠", selection: preference(\.defaultSide)) {
                    Text("左侧").tag(ClipSide.left); Text("右侧").tag(ClipSide.right)
                }
                Divider()
                Toggle("靠近边缘自动吸附", isOn: preference(\.autoSnap))
                settingSlider("吸附距离", value: preference(\.snapDistance), range: 16...96, label: "\(Int(store.state.preferences.snapDistance)) 点")
                    .disabled(!store.state.preferences.autoSnap)
                Toggle("悬停时展开夹子", isOn: preference(\.hoverToExpand))
                settingSlider("悬停等待", value: preference(\.hoverDelay), range: 0.1...1.2, label: String(format: "%.2f 秒", store.state.preferences.hoverDelay))
                    .disabled(!store.state.preferences.hoverToExpand)
                Text("关闭悬停展开后，单击金属夹查看；关闭吸附后，拖动的卡片停留在桌面。").font(.system(size: 10)).foregroundStyle(.secondary)
                Divider()
                Text("显示 / 隐藏快捷键").font(.system(size: 12, weight: .medium))
                HStack {
                    ShortcutRecorder(label: store.state.preferences.shortcut?.label ?? "点击后按组合键", record: { shortcut in
                        if store.state.preferences.holdToClampEnabled && store.state.preferences.holdShortcut.conflicts(with: shortcut) { shortcutError = "与鼠标夹取按键冲突，请换一个组合。"; return }
                        if let error = ShortcutManager.shared.register(shortcut, action: { manager.toggleVisibility() }) { shortcutError = error }
                        else { shortcutError = nil; store.state.preferences.shortcut = shortcut; store.changed(immediate: true) }
                    }).frame(width: 220, height: 30)
                    Button("清除") { ShortcutManager.shared.unregister(); store.state.preferences.shortcut = nil; store.changed(immediate: true) }
                }
                if let shortcutError { Text(shortcutError).font(.system(size: 10)).foregroundStyle(.orange) }
                HStack {
                    Button("查看夹子指引") { manager.showGuide() }
                    Spacer()
                    Button("恢复交互默认值") {
                        let defaults = AppPreferences()
                        store.state.preferences.showBrassClip = defaults.showBrassClip
                        store.state.preferences.autoSnap = defaults.autoSnap
                        store.state.preferences.snapDistance = defaults.snapDistance
                        store.state.preferences.hoverToExpand = defaults.hoverToExpand
                        store.state.preferences.hoverDelay = defaults.hoverDelay
                        store.state.preferences.defaultSide = defaults.defaultSide
                        store.changed(immediate: true)
                    }
                }.controlSize(.small)
            }.toggleStyle(.switch).controlSize(.small).font(.system(size: 12)).padding(.trailing, 6)
        }
    }
    func settingSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, label: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack { Text(title); Spacer(); Text(label).monospacedDigit().foregroundStyle(.secondary) }
            Slider(value: value, in: range).accessibilityLabel(title)
        }.font(.system(size: 11))
    }
    var previewSizes: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("分别调整每种内容展开后的大小，立即生效并自动保存。PDF 和文稿默认已放大；夹子的金属部分保持原有大小。")
                    .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                ForEach(PreviewSizeKind.allCases, id: \.self) { kind in
                    settingSlider(kind.title, value: Binding(
                        get: { store.state.preferences.previewSizes[kind] },
                        set: { store.state.preferences.previewSizes[kind] = $0; store.changed(immediate: true) }),
                        range: PreviewSizes.range,
                        label: String(format: "%.0f%%", store.state.preferences.previewSizes[kind] * 100))
                }
                Text("65%–180% · 保留图片和纸页比例，超出屏幕时自动缩小。仅调整展开的内容，侧边缩略图保持统一。")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                Button("恢复全部内容默认大小") {
                    store.state.preferences.previewSizes = PreviewSizes(); store.changed(immediate: true)
                }.controlSize(.small)
            }.padding(.trailing, 6)
        }
    }
    var materials: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 17) {
                Text("文件夹有封面，文字有纸张；每种内容都有自己的形态。").font(.system(size: 12)).foregroundStyle(.secondary)
                HStack(spacing: 16) {
                    ZStack(alignment: .topTrailing) {
                        FolderMaterial(tint: store.state.preferences.folderTint, title: "项目资料")
                        VStack(alignment: .leading, spacing: 8) {
                            Label("参考图片", systemImage: "folder.fill")
                            Label("研究笔记.txt", systemImage: "doc.text")
                        }.font(.system(size: 11)).padding(18).padding(.top, 30).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        MetalClip().scaleEffect(0.75).offset(x: 4, y: 7)
                    }
                    ZStack(alignment: .topTrailing) {
                        PaperMaterial(id: sampleID, stock: store.state.preferences.noteStock)
                        VStack(alignment: .leading, spacing: 9) {
                            Text("手边的文字").font(.system(size: 14, weight: .medium))
                            Text("一点纹理，一道折痕。\n留住刚刚复制的灵感。").font(.system(size: 11)).lineSpacing(6)
                        }.padding(16).padding(.top, 15).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        MetalClip().scaleEffect(0.75).offset(x: 4, y: 7)
                    }
                }.frame(height: 155).environment(\.colorScheme, .light)
                Picker("文件夹配色", selection: preference(\.folderTint)) {
                    ForEach(FolderTint.allCases, id: \.self) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented)
                Picker("文字纸张", selection: preference(\.noteStock)) {
                    ForEach(NoteStock.allCases, id: \.self) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented)
                Text("左：文件夹封面 · 右：文字 / 剪贴板纸张").font(.system(size: 10)).foregroundStyle(.secondary)
                Divider()
                settingSlider("卡片动效强度", value: preference(\.motionIntensity), range: 0...1.5,
                    label: store.state.preferences.motionIntensity == 0 ? "关闭" : String(format: "%.0f%%", store.state.preferences.motionIntensity * 100))
                Toggle("触控板轻触反馈", isOn: preference(\.tactileFeedback)).toggleStyle(.switch).controlSize(.small).font(.system(size: 11))
                Text("夹紧、合并、抽出与吸附时轻触反馈，需要支持触感的设备。默认关闭。").font(.system(size: 10)).foregroundStyle(.secondary)
                Text("所有类型都有拖动惯性与松手回摆，软材质还会弯曲；系统的减少动态效果优先生效。").font(.system(size: 10)).foregroundStyle(.secondary).lineSpacing(3)
                Divider()
                Button("查看所有支持类型与拖动示例") { section = "能夹什么" }.controlSize(.small)
                Divider()
                Button("恢复材质默认值") {
                    store.state.preferences.folderTint = .kraft
                    store.state.preferences.noteStock = .natural
                    store.state.preferences.motionIntensity = 1
                    store.state.preferences.tactileFeedback = false
                    store.changed(immediate: true)
                }.controlSize(.small)
            }.padding(.trailing, 6)
        }
    }
    var storage: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { Text("本地保存，无需账号。").font(.system(size: 12)); Spacer(); Button("打开资料夹") { NSWorkspace.shared.open(store.storage.root) }.controlSize(.small) }
            Text("主动夹入，不记录剪贴板历史。取消固定不会删除原文件；内部副本保留 7 天。").font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(4)
            Divider()
            Text("恢复夹项").font(.system(size: 13, weight: .medium))
            ScrollView {
                VStack(spacing: 10) {
                    if store.recovery.isEmpty { Text("没有需要恢复的夹项").font(.system(size: 12)).foregroundStyle(.secondary).padding(.vertical, 35) }
                    ForEach(store.recovery) { item in
                        HStack { ClipIcon(item: item, size: 22); Text(item.title).font(.system(size: 12)).lineLimit(1); Spacer(); Button("恢复") { store.restore(item.id) }.controlSize(.small) }.padding(10).background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
            if let message = store.message { Text(message).font(.system(size: 10)).foregroundStyle(.secondary).textSelection(.enabled) }
        }
    }
}

struct ShortcutRecorder: NSViewRepresentable {
    var label: String
    var record: (Shortcut) -> Void
    func makeNSView(context: Context) -> ShortcutField { let view = ShortcutField(); view.record = record; view.stringValue = label; view.savedLabel = label; return view }
    func updateNSView(_ view: ShortcutField, context: Context) { view.record = record; view.savedLabel = label; if !view.recording { view.stringValue = label } }
}
final class ShortcutField: NSTextField {
    var record: (Shortcut) -> Void = { _ in }
    var recording = false
    var savedLabel = "点击后按组合键"
    override init(frame frameRect: NSRect) { super.init(frame: frameRect); isEditable = false; isSelectable = false; isBezeled = true; alignment = .center; focusRingType = .exterior; font = .systemFont(ofSize: 12) }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
    override var acceptsFirstResponder: Bool { true }
    override func mouseDown(with event: NSEvent) { recording = true; stringValue = "按组合键 · Esc 取消"; window?.makeFirstResponder(self) }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { recording = false; stringValue = savedLabel; window?.makeFirstResponder(nil); return }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard !flags.intersection([.command, .option, .control]).isEmpty else { NSSound.beep(); return }
        var modifiers: UInt32 = 0; var text = ""
        if flags.contains(.control) { modifiers |= UInt32(controlKey); text += "⌃" }
        if flags.contains(.option) { modifiers |= UInt32(optionKey); text += "⌥" }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey); text += "⇧" }
        if flags.contains(.command) { modifiers |= UInt32(cmdKey); text += "⌘" }
        text += (event.charactersIgnoringModifiers ?? "键 \(event.keyCode)").uppercased()
        recording = false; record(Shortcut(keyCode: UInt32(event.keyCode), modifiers: modifiers, label: text)); window?.makeFirstResponder(nil)
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool { guard recording else { return false }; keyDown(with: event); return true }
}
