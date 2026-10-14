import AppKit
import ApplicationServices
import ScreenCaptureKit
import UniformTypeIdentifiers
import ClampCore

struct PointTarget: Sendable {
    enum Payload: Sendable { case file(URL), text(String), link(URL), image(CGRect) }
    let payload: Payload
    let title: String
    var bounds: CGRect? = nil
    var regions: [CGRect] = []
    var fileKind: ClipKind? = nil
}

/// An image is frozen during pickup, never re-read at the drop destination.
struct PreparedPointTarget {
    let target: PointTarget
    let image: CGImage?
    var fileKind: ClipKind? = nil
}

struct PointCandidate {
    var role: String
    var secure = false
    var url: URL?
    var selectedText: String?
    var text: String?
    var title: String?
    var rect: CGRect?
    var selectionRect: CGRect?
    var textRegions: [CGRect] = []
    var fileKind: ClipKind? = nil
}

enum PointCaptureError: LocalizedError {
    case unavailable, secure, permission, imagePermission
    var errorDescription: String? {
        switch self {
        case .unavailable: return "这里没有可读取的内容。可先选中文字，或把文件拖到黄铜夹子。"
        case .secure: return "此处是受保护的输入内容，不能夹取。"
        case .permission: return "请在设置 → 鼠标夹取中允许辅助功能。"
        case .imagePermission: return "截取图片区域需要屏幕录制权限，请在鼠标夹取设置中开启。"
        }
    }
}

