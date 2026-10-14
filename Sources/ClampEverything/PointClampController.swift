import AppKit
import SwiftUI
import ApplicationServices
import Combine
import Carbon
import ClampCore
import UniformTypeIdentifiers

enum PointClampCursorGeometry {
    static let size = NSSize(width: 64, height: 46)
    // The ImageGen sprite has its clamping mouth on the left, with five points of padding.
    static let hotspot = NSPoint(x: 5, y: 23)
    static func frame(at point: CGPoint) -> NSRect {
        NSRect(x: point.x - hotspot.x, y: point.y - hotspot.y, width: size.width, height: size.height)
    }
}

@MainActor final class PointClampController: ObservableObject {
    @Published private(set) var status = "未启用"
    @Published private(set) var running = false
    let store: ClipStore
    var onPlace: ((UUID, CGPoint) -> Void)?
    private var targetTask: Task<PreparedPointTarget, Error>?
    private var previewTask: Task<Void, Never>?
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var configured: HoldShortcut?
    private var gesture = HoldGestureState()
    private let cursorPanel = FloatingPanel()
    private let cursorPose = CursorClipPose()
    private let cursorVisibility = CursorVisibilityLease()
    private var previousApplication: NSRunningApplication?
    private var acquiringForeground = false
    private var parkedWindows: [NSWindow] = []
    private var watchdog: Timer?
    private var configurationTimer: Timer?
    private var isCapturing = false
    private var captureGeneration = 0
    private var captureTask: Task<Void, Never>?
    private var consumedMouse = false
    private var consumedEscape = false
    private var consumedRight = false
    private var pressPoint: CGPoint?
    private var recording = false
    private var notices: [NSObjectProtocol] = []
    private let pickupPanel = FloatingPanel()
    private let feedbackPanel = FloatingPanel()
    private var feedbackWork: DispatchWorkItem?
    init(store: ClipStore) {
        self.store = store
        pickupPanel.ignoresMouseEvents = true
        pickupPanel.level = .screenSaver
        pickupPanel.contentView = NSHostingView(rootView: PickupHintView(pose: cursorPose))
        feedbackPanel.ignoresMouseEvents = true
        cursorPanel.ignoresMouseEvents = true
        cursorPanel.level = .screenSaver
        cursorPanel.setAccessibilityElement(false)
        cursorPanel.contentView = NSHostingView(rootView: CursorClipView(pose: cursorPose).frame(width: 64, height: 46))
        for name in [NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.willSleepNotification] {
            notices.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.cancelGesture() }
            })
        }
        notices.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.cancelGesture() }
        })
        notices.append(NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.cursorVisibility.acquired, self.gesture.active, !self.isCapturing else { return }
                self.cancelGesture()
            }
        })
        notices.append(NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshConfiguration() }
        })
        // Granting Accessibility in System Settings doesn't necessarily activate
        // this accessory app. Retry without requiring a settings tab to be open.
        configurationTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.store.state.preferences.holdToClampEnabled else { return }
                self.refreshConfiguration()
            }
        }
        refreshConfiguration()
    }
    func refreshConfiguration() {
        guard store.state.preferences.holdToClampEnabled else { stop(); status = "未启用"; return }
        guard AXIsProcessTrusted() else { stop(); status = "系统尚未授权当前运行版本。若开关已开，请重新关联本版本；授权后自动启动"; return }
        guard !IsSecureEventInputEnabled() else { stop(); status = "安全输入正在使用，结束后自动恢复鼠标夹取"; return }
        let shortcut = store.state.preferences.holdShortcut
        guard shortcut.isValid else { stop(); status = "请重新录制夹取按键"; return }
        if let toggle = store.state.preferences.shortcut, shortcut.conflicts(with: toggle) {
            stop(); status = "与显示 / 隐藏快捷键冲突，请更换夹取按键"; return
        }
        if let tap, configured == shortcut, CFMachPortIsValid(tap) {
            if !CGEvent.tapIsEnabled(tap: tap) { cancelGesture(); CGEvent.tapEnable(tap: tap, enable: true) }
            if CGEvent.tapIsEnabled(tap: tap) { return }
        }
        stop(); configured = shortcut
        let types: [CGEventType] = [.flagsChanged, .keyDown, .keyUp, .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .mouseMoved, .leftMouseDragged]
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: mask, callback: { _, type, event, info in
            guard let info else { return Unmanaged.passUnretained(event) }
            return MainActor.assumeIsolated {
                let controller = Unmanaged<PointClampController>.fromOpaque(info).takeUnretainedValue()
                return controller.receive(type: type, event: event) ? nil : Unmanaged.passUnretained(event)
            }
        }, userInfo: Unmanaged.passUnretained(self).toOpaque())
        guard let tap else { status = "监听未启动，请检查辅助功能权限（重新构建后可能需重新授权）；正在自动重试"; return }
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        guard CGEvent.tapIsEnabled(tap: tap) else { stop(); status = "系统未允许键鼠监听启动，正在自动重试"; return }
        running = true; status = "按住 \(shortcut.label)，点击要夹住的内容"
    }
    func setRecording(_ value: Bool) { recording = value; cancelGesture() }
    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") { NSWorkspace.shared.open(url) }
    }
    func requestScreenCapture() {
        _ = CGRequestScreenCaptureAccess()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") { NSWorkspace.shared.open(url) }
    }
    private func receive(type: CGEventType, event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            cancelGesture()
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        }
        if type == .mouseMoved || type == .leftMouseDragged {
            if gesture.active, !isCapturing { moveCursor(at: event.location); presentCursorWithoutPointer() }
            return consumedMouse
        }
        if type == .leftMouseUp, consumedMouse {
            consumedMouse = false
            let point = pressPoint; pressPoint = nil
            if gesture.active, let point, !isCapturing { capture(at: point, droppedAt: event.location) }
            return true
        }
        if type == .rightMouseUp, consumedRight { consumedRight = false; return true }
        let key = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        if type == .keyUp, key == 53, consumedEscape { consumedEscape = false; return true }
        guard !recording, let configured else { return false }
        if type == .keyDown, key == 53, gesture.active || isCapturing { consumedEscape = true; cancelGesture(); return true }
        if type == .rightMouseDown, gesture.active || isCapturing { consumedRight = true; cancelGesture(); return true }
        if type == .leftMouseDown, gesture.active {
            guard !isCapturing else { consumedMouse = true; return true }
            cursorPose.openness = 0.12
            cursorPose.gripping = true
            let point = event.location
            targetTask?.cancel()
            targetTask = Task { try await PointCapture.prepare(at: point) }
            consumedMouse = true; pressPoint = event.location
            cursorPose.preview = nil; cursorPose.text = ""; cursorPose.material = .note
            cursorPose.pickupMessage = "正在读取…"; cursorPose.failed = false
            let pending = targetTask!
            previewTask?.cancel()
            previewTask = Task { @MainActor [weak self] in
                do {
                    let prepared = try await pending.value
                    guard !Task.isCancelled, let self, self.gesture.active, !self.isCapturing else { return }
                    let target = prepared.target
                    self.cursorPose.pickupMessage = target.title
                    switch target.payload {
                    case .file(let url):
                        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .contentTypeKey])
                        let kind: ClipKind = values?.isDirectory == true ? .folder : (values?.contentType?.conforms(to: .image) == true ? .image : .file)
                        var item = ClipItem(kind: kind, title: url.lastPathComponent)
                        item.originalPath = url.path
                        self.cursorPose.material = PhysicalMaterial.forItem(item)
                        self.cursorPose.preview = NSWorkspace.shared.icon(forFile: url.path)
                    case .text(let text): self.cursorPose.material = .note; self.cursorPose.text = String(text.prefix(12))
                    case .link: self.cursorPose.material = .bookmark; self.cursorPose.preview = NSImage(systemSymbolName: "link", accessibilityDescription: nil)
                    case .image:
                        self.cursorPose.material = .photo
                        self.cursorPose.preview = prepared.image.map { NSImage(cgImage: $0, size: .zero) }
                    }
                } catch {
                    guard !Task.isCancelled, let self, self.gesture.active, !self.isCapturing else { return }
                    self.cursorPose.failed = true
                    self.cursorPose.pickupMessage = error.localizedDescription
                    self.cursorPose.openness = 1
                }
            }
            return true
        }
        guard [.flagsChanged, .keyDown, .keyUp].contains(type) else { return false }
        let consume = gesture.update(shortcut: configured, flags: event.flags.rawValue,
            key: type == .flagsChanged ? nil : key,
            down: type == .keyDown ? true : (type == .keyUp ? false : nil),
            repeated: event.getIntegerValueField(.keyboardEventAutorepeat) != 0)
        if type == .keyDown, key == 53, consume { consumedEscape = true; captureTask?.cancel() }
        if !gesture.active {
            pressPoint = nil; targetTask?.cancel(); targetTask = nil
        }
        updateCursor()
        return consume
    }
    private func updateCursor() {
        guard !isCapturing else { return }
        guard gesture.active, !recording else { hideCursor(); return }
        cursorPose.openness = consumedMouse ? 0.12 : 1
        if !NSApp.isActive && !acquiringForeground {
            previousApplication = NSWorkspace.shared.frontmostApplication
            acquiringForeground = true
            // Keep settings/editor windows from coming forward over the capture target.
            parkedWindows = NSApp.windows.filter { $0.isVisible && !($0 is FloatingPanel) }
            parkedWindows.forEach { $0.orderOut(nil) }
            NSApp.activate(ignoringOtherApps: true)
        }
        moveCursor()
        presentCursorWithoutPointer()
        guard watchdog == nil else { return }
        // Keyboard release is tracked by the event tap. Session flags can lag
        // behind intercepted events, so they must not cancel a valid gesture.
        watchdog = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if !AXIsProcessTrusted() || IsSecureEventInputEnabled() { self.cancelGesture(); return }
                if self.gesture.active, !self.isCapturing { self.moveCursor(); self.presentCursorWithoutPointer() }
            }
        }
    }
    private func presentCursorWithoutPointer() {
        guard NSApp.isActive else { cursorPanel.orderOut(nil); return }
        acquiringForeground = false
        guard cursorVisibility.acquire() else {
            status = "系统未允许隐藏指针，鼠标夹取已取消"; cancelGesture(); return
        }
        cursorPanel.orderFrontRegardless()
        pickupPanel.orderFrontRegardless()
    }
    private func moveCursor(at eventPoint: CGPoint? = nil) {
        let point = eventPoint.map { Self.cocoaPoint($0) } ?? NSEvent.mouseLocation
        cursorPose.nearEdge = NSScreen.screens.first(where: { $0.frame.contains(point) }).map { self.store.state.preferences.autoSnap && DockGeometry.side(at: point, in: $0.frame, distance: self.store.state.preferences.snapDistance) != nil } ?? false
        // The clip's jaw, rather than its centre, marks the click location.
        cursorPanel.setFrame(PointClampCursorGeometry.frame(at: point), display: true)
        let screen = NSScreen.screens.first { $0.frame.contains(point) }?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let size = CGSize(width: 240, height: 62)
        pickupPanel.setFrame(NSRect(x: max(screen.minX, min(point.x + 18, screen.maxX - size.width)),
                                    y: max(screen.minY, min(point.y - 82, screen.maxY - size.height)),
                                    width: size.width, height: size.height), display: true)
    }
    static func cocoaPoint(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x, y: (NSScreen.screens.first?.frame.maxY ?? 0) - point.y)
    }
    private func hideCursor() {
        previewTask?.cancel(); previewTask = nil
        watchdog?.invalidate(); watchdog = nil
        cursorPanel.orderOut(nil); pickupPanel.orderOut(nil)
        cursorPose.gripping = false; cursorPose.processing = false
        cursorVisibility.release()
        acquiringForeground = false
        parkedWindows.forEach { $0.orderBack(nil) }; parkedWindows.removeAll()
        let previous = previousApplication; previousApplication = nil
        if NSApp.isActive, let previous, !previous.isTerminated, previous.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previous.activate(options: [])
        }
    }
    private func cancelGesture() {
        captureGeneration += 1
        targetTask?.cancel(); targetTask = nil; pressPoint = nil
        captureTask?.cancel(); captureTask = nil; isCapturing = false
        gesture.cancel(); hideCursor()
    }
    private func capture(at point: CGPoint, droppedAt destination: CGPoint) {
        let pendingTarget = targetTask
        targetTask = nil
        captureGeneration += 1
        let generation = captureGeneration
        isCapturing = true
        cursorPose.pickupMessage = "正在放置…"
        cursorPose.openness = 0
        captureTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                pendingTarget?.cancel()
                if self.captureGeneration == generation {
                    self.isCapturing = false; self.captureTask = nil
                    self.gesture.cancel(); self.hideCursor()
                }
            }
            do {
                try Task.checkCancellation()
                if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { try await Task.sleep(nanoseconds: 140_000_000) }
                self.hideCursor()
                self.cursorPose.processing = true
                self.pickupPanel.orderFrontRegardless()
                let prepared: PreparedPointTarget
                if let pendingTarget {
                    prepared = try await withTaskCancellationHandler {
                        try await pendingTarget.value
                    } onCancel: { pendingTarget.cancel() }
                } else { throw PointCaptureError.unavailable }
                try Task.checkCancellation()
                let target = prepared.target
                let previous = Set(self.store.active.map(\.id))
                switch target.payload {
                case .file(let url): self.store.importFiles([url])
                case .text(let text): self.store.addTextOrLink(text)
                case .link(let url): self.store.addTextOrLink(url.absoluteString)
                case .image:
                    guard let cgImage = prepared.image else { throw PointCaptureError.unavailable }
                    self.store.addCapturedImage(cgImage, title: target.title)
                }
                self.store.hidden = false; self.store.onChange?()
                let newItem = self.store.active.first { !previous.contains($0.id) }
                let added = newItem != nil
                if let newItem { self.store.tactile(); self.onPlace?(newItem.id, Self.cocoaPoint(destination)) }
                self.showFeedback(added ? "已夹住" : (self.store.message ?? "已处理"), at: destination)
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                self.store.notify(error.localizedDescription); self.showFeedback(error.localizedDescription, at: point)
            }
        }
    }
    private func showFeedback(_ message: String, at point: CGPoint) {
        feedbackWork?.cancel()
        let cocoaPoint = Self.cocoaPoint(point)
        let frame = NSScreen.screens.first { $0.frame.contains(cocoaPoint) }?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1000, height: 800)
        let size = NSSize(width: 300, height: 64)
        feedbackPanel.contentView = NSHostingView(rootView: HStack(spacing: 8) { MetalClip(); Text(message).font(.system(size: 11)).lineLimit(3) }.padding(10).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)).padding(4))
        feedbackPanel.setFrame(NSRect(x: max(frame.minX, min(cocoaPoint.x + 14, frame.maxX - size.width)), y: max(frame.minY, min(cocoaPoint.y - 70, frame.maxY - size.height)), width: size.width, height: size.height), display: true)
        feedbackPanel.orderFrontRegardless()
        let work = DispatchWorkItem { [weak self] in self?.feedbackPanel.orderOut(nil) }
        feedbackWork = work; DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: work)
    }
    func stop() {
        cancelGesture(); gesture.reset()
        consumedMouse = false; consumedEscape = false; consumedRight = false; pressPoint = nil
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil; source = nil; configured = nil; running = false
    }
    func shutdown() {
        configurationTimer?.invalidate(); configurationTimer = nil
        stop(); feedbackWork?.cancel(); feedbackPanel.orderOut(nil)
        for token in notices { NotificationCenter.default.removeObserver(token); NSWorkspace.shared.notificationCenter.removeObserver(token) }
        notices.removeAll()
    }
}


