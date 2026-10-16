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
    static let drawingInset: CGFloat = 20
    static func drawingFrame(at point: CGPoint) -> NSRect { frame(at: point).insetBy(dx: -drawingInset, dy: -drawingInset) }
    static func frame(at point: CGPoint) -> NSRect {
        NSRect(x: point.x - hotspot.x, y: point.y - hotspot.y, width: size.width, height: size.height)
    }
}

@MainActor final class PointClampController: ObservableObject {
    @Published private(set) var status = "未启用"
    @Published private(set) var running = false
    let store: ClipStore
    var blocksHoverExpansion: Bool { gesture.active || isCapturing }
    var onPlace: ((UUID, CGPoint) -> Void)?
    private var targetTask: Task<PreparedPointTarget, Error>?
    private var previewTask: Task<Void, Never>?
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var configured: HoldShortcut?
    private var gesture = HoldGestureState()
    private let cursorPanel = FloatingPanel()
    private let cursorPose = CursorClipPose()
    private let pickupMotion = CursorPickupMotion()
    private let pickupAnimationPanel = FloatingPanel()
    private var cursorPoint = CGPoint.zero
    private let aim = TargetAimController()
    private let subjects = ImageSubjectAimController()
    private let subjectGlowPanel = FloatingPanel()
    private var aimedTarget: PointTarget?
    private let glowPanel = FloatingPanel()
    private let glowState = TargetGlowState()
    private var glowLayout: TargetGlowLayout?
    private var glowStyle: TargetGlowStyle?
    private var aimHintVisible = false
    private let cursorVisibility = CursorVisibilityLease()
    private var previousApplication: NSRunningApplication?
    private var acquiringForeground = false
    private var parkedWindows: [NSWindow] = []
    private var watchdog: Timer?
    private var configurationTimer: Timer?
    private var isCapturing = false
    private var captureGeneration = 0
    private var carrySampler = DragMotionSampler()
    private var carryOrigin = CGPoint.zero
    private var carrySettleWork: DispatchWorkItem?
    private var captureTask: Task<Void, Never>?
    private var consumedMouse = false
    private var consumedEscape = false
    private var consumedRight = false
    private var pressPoint: CGPoint?
    private var recording = false
    private var notices: [NSObjectProtocol] = []
    private let pickupPanel = FloatingPanel()
    private let feedback = ClampFeedbackPresenter()
    init(store: ClipStore) {
        self.store = store
        glowPanel.ignoresMouseEvents = true
        glowPanel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue - 1)
        glowPanel.setAccessibilityElement(false)
        glowPanel.animationBehavior = .none
        subjectGlowPanel.ignoresMouseEvents = true
        subjectGlowPanel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue - 1)
        subjectGlowPanel.animationBehavior = .none; subjectGlowPanel.setAccessibilityElement(false)
        subjects.onSelection = { [weak self] selection in self?.showSubject(selection) }
        aim.onTarget = { [weak self] target in
            guard let self else { return }
            self.aimedTarget = target
            let point = NSEvent.mouseLocation
            self.subjects.update(target, at: CGPoint(x: point.x, y: (NSScreen.screens.first?.frame.maxY ?? 0) - point.y))
            self.showAim(target)
        }
        aim.onMotion = { [weak self] moving in
            guard let self, self.glowState.moving != moving else { return }
            self.glowState.moving = moving
        }
        aim.onHint = { [weak self] visible in
            guard let self else { return }
            self.aimHintVisible = visible
            if visible, self.gesture.active, !self.consumedMouse, !self.isCapturing, NSApp.isActive {
                self.pickupPanel.orderFrontRegardless()
            } else if !self.consumedMouse && !self.isCapturing { self.pickupPanel.orderOut(nil) }
        }
        pickupPanel.ignoresMouseEvents = true
        pickupPanel.level = .screenSaver
        pickupPanel.contentView = NSHostingView(rootView: PickupHintView(pose: cursorPose))
        cursorPanel.ignoresMouseEvents = true
        cursorPanel.level = .screenSaver
        cursorPanel.setAccessibilityElement(false)
        cursorPanel.animationBehavior = .none
        cursorPanel.contentView = NSHostingView(rootView: CursorClipView(pose: cursorPose))
        pickupAnimationPanel.ignoresMouseEvents = true
        pickupAnimationPanel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue - 1)
        pickupAnimationPanel.animationBehavior = .none
        pickupAnimationPanel.setAccessibilityElement(false)
        pickupAnimationPanel.contentView = NSHostingView(rootView: CursorPickupView(motion: pickupMotion, pose: cursorPose))
        pickupMotion.onFrame = { [weak self] in
            guard let self else { return }
            self.cursorPose.openness = self.pickupMotion.sample.jaw
            self.pickupAnimationPanel.setFrame(self.pickupMotion.panelFrame, display: true)
        }
        pickupMotion.onFinish = { [weak self] in
            guard let self else { return }
            self.cursorPose.pickingUp = false
            self.cursorPose.openness = self.cursorPose.material.jawOpening
            self.pickupAnimationPanel.orderOut(nil)
            self.carryOrigin = self.cursorPoint
            self.carrySampler.reset(at: ProcessInfo.processInfo.systemUptime)
        }
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
        let types: [CGEventType] = [.flagsChanged, .keyDown, .keyUp, .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .mouseMoved, .leftMouseDragged, .scrollWheel]
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
        if type == .scrollWheel {
            aim.cancel()
            if gesture.active, !consumedMouse, !isCapturing { moveCursor(at: event.location) }
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
            let subject = subjects.selected(at: event.location)
            aim.cancel(); subjects.cancel(); feedback.dismiss()
            pickupMotion.cancel(); pickupAnimationPanel.orderOut(nil)
            cursorPose.pickingUp = false
            cursorPose.openness = 1
            cursorPose.gripping = true; cursorPose.hasMaterial = false
            cursorPose.motionEnabled = store.state.preferences.motionIntensity > 0 && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            let point = event.location
            targetTask?.cancel()
            targetTask = Task {
                if let subject, let prepared = try await ImageSubjectCapture.prepare(subject, at: point) { return prepared }
                try Task.checkCancellation()
                return try await PointCapture.prepare(at: point)
            }
            consumedMouse = true; pressPoint = event.location
            cursorPose.preview = nil; cursorPose.isCutout = false; cursorPose.text = ""; cursorPose.material = .note
            cursorPose.pickupMessage = "正在读取…"; cursorPose.failed = false
            let pending = targetTask!
            previewTask?.cancel()
            previewTask = Task { @MainActor [weak self] in
                do {
                    let prepared = try await pending.value
                    guard !Task.isCancelled, let self, self.gesture.active, !self.isCapturing else { return }
                    self.applyPreparedTarget(prepared, sourcePoint: point)
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
        if !pickupMotion.active { cursorPose.openness = consumedMouse && cursorPose.hasMaterial ? cursorPose.material.jawOpening : 1 }
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
        if consumedMouse || aimHintVisible { pickupPanel.orderFrontRegardless() }
        else { pickupPanel.orderOut(nil) }
    }
    private func moveCursor(at eventPoint: CGPoint? = nil) {
        let point = eventPoint.map { Self.cocoaPoint($0) } ?? NSEvent.mouseLocation
        cursorPoint = point
        pickupMotion.move(to: point)
        if !consumedMouse && !isCapturing {
            let top = NSScreen.screens.first?.frame.maxY ?? 0
            let axPoint = CGPoint(x: point.x, y: top - point.y)
            subjects.move(to: axPoint)
            aim.update(at: axPoint)
        }
        if consumedMouse { updateCarry(at: point) }
        cursorPose.nearEdge = NSScreen.screens.first(where: { $0.frame.contains(point) }).map { self.store.state.preferences.autoSnap && DockGeometry.side(at: point, in: $0.frame, distance: self.store.state.preferences.snapDistance) != nil } ?? false
        // The clip's jaw, rather than its centre, marks the click location.
        cursorPanel.setFrame(PointClampCursorGeometry.drawingFrame(at: point), display: true)
        let screen = NSScreen.screens.first { $0.frame.contains(point) }?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let size = CGSize(width: 240, height: 62)
        pickupPanel.setFrame(NSRect(x: max(screen.minX, min(point.x + 18, screen.maxX - size.width)),
                                    y: max(screen.minY, min(point.y - 82, screen.maxY - size.height)),
                                    width: size.width, height: size.height), display: true)
    }
    private func applyPreparedTarget(_ prepared: PreparedPointTarget, sourcePoint: CGPoint) {
        guard !cursorPose.hasMaterial else { return }
        let target = prepared.target
        cursorPose.pickupMessage = target.title
        cursorPose.isCutout = prepared.isSubject
        switch target.payload {
        case .file(let url):
            let kind = prepared.fileKind ?? .file
            var item = ClipItem(kind: kind, title: url.lastPathComponent); item.originalPath = url.path
            cursorPose.material = PhysicalMaterial.forItem(item)
            cursorPose.preview = NSWorkspace.shared.icon(forFile: url.path)
        case .text(let text): cursorPose.material = .note; cursorPose.text = String(text.prefix(240))
        case .link: cursorPose.material = .bookmark; cursorPose.preview = NSImage(systemSymbolName: "link", accessibilityDescription: nil)
        case .image:
            cursorPose.material = .photo
            cursorPose.preview = prepared.image.map { NSImage(cgImage: $0, size: .zero) }
        }
        cursorPose.hasMaterial = true
        let click = Self.cocoaPoint(sourcePoint)
        let screen = NSScreen.screens.first { $0.frame.contains(click) }?.frame ?? NSScreen.main?.frame ?? .zero
        let source = CursorPickupGeometry.source(bounds: target.bounds, regions: target.regions, click: click,
            screen: screen, desktopTop: NSScreen.screens.first?.frame.maxY ?? 0)
        cursorPose.pickingUp = cursorPose.motionEnabled
        pickupMotion.start(source: source, destination: cursorPoint, material: cursorPose.material, animated: cursorPose.motionEnabled)
        if pickupMotion.active { pickupAnimationPanel.orderFrontRegardless() }
    }

    private func updateCarry(at point: CGPoint) {
        guard cursorPose.hasMaterial, cursorPose.motionEnabled, !pickupMotion.active else { return }
        let delta = CGPoint(x: point.x - carryOrigin.x, y: point.y - carryOrigin.y)
        guard let pull = carrySampler.sample(delta: delta, at: ProcessInfo.processInfo.systemUptime, inertia: cursorPose.material.inertia) else { return }
        cursorPose.carrySettling = false; cursorPose.carryPull = pull
        carrySettleWork?.cancel()
        let settle = DispatchWorkItem { [weak self] in
            guard let self, self.gesture.active, self.cursorPose.hasMaterial else { return }
            self.cursorPose.carrySettling = true; self.cursorPose.carryPull = .resting
        }
        carrySettleWork = settle
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.09, execute: settle)
    }
    private func showSubject(_ selection: ImageSubjectSelection?) {
        guard gesture.active, !consumedMouse, !isCapturing, let selection,
              let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }),
              let frame = TargetGlowGeometry.frame(rect: selection.screenRect, screen: screen.frame, desktopTop: NSScreen.screens.first?.frame.maxY ?? 0) else {
            subjectGlowPanel.orderOut(nil); subjectGlowPanel.contentView = nil
            showAim(aimedTarget); return
        }
        glowPanel.orderOut(nil)
        cursorPose.aimTitle = "图片主体 · 点击单独夹住"
        subjectGlowPanel.contentView = NSHostingView(rootView: ImageSubjectGlowView(selection: selection,
            animated: store.state.preferences.motionIntensity > 0 && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, state: glowState))
        subjectGlowPanel.setFrame(frame, display: true); subjectGlowPanel.orderFrontRegardless()
    }
    private func showAim(_ target: PointTarget?) {
        if subjects.selection != nil { glowPanel.orderOut(nil); return }
        guard gesture.active, !consumedMouse, !isCapturing, let target,
              let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }),
              let layout = TargetGlowLayout.make(regions: target.regions.isEmpty ? target.bounds.map { [$0] } ?? [] : target.regions,
                                                 screen: screen.frame, desktopTop: NSScreen.screens.first?.frame.maxY ?? 0) else {
            if glowPanel.isVisible { glowPanel.orderOut(nil) }
            glowPanel.contentView = nil; glowLayout = nil; glowStyle = nil
            if !cursorPose.aimTitle.isEmpty { cursorPose.aimTitle = "" }
            return
        }
        cursorPose.aimTitle = target.title
        let style = TargetGlowStyle.forTarget(target)
        if glowPanel.isVisible && glowLayout == layout && glowStyle == style { return }
        glowLayout = layout; glowStyle = style
        glowPanel.contentView = NSHostingView(rootView: TargetGlowView(animated: !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion && store.state.preferences.motionIntensity > 0,
                                                                     style: style, regions: layout.regions, state: glowState))
        glowPanel.setFrame(layout.frame, display: true)
        glowPanel.orderFrontRegardless()
    }
    static func cocoaPoint(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x, y: (NSScreen.screens.first?.frame.maxY ?? 0) - point.y)
    }
    private func hideCursor() {
        pickupMotion.cancel(); pickupAnimationPanel.orderOut(nil)
        cursorPose.pickingUp = false
        aim.cancel(); subjects.cancel(); subjectGlowPanel.orderOut(nil); subjectGlowPanel.contentView = nil
        carrySettleWork?.cancel(); carrySettleWork = nil
        cursorPose.hasMaterial = false; cursorPose.carryPull = .resting
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
        moveCursor(at: destination)
        let readyAtRelease = cursorPose.hasMaterial
        cursorPose.pickupMessage = "正在放置…"
        if !pickupMotion.active { cursorPose.openness = 0 }
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
                self.cursorPose.processing = true
                let prepared: PreparedPointTarget
                if let pendingTarget {
                    prepared = try await withTaskCancellationHandler {
                        try await pendingTarget.value
                    } onCancel: { pendingTarget.cancel() }
                } else { throw PointCaptureError.unavailable }
                try Task.checkCancellation()
                self.applyPreparedTarget(prepared, sourcePoint: point)
                try await self.pickupMotion.finish()
                try Task.checkCancellation()
                self.cursorPose.carrySettling = true; self.cursorPose.carryPull = .resting
                self.cursorPose.processing = true
                if readyAtRelease && self.cursorPose.motionEnabled { try await Task.sleep(nanoseconds: 90_000_000) }
                try Task.checkCancellation()
                self.hideCursor()
                let target = prepared.target
                let previous = Set(self.store.active.map(\.id))
                let added = try self.store.batchChanges {
                    switch target.payload {
                    case .file(let url): self.store.importFiles([url])
                    case .text(let text): self.store.addTextOrLink(text)
                    case .link(let url): self.store.addTextOrLink(url.absoluteString)
                    case .image:
                        guard let cgImage = prepared.image else { throw PointCaptureError.unavailable }
                        self.store.addCapturedImage(cgImage, title: target.title, isCutout: prepared.isSubject)
                    }
                    self.store.hidden = false
                    let newItem = self.store.active.first { !previous.contains($0.id) }
                    let added = newItem != nil
                    if let newItem { self.store.tactile(); self.onPlace?(newItem.id, Self.cocoaPoint(destination)) }
                    return added
                }
                self.showFeedback(added ? "已夹住" : (self.store.message ?? "已处理"), kind: added ? .success : .notice, at: destination)
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                self.store.notify(error.localizedDescription); self.showFeedback(error.localizedDescription, kind: .failure, at: destination)
            }
        }
    }
    private func showFeedback(_ message: String, kind: ClampFeedbackKind, at point: CGPoint) {
        feedback.show(message, kind: kind, at: Self.cocoaPoint(point),
            animated: store.state.preferences.motionIntensity > 0 && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
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
        stop(); feedback.dismiss()
        for token in notices { NotificationCenter.default.removeObserver(token); NSWorkspace.shared.notificationCenter.removeObserver(token) }
        notices.removeAll()
    }
}


