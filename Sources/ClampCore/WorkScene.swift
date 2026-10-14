import Foundation

/// Scenes share the original items. Switching context never copies or removes content.
public struct WorkScene: Identifiable, Codable, Equatable {
    public var id = UUID()
    public var title: String
    public var itemIDs: Set<UUID>
    public init(title: String, itemIDs: Set<UUID>) { self.title = title; self.itemIDs = itemIDs }
}