/// Reads only the clicked element and a bounded parent chain, never an entire app tree.
enum PointCapture {
    static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }
    static func string(_ element: AXUIElement, _ name: String) -> String? { attribute(element, name) as? String }
    static func url(_ element: AXUIElement) -> URL? {
        if let value = attribute(element, kAXURLAttribute) as? URL { return value }
        return string(element, kAXURLAttribute).flatMap(URL.init(string:))
    }
    static func parent(_ element: AXUIElement) -> AXUIElement? {
        guard let value = attribute(element, kAXParentAttribute), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }
    static func bounds(_ element: AXUIElement) -> CGRect? {
        guard let p = attribute(element, kAXPositionAttribute), let s = attribute(element, kAXSizeAttribute),
              CFGetTypeID(p) == AXValueGetTypeID(), CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero; var size = CGSize.zero
        guard AXValueGetValue(p as! AXValue, .cgPoint, &point), AXValueGetValue(s as! AXValue, .cgSize, &size), size.width > 1, size.height > 1 else { return nil }
        return CGRect(origin: point, size: size)
    }
    static func selectionBounds(_ element: AXUIElement) -> CGRect? {
        guard let range = attribute(element, kAXSelectedTextRangeAttribute) else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(element, kAXBoundsForRangeParameterizedAttribute as CFString, range, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var rect = CGRect.zero
        guard AXValueGetValue(value as! AXValue, .cgRect, &rect), rect.width > 1, rect.height > 1 else { return nil }
        return rect
    }
    static func parameter(_ element: AXUIElement, _ name: String, _ parameter: CFTypeRef) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(element, name as CFString, parameter, &value) == .success else { return nil }
        return value
    }
    /// Use native visual line ranges, including soft wrapping. Bound work on long documents.
    static func textRegions(_ element: AXUIElement, selected: Bool, text: String?) throws -> [CGRect] {
        var range = CFRange(location: 0, length: text?.utf16.count ?? 0)
        if selected {
            guard let value = attribute(element, kAXSelectedTextRangeAttribute), CFGetTypeID(value) == AXValueGetTypeID(),
                  AXValueGetValue(value as! AXValue, .cfRange, &range) else { return [] }
        }
        guard range.location >= 0, range.length > 0, range.location < Int.max - range.length,
              let first = parameter(element, kAXLineForIndexParameterizedAttribute, NSNumber(value: range.location)) as? NSNumber,
              let last = parameter(element, kAXLineForIndexParameterizedAttribute, NSNumber(value: range.location + range.length - 1)) as? NSNumber,
              first.intValue >= 0, last.intValue >= first.intValue,
              last.intValue - first.intValue < 24 else { return [] }
        let deadline = Date().addingTimeInterval(0.16)
        var result: [CGRect] = []
        for line in first.intValue...last.intValue {
            try Task.checkCancellation()
            guard Date() < deadline,
                  let lineValue = parameter(element, kAXRangeForLineParameterizedAttribute, NSNumber(value: line)),
                  CFGetTypeID(lineValue) == AXValueGetTypeID() else { return [] }
            var lineRange = CFRange()
            guard AXValueGetValue(lineValue as! AXValue, .cfRange, &lineRange),
                  lineRange.location >= 0, lineRange.length >= 0, lineRange.location < Int.max - lineRange.length else { return [] }
            let start = max(range.location, lineRange.location), end = min(range.location + range.length, lineRange.location + lineRange.length)
            if end <= start { continue }
            var intersection = CFRange(location: start, length: end - start)
            guard let axRange = AXValueCreate(.cfRange, &intersection),
                  let rectValue = parameter(element, kAXBoundsForRangeParameterizedAttribute, axRange),
                  CFGetTypeID(rectValue) == AXValueGetTypeID() else { return [] }
            var rect = CGRect.zero
            guard AXValueGetValue(rectValue as! AXValue, .cgRect, &rect), rect.width > 1, rect.height > 1 else { return [] }
            result.append(rect)
        }
        return result
    }
    static func target(at point: CGPoint) throws -> PointTarget {
        guard AXIsProcessTrusted() else { throw PointCaptureError.permission }
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.25)
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y), &hit) == .success, let hit else { throw PointCaptureError.unavailable }
        var process: pid_t = 0; AXUIElementGetPid(hit, &process)
        guard process != ProcessInfo.processInfo.processIdentifier else { throw PointCaptureError.unavailable }
        var chain: [AXUIElement] = []; var cursor: AXUIElement? = hit
        for _ in 0..<6 {
            try Task.checkCancellation()
            guard let element = cursor else { break }
            AXUIElementSetMessagingTimeout(element, 0.2)
            if string(element, kAXSubroleAttribute) == kAXSecureTextFieldSubrole { throw PointCaptureError.secure }
            chain.append(element)
            let role = string(element, kAXRoleAttribute)
            if role == kAXWindowRole || role == kAXApplicationRole || role == "AXWebArea" { break }
            cursor = parent(element)
        }
        let candidates = try chain.map { element -> PointCandidate in
            try Task.checkCancellation()
            let role = string(element, kAXRoleAttribute) ?? ""
            let boundary = [kAXWindowRole, kAXApplicationRole, "AXWebArea"].contains(role)
            let selected = string(element, kAXSelectedTextAttribute)
            let hasSelection = selected?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            let text = boundary ? nil : (string(element, kAXValueAttribute) ?? string(element, kAXTitleAttribute))
            let isText = [kAXStaticTextRole, kAXTextFieldRole, kAXTextAreaRole].contains(role)
            let targetURL = boundary ? nil : url(element)
            var kind: ClipKind?
            if let targetURL, targetURL.isFileURL {
                let values = try? targetURL.resourceValues(forKeys: [.isDirectoryKey, .contentTypeKey])
                kind = values?.isDirectory == true || targetURL.hasDirectoryPath ? .folder : (values?.contentType?.conforms(to: .image) == true ? .image : .file)
            }
            return PointCandidate(role: role, url: targetURL, selectedText: selected, text: text,
                title: boundary ? nil : (string(element, kAXTitleAttribute) ?? string(element, kAXDescriptionAttribute)),
                rect: boundary ? nil : bounds(element), selectionRect: hasSelection ? selectionBounds(element) : nil,
                textRegions: hasSelection || isText ? try textRegions(element, selected: hasSelection, text: text) : [], fileKind: kind)
        }
        return try resolve(candidates)
    }

    static func resolve(_ candidates: [PointCandidate]) throws -> PointTarget {
        guard !candidates.contains(where: \.secure) else { throw PointCaptureError.secure }
        // A file keeps its identity; an explicit text selection beats a parent link.
        for candidate in candidates {
            if let url = candidate.url, url.isFileURL { return PointTarget(payload: .file(url), title: url.lastPathComponent, bounds: candidate.rect, fileKind: candidate.fileKind) }
        }
        for candidate in candidates {
            if let text = candidate.selectedText, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return PointTarget(payload: .text(text), title: "选中的文字", bounds: candidate.selectionRect ?? candidate.rect, regions: candidate.textRegions)
            }
        }
        for candidate in candidates {
            if let url = candidate.url, ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
                return PointTarget(payload: .link(url), title: candidate.title ?? url.host ?? "链接", bounds: candidate.rect)
            }
        }
        for candidate in candidates.prefix(3) {
            if [kAXStaticTextRole, kAXTextFieldRole, kAXTextAreaRole].contains(candidate.role),
               let text = candidate.text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return PointTarget(payload: .text(text), title: "夹取的文字", bounds: candidate.rect, regions: candidate.textRegions)
            }
        }
        for candidate in candidates {
            if [kAXImageRole, "AXButton", "AXDockItem", "AXMenuItem", "AXCell"].contains(candidate.role),
               let rect = candidate.rect, rect.width.isFinite, rect.height.isFinite,
               rect.origin.x.isFinite, rect.origin.y.isFinite, rect.width > 1, rect.height > 1 {
                return PointTarget(payload: .image(rect), title: candidate.title ?? "夹取的图片", bounds: rect)
            }
        }
        throw PointCaptureError.unavailable
    }

    @MainActor static func prepare(at point: CGPoint,
        resolve: @escaping @Sendable (CGPoint) throws -> PointTarget = { try target(at: $0) },
        snapshot: @escaping @MainActor (CGRect, CGPoint) async throws -> CGImage = { try await image(in: $0, at: $1) }
    ) async throws -> PreparedPointTarget {
        let reader = Task.detached(priority: .userInitiated) { try resolve(point) }
        return try await withTaskCancellationHandler {
            let target = try await reader.value
            try Task.checkCancellation()
            let captured: CGImage?
            if case .image(let rect) = target.payload { captured = try await snapshot(rect, point) }
            else { captured = nil }
            try Task.checkCancellation()
            var kind = target.fileKind
            if case .file(let url) = target.payload, kind == nil {
                let metadata = Task.detached(priority: .utility) { () throws -> ClipKind in
                    let values = try url.resourceValues(forKeys: [.isDirectoryKey, .contentTypeKey])
                    return values.isDirectory == true ? .folder : (values.contentType?.conforms(to: .image) == true ? .image : .file)
                }
                kind = try await withTaskCancellationHandler { try await metadata.value } onCancel: { metadata.cancel() }
            }
            try Task.checkCancellation()
            return PreparedPointTarget(target: target, image: captured, fileKind: kind)
        } onCancel: { reader.cancel() }
    }
    @MainActor static func image(in rect: CGRect, at point: CGPoint) async throws -> CGImage {
        guard CGPreflightScreenCaptureAccess() else { throw PointCaptureError.imagePermission }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.frame.contains(point) }) else { throw PointCaptureError.unavailable }
        let clipped = rect.intersection(display.frame)
        guard !clipped.isNull, clipped.width > 1, clipped.height > 1 else { throw PointCaptureError.unavailable }
        let ownApps = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
        let filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])
        let config = SCStreamConfiguration()
        config.sourceRect = clipped.offsetBy(dx: -display.frame.minX, dy: -display.frame.minY)
        let scale = NSScreen.screens.first { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == display.displayID }?.backingScaleFactor ?? 2
        config.width = max(1, Int(clipped.width * scale)); config.height = max(1, Int(clipped.height * scale))
        config.showsCursor = false; config.captureResolution = .best
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }
}
