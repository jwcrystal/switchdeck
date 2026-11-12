import Combine
import Foundation
import SwitchKit

/// Owns the catalog and the saved config, publishes changes so the menu and the
/// settings window stay in sync, and keeps global shortcuts in step with the
/// config.
@MainActor
final class AppModel: ObservableObject {
    let catalog: SwitchCatalog
    private let store: ConfigStore
    private let hotkeys = HotkeyCenter()

    @Published private(set) var config: SwitchDeckConfig
    /// Shortcut problems to show in Settings › Shortcuts. Empty means all good.
    @Published private(set) var hotkeyIssues: [String] = []

    /// Set by the menu controller: runs one switch by id, with error reporting.
    var runSwitch: ((String) -> Void)?

    init(catalog: SwitchCatalog = .standard(), store: ConfigStore = ConfigStore()) {
        self.catalog = catalog
        self.store = store
        self.config = store.config
        seedScreenshotShortcutIfNeeded()
        registerHotkeys()
    }

    /// Installs ⌥E once, matching HapiGo's default screenshot shortcut. Later,
    /// the user can change or clear it in Settings › Shortcuts.
    private func seedScreenshotShortcutIfNeeded() {
        guard !config.didSeedScreenshotShortcut else { return }

        var updated = config
        updated.didSeedScreenshotShortcut = true
        if updated.hotkey(for: "screenshot") == nil {
            updated.setHotkey(
                HotkeyBinding(keyCode: 14, modifiers: HotkeyBinding.optionModifier, label: "E"),
                for: "screenshot"
            )
        }

        store.update { $0 = updated }
        config = store.config
    }

    /// Every switch in the user's order, including hidden ones (settings list).
    var orderedItems: [SwitchItem] {
        config.orderedIDs(from: catalog.ids).compactMap(catalog.item(id:))
    }

    /// Only the switches shown in the menu.
    var menuItems: [SwitchItem] {
        orderedItems.filter { config.isEnabled($0.id) }
    }

    func setEnabled(_ id: String, _ enabled: Bool) {
        update { $0.setEnabled(enabled, for: id) }
    }

    func setHotkey(_ binding: HotkeyBinding?, for id: String) {
        update { $0.setHotkey(binding, for: id) }
    }

    func markSetupComplete() {
        guard !config.didCompleteSetup else { return }
        update { $0.didCompleteSetup = true }
    }

    func move(_ id: String, by offset: Int) {
        update { $0.move(id, by: offset, allIDs: catalog.ids) }
    }

    /// Drag reordering from the Customize list. `destination` is SwiftUI's
    /// insertion index over the full list, hidden switches included.
    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        update { $0.move(fromOffsets: source, toOffset: destination, allIDs: catalog.ids) }
    }

    private func update(_ body: (inout SwitchDeckConfig) -> Void) {
        store.update(body)
        config = store.config
        registerHotkeys()
    }

    /// Re-registers every shortcut after a config change.
    ///
    /// Conflict checks: identical bindings inside the app are caught here, and
    /// combinations another app already owns fail inside Carbon.
    private func registerHotkeys() {
        hotkeys.unregisterAll()

        var issues: [String] = []
        var owners: [HotkeyBinding: String] = [:]

        for item in menuItems {
            guard let binding = config.hotkey(for: item.id) else { continue }

            guard binding.isUsable else {
                issues.append("\(item.title): \(binding.displayString) needs ⌘, ⌥ or ⌃.")
                continue
            }

            if let ownerID = owners[binding] {
                let owner = catalog.item(id: ownerID)?.title ?? ownerID
                issues.append("\(item.title): \(binding.displayString) is already used by \(owner).")
                continue
            }

            do {
                try hotkeys.register(binding) { [weak self] in
                    self?.runSwitch?(item.id)
                }
                owners[binding] = item.id
            } catch {
                issues.append("\(item.title): \(error.localizedDescription)")
            }
        }

        hotkeyIssues = issues
    }
}
