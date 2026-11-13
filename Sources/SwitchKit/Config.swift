import Foundation

/// What the user changed about the menu: order and visibility.
///
/// Unknown ids are ignored when the menu is built, so removing a switch from a
/// later build never breaks an existing config file.
public struct SwitchDeckConfig: Codable, Equatable {
    /// Preferred order. Ids not listed here come after these, in catalog order.
    public var order: [String]
    public var disabled: Set<String>
    public var hotkeys: [String: HotkeyBinding]
    /// Set once the user closes the setup window, so it only opens by itself
    /// on a fresh install.
    public var didCompleteSetup: Bool
    /// ⌥E is installed once as the default screenshot shortcut.
    public var didSeedScreenshotShortcut: Bool

    public init(
        order: [String] = [],
        disabled: Set<String> = [],
        hotkeys: [String: HotkeyBinding] = [:],
        didCompleteSetup: Bool = false,
        didSeedScreenshotShortcut: Bool = false
    ) {
        self.order = order
        self.disabled = disabled
        self.hotkeys = hotkeys
        self.didCompleteSetup = didCompleteSetup
        self.didSeedScreenshotShortcut = didSeedScreenshotShortcut
    }

    // Decoded field by field so a config written by an older build still loads.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        order = try container.decodeIfPresent([String].self, forKey: .order) ?? []
        disabled = try container.decodeIfPresent(Set<String>.self, forKey: .disabled) ?? []
        hotkeys = try container.decodeIfPresent([String: HotkeyBinding].self, forKey: .hotkeys) ?? [:]
        didCompleteSetup = try container.decodeIfPresent(Bool.self, forKey: .didCompleteSetup) ?? false
        didSeedScreenshotShortcut = try container.decodeIfPresent(Bool.self, forKey: .didSeedScreenshotShortcut) ?? false
    }

    /// Applies the saved order, then slips ids the config has never seen in next
    /// to their catalog neighbours (so a new switch lands where it was designed,
    /// not at the bottom of the menu).
    public func orderedIDs(from allIDs: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []

        for id in order where allIDs.contains(id) && seen.insert(id).inserted {
            result.append(id)
        }

        for (catalogIndex, id) in allIDs.enumerated() where !seen.contains(id) {
            if let next = allIDs[(catalogIndex + 1)...].first(where: { result.contains($0) }),
               let position = result.firstIndex(of: next) {
                result.insert(id, at: position)
            } else {
                result.append(id)
            }
            seen.insert(id)
        }

        return result
    }

    public func isEnabled(_ id: String) -> Bool {
        !disabled.contains(id)
    }

    public mutating func setEnabled(_ enabled: Bool, for id: String) {
        if enabled {
            disabled.remove(id)
        } else {
            disabled.insert(id)
        }
    }

    public func hotkey(for id: String) -> HotkeyBinding? {
        hotkeys[id]
    }

    /// Passing nil clears the shortcut.
    public mutating func setHotkey(_ binding: HotkeyBinding?, for id: String) {
        if let binding {
            hotkeys[id] = binding
        } else {
            hotkeys.removeValue(forKey: id)
        }
    }

    /// Moves an id one position up (-1) or down (+1) inside `allIDs`.
    public mutating func move(_ id: String, by offset: Int, allIDs: [String]) {
        var ids = orderedIDs(from: allIDs)
        guard let index = ids.firstIndex(of: id) else { return }
        let target = index + offset
        guard ids.indices.contains(target) else { return }
        ids.swapAt(index, target)
        order = ids
    }

    /// Drag reordering: moves a set of indices to SwiftUI's insertion point,
    /// with the same semantics as `Array.move(fromOffsets:toOffset:)` (which
    /// lives in SwiftUI, so it is spelled out here).
    public mutating func move(fromOffsets source: IndexSet, toOffset destination: Int, allIDs: [String]) {
        let ids = orderedIDs(from: allIDs)
        let moving = source.compactMap { ids.indices.contains($0) ? ids[$0] : nil }
        guard !moving.isEmpty else { return }

        var remaining: [String] = []
        for (index, id) in ids.enumerated() where !source.contains(index) {
            remaining.append(id)
        }

        let removedBeforeDestination = source.filter { $0 < destination }.count
        let insertion = max(0, min(remaining.count, destination - removedBeforeDestination))
        remaining.insert(contentsOf: moving, at: insertion)
        order = remaining
    }
}

public final class ConfigStore {
    public private(set) var config: SwitchDeckConfig
    public let url: URL

    public init(url: URL = ConfigStore.defaultURL()) {
        self.url = url
        self.config = Self.load(from: url)
    }

    public static func defaultURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("SwitchDeck/config.json")
    }

    private static func load(from url: URL) -> SwitchDeckConfig {
        guard let data = try? Data(contentsOf: url),
              let config = try? JSONDecoder().decode(SwitchDeckConfig.self, from: data)
        else {
            return SwitchDeckConfig()
        }
        return config
    }

    public func update(_ body: (inout SwitchDeckConfig) -> Void) {
        body(&config)
        save()
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(config).write(to: url, options: .atomic)
        } catch {
            NSLog("SwitchDeck: could not save config to \(url.path): \(error.localizedDescription)")
        }
    }
}
