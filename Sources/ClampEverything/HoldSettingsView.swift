import AppKit
import SwiftUI
import ClampCore

struct HoldSettingsView: View {
    @ObservedObject var store: ClipStore
    @ObservedObject var controller: PointClampController
    @State private var error: String?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 17) {
                Text("按住变成夹子，按下夹紧，拖动后松手放置。").font(.system(size: 12)).foregroundStyle(.secondary)
                Toggle("启用鼠标夹取", isOn: Binding(get: { store.state.preferences.holdToClampEnabled }, set: {
                    store.state.preferences.holdToClampEnabled = $0; store.changed(immediate: true)
                })).toggleStyle(.switch).controlSize(.small)
                HStack(spacing: 12) {
                    MetalClip(opened: true)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("按住的键").font(.system(size: 12, weight: .medium))
                        HoldKeyRecorder(label: store.state.preferences.holdShortcut.label,
                            recordingChanged: { controller.setRecording($0) }, record: save)
                            .frame(width: 210, height: 32)
                    }
                }
                HStack {
                    Button("⌥ Option") { save(.option) }
                    Button("⌃⌥") { save(HoldShortcut(modifiers: (1 << 18) | (1 << 19), label: "⌃⌥")) }
                }.controlSize(.small)
                Text(error ?? "支持单键、仅修饰键或组合键。录制后松开；Esc 取消。单字母键启用后会占用该键，建议使用 Option。").font(.system(size: 10)).foregroundStyle(error == nil ? Color.secondary : .orange).lineSpacing(3)
                VStack(alignment: .leading, spacing: 7) {
                    Label("按住按键：夹子张开，停留后目标边缘泛起柔光", systemImage: "1.circle")
                    Label("按下鼠标：读取内容，显示名称或图片预览", systemImage: "2.circle")
                    Label("保持按键拖动：边缘提示吸附，桌面提示放置", systemImage: "3.circle")
                    Label("松开鼠标：放下夹项；Esc / 右键随时取消", systemImage: "4.circle")
                }.font(.system(size: 10)).foregroundStyle(.secondary)
                Text("文字暖白逐行勾亮，图片冷蓝贴边，链接薄荷底光，文件夹琥珀边光，文件淡紫角光。移动时降低光效并收起提示，停稳后亮起；移出对象清除。文字逐行边界不可用时退回选区或对象外框。瞄准不截图。")
                    .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Divider()
                Label(controller.status, systemImage: controller.running ? "checkmark.circle" : "hand.point.up.left").font(.system(size: 11)).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button(ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27 ? "允许设备控制与数据访问…" : "允许辅助功能…") { controller.requestAccessibility() }
                    Button("重新检查") { controller.refreshConfiguration() }
                }.controlSize(.small)
                Button("允许图片区域截图…") { controller.requestScreenCapture() }.controlSize(.small)
                Text("文件保留原位置；选中文字优先于网页链接。图标与图片无法提供原件时，在按下后读取其可见区域，读取完成后即可带着预览拖走，不会在放下时重新截图。密码输入框不夹取。").font(.system(size: 10)).foregroundStyle(.secondary).lineSpacing(3)
                Text("授权后自动启动，无需反复点击重新检查。若更新后仍提示未授权，请在系统设置中重新开启屏幕夹子的辅助功能。拖到屏幕左右边缘自动吸附；拖动夹子可调整高度或拉回桌面。Esc 或右键取消；每次夹取后松开再按。").font(.system(size: 10)).foregroundStyle(.secondary)
            }.padding(.trailing, 4)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in controller.refreshConfiguration() }
        .onDisappear { controller.setRecording(false) }
    }
    private func save(_ shortcut: HoldShortcut) {
        guard shortcut.isValid else { error = "请选择有效的按键，Esc 用于取消。"; return }
        if let toggle = store.state.preferences.shortcut, shortcut.conflicts(with: toggle) { error = "与显示 / 隐藏快捷键相同，请换一个组合。"; return }
        error = nil; store.state.preferences.holdShortcut = shortcut; store.changed(immediate: true)
    }
}

struct HoldKeyRecorder: NSViewRepresentable {
    let label: String
    var recordingChanged: (Bool) -> Void
    var record: (HoldShortcut) -> Void
    func makeNSView(context: Context) -> HoldKeyField { let view = HoldKeyField(); configure(view); return view }
    func updateNSView(_ view: HoldKeyField, context: Context) { configure(view) }
    private func configure(_ view: HoldKeyField) {
        view.record = record; view.recordingChanged = recordingChanged; view.savedLabel = label
        if !view.recording { view.stringValue = label }
    }
}

final class HoldKeyField: NSTextField {
    var record: (HoldShortcut) -> Void = { _ in }
    var recordingChanged: (Bool) -> Void = { _ in }
    private(set) var recording = false
    var savedLabel = "⌥ Option"
    private var candidate: UInt64 = 0
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect); isEditable = false; isSelectable = false; isBezeled = true
        alignment = .center; font = .systemFont(ofSize: 12); focusRingType = .exterior
        setAccessibilityLabel("录制鼠标夹取按键")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
    override var acceptsFirstResponder: Bool { true }
    override func mouseDown(with event: NSEvent) {
        recording = true; candidate = 0; recordingChanged(true)
        stringValue = "按下单键或组合键…"; window?.makeFirstResponder(self)
    }
    override func flagsChanged(with event: NSEvent) {
        guard recording else { super.flagsChanged(with: event); return }
        let flags = UInt64(event.modifierFlags.rawValue) & HoldShortcut.modifierMask
        if flags.nonzeroBitCount > candidate.nonzeroBitCount { candidate = flags }
        if flags == 0, candidate != 0 { finish(HoldShortcut(modifiers: candidate, label: Self.modifierLabel(candidate))) }
        else { stringValue = Self.modifierLabel(candidate) + " · 松开保存" }
    }
    override func keyDown(with event: NSEvent) {
        guard recording else { return }
        if event.keyCode == 53 { finish(nil); return }
        guard !event.isARepeat else { return }
        let flags = UInt64(event.modifierFlags.rawValue) & HoldShortcut.modifierMask
        let keyLabel: String
        switch event.keyCode {
        case 49: keyLabel = "Space"
        case 36: keyLabel = "Return"
        case 48: keyLabel = "Tab"
        case 51: keyLabel = "Delete"
        case 123: keyLabel = "←"
        case 124: keyLabel = "→"
        case 125: keyLabel = "↓"
        case 126: keyLabel = "↑"
        default: keyLabel = event.charactersIgnoringModifiers?.uppercased() ?? "Key \(event.keyCode)"
        }
        finish(HoldShortcut(keyCode: event.keyCode, modifiers: flags, label: Self.modifierLabel(flags) + keyLabel))
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool { guard recording else { return false }; keyDown(with: event); return true }
    override func resignFirstResponder() -> Bool {
        if recording { recording = false; recordingChanged(false); stringValue = savedLabel }
        return super.resignFirstResponder()
    }
    private func finish(_ shortcut: HoldShortcut?) {
        recording = false; recordingChanged(false)
        if let shortcut { record(shortcut) }
        stringValue = savedLabel; window?.makeFirstResponder(nil)
    }
    private static func modifierLabel(_ flags: UInt64) -> String {
        [(18, "⌃"), (19, "⌥"), (17, "⇧"), (20, "⌘"), (23, "fn")].compactMap { flags & (1 << $0.0) != 0 ? $0.1 : nil }.joined()
    }
}
