import AppKit
import SwiftUI
import ClampCore

final class FloatingPanel: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false; backgroundColor = .clear; hasShadow = false; level = .floating
        hidesOnDeactivate = false; isMovable = false; becomesKeyOnlyIfNeeded = true
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
    }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor final class CardModel: ObservableObject {
    let id: UUID
    @Published var expanded = false
    @Published var revealProgress: CGFloat = 0
    @Published var sheetSize = CGSize.zero
    @Published private(set) var documentTurning = false
    var pageTurnInset: CGFloat {
        documentTurning && expanded ? LeftBindingPageGeometry.drawingOutset(height: max(0, sheetSize.height - ClipOrientation.verticalMargins)) + 20 : 0
    }
    var pageTurnSideInset: CGFloat { documentTurning && expanded ? ceil(sheetSize.width * 0.055 + 20) : 0 }
    func documentTurn(_ active: Bool) {
        guard !retired, documentTurning != active else { return }
        documentTurning = active; manager?.layout(self)
    }
    var revealInFlight = false
    var sticky = false
    var busy = false
    @Published var moving = false
    @Published var nearEdge = false
    @Published var mergeReady = false
    @Published var paperPull = PaperPull.resting
    private var dragSampler = DragMotionSampler()
    private var dragSettleWork: DispatchWorkItem?
    @Published var dragResting = true
    var hovered = false
    var slot = NSRect.zero
    let panel = FloatingPanel()
    weak var manager: WindowManager?
    private var hoverWork: DispatchWorkItem?
    private var revealWork: DispatchWorkItem?
    private var revealGeneration = 0
    private var dragOrigin = NSRect.zero
    private(set) var hoverSuppressed = false
    private var retired = false
    init(id: UUID, manager: WindowManager) { self.id = id; self.manager = manager }
    func hover(_ inside: Bool) {
        hovered = inside; hoverWork?.cancel()
        guard !retired else { return }
        // Resizing a window synthesizes exit/enter events; only a genuine exit
        // from the current hit area may rearm a deliberately closed clip.
        if !inside && !panel.frame.contains(NSEvent.mouseLocation) { hoverSuppressed = false }
        if inside && manager?.hoverExpansionBlocked == true { hoverSuppressed = true; return }
        if inside && (hoverSuppressed || manager?.store.state.preferences.hoverToExpand == false) { return }
        if busy || moving || manager?.menuTracking == true { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.retired, !self.busy, !self.moving, !(inside && self.hoverSuppressed), self.manager?.menuTracking != true else { return }
            if inside {
                guard self.manager?.hoverExpansionBlocked != true else { self.hoverSuppressed = true; return }
                guard self.manager?.store.state.preferences.hoverToExpand != false else { return }
                self.present()
            }
            else if !self.sticky && self.manager?.placement(self.id)?.mode != .floating { self.dismiss() }
        }
        hoverWork = work; DispatchQueue.main.asyncAfter(deadline: .now() + (inside ? (manager?.store.state.preferences.hoverDelay ?? 0.35) : 0.45), execute: work)
    }
    func show() {
        guard !retired else { return }
        hoverWork?.cancel(); hoverSuppressed = false; sticky = true; present()
    }
    private var physical: PhysicalMaterial { PhysicalMaterial.forItem(manager?.store.item(id)) }
    private var revealAnimation: Animation { .spring(response: HingeReveal.duration, dampingFraction: 0.72) }
    private var closeDuration: TimeInterval { HingeReveal.closeDuration }
    func present(animated: Bool = true) {
        guard !retired else { return }
        cancelReveal()
        let wasExpanded = expanded
        let animate = animated && manager?.store.state.preferences.motionIntensity != 0 && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        expanded = true; revealInFlight = animate; manager?.layout(self)
        guard animate else { revealProgress = 1; return }
        if wasExpanded {
            withAnimation(revealAnimation) { revealProgress = 1 }
            finishRevealAfterSettling()
        } else {
            revealProgress = 0
            let generation = revealGeneration
            let work = DispatchWorkItem { [weak self] in
                guard let self, !self.retired, self.expanded, self.revealGeneration == generation else { return }
                withAnimation(self.revealAnimation) { self.revealProgress = 1 }
                self.finishRevealAfterSettling()
            }
            revealWork = work; DispatchQueue.main.asyncAfter(deadline: .now() + 0.016, execute: work)
        }
    }
    private func dismiss() {
        cancelReveal()
        guard expanded else { revealInFlight = false; revealProgress = 0; manager?.layout(self); return }
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion || manager?.store.state.preferences.motionIntensity == 0 {
            revealInFlight = false; revealProgress = 0; expanded = false; manager?.layout(self); return
        }
        revealInFlight = true; manager?.layout(self)
        withAnimation(.easeInOut(duration: closeDuration)) { revealProgress = 0 }
        let generation = revealGeneration
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.retired, self.revealProgress == 0, self.revealGeneration == generation else { return }
            self.revealInFlight = false; self.expanded = false; self.revealWork = nil; self.manager?.layout(self)
        }
        revealWork = work; DispatchQueue.main.asyncAfter(deadline: .now() + closeDuration, execute: work)
    }
    private func finishRevealAfterSettling() {
        let generation = revealGeneration
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.retired, self.expanded, self.revealGeneration == generation else { return }
            self.revealInFlight = false; self.revealWork = nil; self.manager?.layout(self)
        }
        revealWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + HingeReveal.settleDuration, execute: work)
    }
    private func cancelReveal() { revealGeneration += 1; revealWork?.cancel(); revealWork = nil }
    func retire() {
        retired = true; dragSettleWork?.cancel(); hoverWork?.cancel(); hoverWork = nil; cancelReveal()
        revealInFlight = false; documentTurning = false; paperPull = .resting
        manager = nil; panel.orderOut(nil)
        // Break CardModel → panel → hosting view → CardModel retention.
        panel.contentView = nil
    }
    func close() {
        guard !busy, !moving, manager?.menuTracking != true else { return }
        hoverWork?.cancel(); hoverWork = nil; hoverSuppressed = true
        sticky = false
        if manager?.placement(id)?.mode == .floating { manager?.dock(id) }
        else { dismiss() }
    }
    func beginMove() {
        guard !retired else { return }
        if documentTurning { documentTurning = false; manager?.layout(self) }
        let wasWide = expanded || manager?.placement(id)?.mode == .floating
        hoverWork?.cancel(); cancelReveal()
        hoverSuppressed = true; revealInFlight = false; busy = true; expanded = wasWide; revealProgress = wasWide ? 1 : 0; sticky = true
        let previous = panel.frame
        manager?.layout(self)
        moving = true
        let left = manager?.placement(id)?.side == .left
        let lift = wasWide ? CGFloat(0) : HingeReveal.suspension(size: panel.frame.size, isLeft: left).y - ClipOrientation.compactHookY
        let slide = wasWide ? CGFloat(0) : HingeReveal.translation(progress: 0, isLeft: left).width
        if left { panel.setFrameOrigin(NSPoint(x: previous.minX + slide, y: previous.maxY + lift - panel.frame.height)) }
        else { panel.setFrameOrigin(NSPoint(x: previous.maxX + slide - panel.frame.width, y: previous.maxY + lift - panel.frame.height)) }
        dragOrigin = panel.frame
        dragSettleWork?.cancel(); dragResting = false
        dragSampler.reset(at: ProcessInfo.processInfo.systemUptime)
        paperPull = .resting
    }
    func move(_ delta: NSPoint) {
        guard moving, !retired else { return }
        // Window position follows every event; visual work is bounded to 60 Hz.
        panel.setFrameOrigin(NSPoint(x: dragOrigin.minX + delta.x, y: dragOrigin.minY + delta.y))
        guard let pull = dragSampler.sample(delta: delta, at: ProcessInfo.processInfo.systemUptime, inertia: physical.inertia) else { return }
        if dragResting { dragResting = false }
        if manager?.store.state.preferences.motionIntensity != 0 && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { paperPull = pull }
        dragSettleWork?.cancel()
        let settle = DispatchWorkItem { [weak self] in
            guard let self, self.moving, !self.retired else { return }
            self.dragResting = true; self.paperPull = .resting
        }
        dragSettleWork = settle
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.09, execute: settle)
        let point = NSEvent.mouseLocation
        manager?.updateGrouping(source: id, at: point)
        manager?.showSnapPreview(at: point)
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) {
            let preferences = manager?.store.state.preferences ?? AppPreferences()
            let next = preferences.autoSnap && DockGeometry.side(at: point, in: screen.frame, distance: preferences.snapDistance) != nil
            if nearEdge != next { nearEdge = next }
        }
    }
    func endMove() { manager?.updateGrouping(source: id, at: NSEvent.mouseLocation); dragSettleWork?.cancel(); dragResting = true; manager?.hideSnapPreview(); paperPull = .resting; moving = false; nearEdge = false; busy = false; manager?.finishMove(self) }
    func interaction(_ active: Bool) { busy = active; if !active { hover(hovered) } }
}