@MainActor final class CursorClipPose: ObservableObject {
    @Published var openness: Double = 1
    @Published var gripping = false
    @Published var nearEdge = false
    @Published var preview: NSImage?
    @Published var isCutout = false
    @Published var text = ""
    @Published var material: PhysicalMaterial = .note
    @Published var pickupMessage = ""
    @Published var failed = false
    @Published var processing = false
    @Published var aimTitle = ""
    @Published var hasMaterial = false
    @Published var pickingUp = false
    @Published var motionEnabled = true
    @Published var carryPull = PaperPull.resting
    @Published var carrySettling = true
    var effectiveOpenness: Double { gripping && hasMaterial && !failed ? max(openness, material.jawOpening) : 1 }
}

struct CursorClipView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var pose: CursorClipPose
    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear.frame(width: 64, height: 46)
            if pose.gripping && pose.hasMaterial && !pose.failed && !pose.pickingUp {
                CursorHeldMaterial(pose: pose)
                    .rotationEffect(.degrees(-6 + Double(pose.carryPull.x) * 7 + Double(pose.carryPull.y) * 2), anchor: UnitPoint(x: 12 / 22.0, y: 0))
                    .animation(reduceMotion || !pose.motionEnabled || !pose.carrySettling ? nil : .spring(response: pose.material.springResponse, dampingFraction: 0.7), value: pose.carryPull)
                    .shadow(color: .black.opacity(0.22), radius: 2, y: 1.2)
                    .position(x: 4, y: 37)
            }
            ImageGenCursorClip(openness: pose.effectiveOpenness)
                .animation(reduceMotion || !pose.motionEnabled || pose.pickingUp ? nil : .spring(response: 0.22, dampingFraction: 0.8), value: pose.openness)
                .position(x: 32, y: 23)
        }
        .frame(width: 64, height: 46)
        .padding(PointClampCursorGeometry.drawingInset)
    }
}

struct PickupHintView: View {
    @ObservedObject var pose: CursorClipPose
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(pose.processing ? "正在放置…" : (pose.gripping ? pose.pickupMessage : (pose.aimTitle.isEmpty ? "点击夹住内容，拖动后松手放置" : "夹取 · " + pose.aimTitle)))
                .font(.system(size: 11, weight: .medium)).lineLimit(2)
            Text(pose.processing ? "正在读取目标 · Esc / 右键取消" : (pose.failed ? "Esc / 右键取消，松开按键重试" : (pose.gripping ? (pose.nearEdge ? "松手吸附到屏幕边缘 · Esc 取消" : "松手放在这里 · Esc / 右键取消") : "松开夹取按键退出 · Esc / 右键取消")))
                .font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(9)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 9)).padding(3)
        .allowsHitTesting(false)
    }
}