@MainActor final class CursorClipPose: ObservableObject {
    @Published var openness: Double = 1
    @Published var gripping = false
    @Published var nearEdge = false
    @Published var preview: NSImage?
    @Published var text = ""
    @Published var material: PhysicalMaterial = .note
    @Published var pickupMessage = ""
    @Published var failed = false
    @Published var processing = false
}

struct CursorClipView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var pose: CursorClipPose
    var body: some View {
        ImageGenCursorClip(openness: pose.gripping && !pose.failed ? max(pose.openness, pose.material.jawOpening) : pose.openness)
            .animation(reduceMotion ? nil : .spring(response: 0.22, dampingFraction: 0.8), value: pose.openness)
            .background(alignment: .leading) {
                if pose.gripping && !pose.failed {
                    Group {
                        if pose.material.isPocket { FolderMaterial(tint: .kraft, opening: 0.6, layers: 2) }
                        else if pose.material == .bookmark { BookmarkMaterial() }
                        else if pose.material == .note || pose.material == .photo { RoundedRectangle(cornerRadius: 2).fill(Color(red: 0.99, green: 0.97, blue: 0.9)) }
                        else { FileMaterial(material: pose.material) }
                    }
                        .frame(width: 22, height: 28)
                        .overlay {
                            if let preview = pose.preview { Image(nsImage: preview).resizable().scaledToFit().padding(3) }
                            else { Text(pose.text).font(.system(size: 5)).foregroundStyle(.black).lineLimit(3).padding(2) }
                        }
                        .rotationEffect(.degrees(pose.nearEdge ? 0 : -9))
                        .shadow(radius: 2, y: 2)
                }
            }
            .padding(5)
    }
}

struct PickupHintView: View {
    @ObservedObject var pose: CursorClipPose
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(pose.processing ? "正在放置…" : (pose.gripping ? pose.pickupMessage : "点击夹住内容，拖动后松手放置"))
                .font(.system(size: 11, weight: .medium)).lineLimit(2)
            Text(pose.processing ? "正在读取目标 · Esc / 右键取消" : (pose.failed ? "Esc / 右键取消，松开按键重试" : (pose.gripping ? (pose.nearEdge ? "松手吸附到屏幕边缘 · Esc 取消" : "松手放在这里 · Esc / 右键取消") : "松开夹取按键退出 · Esc / 右键取消")))
                .font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(9)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 9)).padding(3)
        .allowsHitTesting(false)
    }
}