@MainActor final class WindowManager: NSObject, NSWindowDelegate {
    let store: ClipStore
    let pointClamp: PointClampController
    var cards: [UUID: CardModel] = [:]
    var rails: [String: FloatingPanel] = [:]
    var libraryWindow: NSWindow?
    var settingsWindow: NSWindow?
    var editors: [UUID: NSWindow] = [:]
    var menuTracking = false
    private(set) var guidePlayback: GuidePlayback?
    private(set) var guideExamples: GuideExamples?
    let guidePanel = ClipGuidePanel()
    private let snapPreview = FloatingPanel()
    private var mergeCandidate: UUID?
    private var mergeSource: UUID?
    private var mergeWork: DispatchWorkItem?
    private var guideScreenID: String?
    private var observers: [NSObjectProtocol] = []
    private var monitors: [Any] = []
    private var fullScreenTimer: Timer?
    private var blockedScreens: Set<String> = []

    init(store: ClipStore) {
        self.store = store; pointClamp = PointClampController(store: store); super.init()
        store.onChange = { [weak self] in self?.pointClamp.refreshConfiguration(); self?.sync() }
        store.onReveal = { [weak self] id in self?.reveal(id) }
        store.onThumbnailChange = { [weak self] id in
            guard let self, let card = self.cards[id], card.expanded, !card.moving, !card.revealInFlight else { return }
            self.layout(card)
        }
        pointClamp.onPlace = { [weak self] id, point in self?.placeCaptured(id, at: point) }
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.store.reconcileScreens(); self?.sync() } })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.detectFullScreen(); self?.sync() } })
        observers.append(NotificationCenter.default.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.menuTracking = true } })
        observers.append(NotificationCenter.default.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.menuTracking = false; self?.cards.values.forEach { $0.hover($0.hovered) } } })
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in Task { @MainActor in self?.outsideClick() } }) { monitors.append(monitor) }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown], handler: { [weak self] event in
            MainActor.assumeIsolated {
                if event.type == .keyDown && event.keyCode == 53 { self?.closeDockedCards() }
                else if event.type != .keyDown { self?.outsideClick() }
            }
            return event
        }) { monitors.append(monitor) }
        // Low-frequency fallback for full-screen transitions that don't produce a Space notification.
        fullScreenTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in Task { @MainActor in self?.detectFullScreen() } }
        store.reconcileScreens(); sync(); detectFullScreen()
    }
    var hoverExpansionBlocked: Bool {
        HoverExpansionGate.blocks(mouseButtons: NSEvent.pressedMouseButtons,
                                  materialMoving: cards.values.contains { $0.moving || $0.busy },
                                  pointClamping: pointClamp.blocksHoverExpansion)
    }
    var compactWidth: CGFloat { DockGeometry.compactSize.width }
    func placement(_ id: UUID) -> ClipPlacement? {
        if let item = store.item(id) { return item.removedAt == nil ? item.placement : nil }
        return store.group(id)?.placement
    }
    func updatePlacement(_ id: UUID, _ body: (inout ClipPlacement) -> Void) {
        if store.item(id) != nil { store.update(id) { body(&$0.placement) } }
        else { store.updateGroup(id) { body(&$0.placement) } }
    }
    func screen(for placement: ClipPlacement) -> NSScreen? { NSScreen.screens.first { $0.stableID == placement.position.screenID } ?? NSScreen.main ?? NSScreen.screens.first }
    func dockedIDs(on screen: NSScreen, side: ClipSide) -> [UUID] {
        let singles = store.sceneItems.filter { $0.groupID == nil && $0.placement.mode == .docked && self.screen(for: $0.placement)?.stableID == screen.stableID && $0.placement.side == side }.map(\.id)
        let groups = store.sceneGroups.filter { $0.placement.mode == .docked && self.screen(for: $0.placement)?.stableID == screen.stableID && $0.placement.side == side }.map(\.id)
        return groups + singles
    }
    func sync() {
        if let source = mergeSource, !store.visibleInScene(source) { cancelGrouping(); hideSnapPreview() }
        if store.hidden { dismissGuide() }
        for card in cards.values where placement(card.id)?.mode == .docked { card.slot = .zero }
        let validIDs = Set(store.sceneItems.map(\.id) + store.sceneGroups.map(\.id))
        for id in Array(cards.keys) where !validIDs.contains(id) { cards[id]?.retire(); cards[id] = nil }
        let screenIDs = Set(NSScreen.screens.map(\.stableID))
        for id in Array(rails.keys) where !screenIDs.contains(id) { rails[id]?.orderOut(nil); rails[id] = nil }
        var visible: Set<UUID> = []
        for screen in NSScreen.screens {
            let frame = NSRect(x: screen.frame.minX, y: screen.visibleFrame.minY + 12, width: screen.frame.width, height: screen.visibleFrame.height - 24)
            let capacity = max(1, Int((frame.height - 130) / DockGeometry.spacing))
            let right = dockedIDs(on: screen, side: .right), left = dockedIDs(on: screen, side: .left)
            let overflow = max(0, right.count - capacity) + max(0, left.count - capacity)
            let rail = rails[screen.stableID] ?? FloatingPanel()
            rails[screen.stableID] = rail
            if store.state.preferences.showBrassClip {
                rail.contentView = NSHostingView(rootView: RailView(store: store, manager: self, overflow: overflow))
                rail.setFrame(NSRect(x: frame.maxX - 58, y: frame.maxY - 50, width: 58, height: 44), display: true)
                if shouldShow(on: screen) || guideScreenID == screen.stableID { rail.orderFrontRegardless() } else { rail.orderOut(nil) }
            } else {
                rail.orderOut(nil); rail.contentView = nil
            }
            for side in [ClipSide.left, .right] {
                let ids = side == .left ? left : right
                let shown = Array(ids.prefix(capacity))
                let origins = DockGeometry.origins(heights: shown.map { placement($0)?.dockHeight }, in: frame)
                for (index, id) in shown.enumerated() {
                    visible.insert(id)
                    let card = model(id)
                    card.slot = NSRect(x: side == .left ? frame.minX : frame.maxX - compactWidth, y: origins[index], width: compactWidth, height: DockGeometry.compactSize.height)
                    layout(card)
                }
            }
        }
        for item in store.sceneItems where item.placement.mode == .floating { visible.insert(item.id); layout(model(item.id)) }
        for group in store.sceneGroups where group.placement.mode == .floating { visible.insert(group.id); layout(model(group.id)) }
        for (id, card) in cards where !visible.contains(id) { card.panel.orderOut(nil) }
    }
    func model(_ id: UUID) -> CardModel {
        if let card = cards[id] { return card }
        let card = CardModel(id: id, manager: self); cards[id] = card
        card.panel.contentView = NSHostingView(rootView: CardSurface(store: store, model: card, manager: self))
        return card
    }
    func shouldShow(on screen: NSScreen) -> Bool { !store.hidden && !blockedScreens.contains(screen.stableID) }
    func layout(_ card: CardModel) {
        guard cards[card.id] === card, store.visibleInScene(card.id), let placement = placement(card.id) else { card.panel.orderOut(nil); return }
        if placement.mode == .docked, store.item(card.id)?.groupID != nil { card.panel.orderOut(nil); return }
        guard let screen = screen(for: placement), !card.moving else { return }
        let usable = NSRect(x: screen.frame.minX, y: screen.visibleFrame.minY + 12, width: screen.frame.width, height: screen.visibleFrame.height - 24)
        let floating = placement.mode == .floating
        if floating && !card.expanded { card.expanded = true; card.revealProgress = 1 }
        let wide = floating || card.expanded
        var width = min(usable.width, wide ? CGFloat(placement.width) : compactWidth)
        var height = min(usable.height, wide ? CGFloat(placement.height) : DockGeometry.compactSize.height)
        if wide {
            let fitted = MinimalSurfaceLayout.sheetSize(item: store.item(card.id), imageSize: store.images[card.id]?.size,
                                                        limit: CGSize(width: width, height: height),
                                                        scale: store.state.preferences.previewSizes[PreviewSizeKind.forItem(store.item(card.id))],
                                                        maximumSize: usable.size)
            width = fitted.width; height = fitted.height
        }
        let sheetSize = CGSize(width: width, height: height)
        if card.sheetSize != sheetSize { card.sheetSize = sheetSize }
        let origin: NSPoint
        if floating {
            origin = NSPoint(x: usable.minX + CGFloat(placement.position.x) * max(0, usable.width - width), y: usable.minY + CGFloat(placement.position.y) * max(0, usable.height - height))
        } else {
            let lift = wide ? HingeReveal.suspension(size: sheetSize, isLeft: placement.side == .left).y - ClipOrientation.compactHookY : 0
            origin = NSPoint(x: placement.side == .left ? usable.minX : usable.maxX - width,
                             y: min(usable.maxY - height, max(usable.minY, card.slot.maxY + lift - height)))
        }
        var frame = NSRect(origin: origin, size: sheetSize)
        // The page lifts beyond its resting outline. Grow transparent space
        // around it while keeping the sheet and clip at the same screen point.
        let turnInset = card.pageTurnInset
        frame.origin.y -= turnInset; frame.size.height += turnInset * 2
        let sideInset = card.pageTurnSideInset
        frame.origin.x -= sideInset; frame.size.width += sideInset * 2
        if wide && !floating && card.revealInFlight {
            // Extend only below the fixed sheet. The top and jaw stay in place.
            let extra = HingeReveal.swingHeight(size: sheetSize, isLeft: placement.side == .left) - height
            frame.origin.y -= extra; frame.size.height += extra
        }
        card.panel.setFrame(frame, display: true)
        if shouldShow(on: screen) { card.panel.orderFrontRegardless() } else { card.panel.orderOut(nil) }
    }
    func reveal(_ id: UUID) {
        guard placement(id) != nil else { return }
        if !store.visibleInScene(id) { store.selectScene(nil) }
        store.hidden = false
        let target: UUID
        if let item = store.item(id), let group = item.groupID, item.placement.mode != .floating { target = group } else { target = id }
        sync()
        let card = model(target)
        if placement(target)?.mode == .docked && card.slot == .zero { showLibrary(); return }
        card.show()
    }
    func dock(_ id: UUID) {
        cards[id]?.sticky = false; cards[id]?.expanded = false; cards[id]?.revealProgress = 0; cards[id]?.revealInFlight = false
        updatePlacement(id) { $0.mode = .docked }
        sync()
    }
    func float(_ id: UUID) {
        if !store.visibleInScene(id) { store.selectScene(nil) }
        updatePlacement(id) { $0.mode = .floating }
        cards[id]?.show(); sync()
    }
    func resize(_ id: UUID, delta: NSPoint, original: NSSize) {
        updatePlacement(id) { $0.width = min(900, max(280, original.width + delta.x)); $0.height = min(1000, max(300, original.height - delta.y)) }
        if let card = cards[id] { layout(card) }
    }
    func finishMove(_ card: CardModel, at destinationPoint: CGPoint? = nil) {
        let destination = mergeSource == card.id ? mergeCandidate : nil
        let ready = destination.flatMap { cards[$0]?.mergeReady } ?? false
        cancelGrouping()
        if ready, let destination, store.combine(card.id, with: destination) != nil { return }
        let point = destinationPoint ?? NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) ?? NSScreen.main else { return }
        let usable = NSRect(x: screen.frame.minX, y: screen.visibleFrame.minY + 12, width: screen.frame.width, height: screen.visibleFrame.height - 24)
        let preferences = store.state.preferences
        let side = preferences.autoSnap ? DockGeometry.side(at: point, in: usable, distance: preferences.snapDistance) : nil
        let left = side == .left, right = side == .right
        if side == nil && !card.expanded {
            // Keep a compact clip compact while dragging along the edge. Only
            // unfold after a floating drop, preserving its suspension point.
            let previous = card.panel.frame
            let wasLeft = placement(card.id)?.side == .left
            card.expanded = true; card.revealProgress = 1
            layout(card)
            card.panel.setFrameOrigin(NSPoint(x: wasLeft ? previous.minX : previous.maxX - card.panel.frame.width,
                                               y: previous.maxY - card.panel.frame.height))
        }
        updatePlacement(card.id) { placement in
            placement.userMoved(to: ScreenPosition(screenID: screen.stableID,
                x: Double(min(1, max(0, (card.panel.frame.minX - usable.minX) / max(1, usable.width - card.panel.frame.width)))),
                y: Double(min(1, max(0, (card.panel.frame.minY - usable.minY) / max(1, usable.height - card.panel.frame.height))))))
            placement.mode = left || right ? .docked : .floating
            if left || right {
                placement.side = left ? .left : .right
                placement.dockHeight = DockGeometry.height(at: point.y, in: usable)
            }
        }
        sync(); store.save()
        if left || right {
            store.tactile(.alignment)
            // Fold around the jaw; a window animator could keep moving the panel
            // after the user had already picked it up again.
            card.close()
        }
    }
    func placeCaptured(_ id: UUID, at point: CGPoint) {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) else { return }
        let usable = NSRect(x: screen.frame.minX, y: screen.visibleFrame.minY + 12, width: screen.frame.width, height: screen.visibleFrame.height - 24)
        let preferences = store.state.preferences
        let side = preferences.autoSnap ? DockGeometry.side(at: point, in: usable, distance: preferences.snapDistance) : nil
        updatePlacement(id) { placement in
            placement.userMoved(to: ScreenPosition(screenID: screen.stableID,
                x: Double(max(0, min(1, (point.x - usable.minX - CGFloat(placement.width) + ClipOrientation.edgeAnchor) / max(1, usable.width - CGFloat(placement.width))))),
                y: Double(max(0, min(1, (point.y - usable.minY - CGFloat(placement.height) + ClipOrientation.contactY) / max(1, usable.height - CGFloat(placement.height)))))))
            placement.mode = side == nil ? .floating : .docked
            if let side { placement.side = side; placement.dockHeight = DockGeometry.height(at: point.y, in: usable) }
        }
        let card = model(id)
        if side == nil { card.present() }
        else { card.sticky = false; card.expanded = false; card.revealProgress = 0 }
        sync(); store.save()
    }
    func outsideClick() {
        guard !menuTracking else { return }
        let point = NSEvent.mouseLocation
        if guidePanel.isVisible && guidePanel.frame.contains(point) { return }
        dismissGuide()
        for card in cards.values where !card.panel.frame.contains(point) && placement(card.id)?.mode == .docked && !card.busy && !card.moving { card.close() }
    }
    func closeDockedCards() {
        dismissGuide()
        for card in cards.values where placement(card.id)?.mode == .docked { card.close() }
    }
    func showGuide() {
        dismissGuide(); settingsWindow?.close()
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main else { return }
        guideScreenID = screen.stableID; store.hidden = false; sync()
        let playback = GuidePlayback(), examples = GuideExamples()
        guidePlayback = playback; guideExamples = examples
        guidePanel.title = "屏幕夹子 · 动态使用指引"
        let size = ClipGuideView.size
        let scale = min(1, min((screen.visibleFrame.width - 32) / size.width, (screen.visibleFrame.height - 32) / size.height))
        guidePanel.contentView = NSHostingView(rootView: ClipGuideView(playback: playback, examples: examples,
            preferences: store.state.preferences, close: { [weak self] in self?.dismissGuide() })
            .scaleEffect(scale).frame(width: size.width * scale, height: size.height * scale))
        guidePanel.setFrame(NSRect(x: screen.visibleFrame.midX - size.width * scale / 2,
            y: screen.visibleFrame.midY - size.height * scale / 2, width: size.width * scale, height: size.height * scale), display: true)
        NSApp.activate(ignoringOtherApps: true); guidePanel.makeKeyAndOrderFront(nil)
        playback.play()
    }
    func dismissGuide() {
        if let id = guideScreenID, blockedScreens.contains(id) || store.hidden { rails[id]?.orderOut(nil) }
        guidePlayback?.pause(); guidePlayback = nil; guideExamples = nil
        guideScreenID = nil; guidePanel.orderOut(nil); guidePanel.contentView = nil
    }
    func toggleVisibility() { store.hidden.toggle(); sync() }
    func showLibrary() {
        if libraryWindow == nil {
            libraryWindow = makeWindow(title: "夹项与恢复", size: NSSize(width: 950, height: 650), content: LibraryView(store: store, manager: self))
        }
        NSApp.activate(ignoringOtherApps: true); libraryWindow?.makeKeyAndOrderFront(nil)
    }
    func updateGrouping(source: UUID, at point: CGPoint) {
        let candidate = cards.values.filter {
            $0.id != source && $0.panel.isVisible && $0.panel.frame.contains(point) && store.canCombine(source, with: $0.id)
        }.sorted { $0.panel.frame.width * $0.panel.frame.height < $1.panel.frame.width * $1.panel.frame.height }.first?.id
        guard candidate != mergeCandidate || source != mergeSource else { return }
        cancelGrouping()
        guard let candidate else { return }
        mergeCandidate = candidate; mergeSource = source
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.mergeCandidate == candidate, self.mergeSource == source,
                  self.cards[source]?.moving == true else { return }
            self.cards[candidate]?.mergeReady = true
        }
        mergeWork = work; DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: work)
    }
    func cancelGrouping() {
        mergeWork?.cancel(); mergeWork = nil
        if let candidate = mergeCandidate { cards[candidate]?.mergeReady = false }
        mergeCandidate = nil; mergeSource = nil
    }
    func showSnapPreview(at point: CGPoint) {
        guard store.state.preferences.autoSnap,
              let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }),
              let side = DockGeometry.side(at: point, in: screen.frame, distance: store.state.preferences.snapDistance) else { hideSnapPreview(); return }
        let frame = NSRect(x: screen.frame.minX, y: screen.visibleFrame.minY + 12, width: screen.frame.width, height: screen.visibleFrame.height - 24)
        snapPreview.ignoresMouseEvents = true
        if snapPreview.contentView == nil {
        snapPreview.contentView = NSHostingView(rootView: RoundedRectangle(cornerRadius: 8)
            .fill(ClipStyle.accent.opacity(0.2))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(ClipStyle.accent, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])))
            .overlay(Text("松手吸附").font(.system(size: 10)).foregroundStyle(.white)).padding(2))
        }
        snapPreview.setFrame(NSRect(x: side == .left ? frame.minX : frame.maxX - compactWidth,
            y: DockGeometry.originY(height: DockGeometry.height(at: point.y, in: frame), index: 0, in: frame), width: compactWidth, height: DockGeometry.compactSize.height), display: true)
        if !snapPreview.isVisible { snapPreview.orderFrontRegardless() }
    }
    func hideSnapPreview() { if snapPreview.isVisible { snapPreview.orderOut(nil) } }
    func showSettings(section: String? = nil) {
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 530), styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
            window.title = "屏幕夹子 · 设置"; window.titleVisibility = .hidden; window.titlebarAppearsTransparent = true
            window.isOpaque = false; window.backgroundColor = .clear; window.hasShadow = false
            window.isMovableByWindowBackground = true; window.isReleasedWhenClosed = false
            window.standardWindowButton(.closeButton)?.isHidden = true
            window.standardWindowButton(.miniaturizeButton)?.isHidden = true
            window.standardWindowButton(.zoomButton)?.isHidden = true
            window.contentView = NSHostingView(rootView: SettingsView(store: store, manager: self))
            window.center(); settingsWindow = window
        }
        if let section {
            settingsWindow?.contentView = NSHostingView(rootView: SettingsView(store: store, manager: self, initialSection: section))
        }
        NSApp.activate(ignoringOtherApps: true); settingsWindow?.makeKeyAndOrderFront(nil)
    }
    func edit(_ id: UUID) {
        cards[id]?.interaction(true)
        if editors[id] == nil {
            let window = makeWindow(title: "编辑纸签", size: NSSize(width: 450, height: 440), content: EditorView(store: store, id: id, done: { [weak self] in self?.editors[id]?.close() }))
            window.identifier = NSUserInterfaceItemIdentifier(id.uuidString); window.delegate = self; editors[id] = window
        }
        NSApp.activate(ignoringOtherApps: true); editors[id]?.makeKeyAndOrderFront(nil)
    }
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, let value = window.identifier?.rawValue, let id = UUID(uuidString: value) else { return }
        editors[id] = nil; cards[id]?.interaction(false)
    }
    func makeWindow<Content: View>(title: String, size: NSSize, content: Content) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = title; window.contentView = NSHostingView(rootView: content); window.isReleasedWhenClosed = false; window.center(); window.minSize = NSSize(width: min(size.width, 420), height: 340)
        return window
    }
    func shutdown() {
        cancelGrouping(); hideSnapPreview(); snapPreview.contentView = nil
        dismissGuide(); guidePanel.contentView = nil
        pointClamp.shutdown()
        fullScreenTimer?.invalidate()
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
        monitors.removeAll()
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        observers.removeAll()
        for card in cards.values { card.retire() }
        cards.removeAll()
        for rail in rails.values { rail.orderOut(nil); rail.contentView = nil }
        rails.removeAll()
    }
    func detectFullScreen() {
        guard store.state.preferences.hideInFullScreen else {
            if !blockedScreens.isEmpty { blockedScreens = []; sync() }; return
        }
        // Public window-list geometry, deliberately conservative: only a frontmost app
        // window covering the entire display. No accessibility or screen capture access.
        let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier
        guard pid != ProcessInfo.processInfo.processIdentifier,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return }
        var blocked: Set<String> = []
        for window in windows {
            guard (window[kCGWindowOwnerPID as String] as? Int32) == pid,
                  (window[kCGWindowLayer as String] as? Int) == 0,
                  let dictionary = window[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: dictionary as CFDictionary) else { continue }
            for screen in NSScreen.screens {
                guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { continue }
                let display = CGDisplayBounds(CGDirectDisplayID(number.uint32Value))
                if abs(bounds.minX - display.minX) < 2 && abs(bounds.minY - display.minY) < 2 && bounds.width >= display.width - 2 && bounds.height >= display.height - 2 { blocked.insert(screen.stableID) }
            }
        }
        if blocked != blockedScreens { blockedScreens = blocked; sync() }
    }
}
