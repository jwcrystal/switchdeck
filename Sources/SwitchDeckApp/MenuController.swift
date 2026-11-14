import AppKit
import Combine
import SwitchKit

/// Builds and owns the status-bar menu.
@MainActor
final class MenuController: NSObject, NSMenuDelegate {
    private final class ItemBox: NSObject {
        let item: SwitchItem
        init(_ item: SwitchItem) { self.item = item }
    }

    private final class ActionBox: NSObject {
        let run: () throws -> Void
        let isChecked: () -> Bool
        init(_ run: @escaping () throws -> Void, isChecked: @escaping () -> Bool) {
            self.run = run
            self.isChecked = isChecked
        }
    }

    private let statusItem: NSStatusItem
    private let model: AppModel
    private var cancellables: Set<AnyCancellable> = []
    private var isMenuOpen = false
    private var needsRebuild = false

    var openSettings: () -> Void = {}
    var openPermissions: () -> Void = {}

    init(model: AppModel) {
        self.model = model
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        let button = statusItem.button
        button?.image = NSImage(
            systemSymbolName: "switch.2",
            accessibilityDescription: "SwitchDeck"
        ) ?? NSImage(systemSymbolName: "power", accessibilityDescription: "SwitchDeck")
        button?.image?.isTemplate = true
        button?.toolTip = "SwitchDeck"

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        model.$config
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.rebuild() }
            .store(in: &cancellables)

        model.runSwitch = { [weak self] id in
            self?.performSwitch(id: id)
        }

        rebuild()
    }

    /// Subtitle column: live state first, then the shortcut, so the menu says
    /// "Until 18:30  ⌃⌥K" the way the original does.
    private func menuSubtitle(for item: SwitchItem) -> String? {
        let parts = [
            item.subtitle(),
            model.config.hotkey(for: item.id)?.displayString,
        ].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: "  ")
    }

    // MARK: - Menu construction

    private func rebuild() {
        // Never mutate a menu that is on screen: AppKit keeps painting the old
        // rows and the list looks duplicated. Defer until the menu closes.
        guard !isMenuOpen else {
            needsRebuild = true
            return
        }

        let menu = NSMenu()
        menu.delegate = self

        // Belt and braces: even if a config ever lists an id twice, the menu
        // shows each switch once.
        var seen = Set<String>()
        for item in model.menuItems where seen.insert(item.id).inserted {
            let menuItem = NSMenuItem(title: item.title, action: #selector(runItem(_:)), keyEquivalent: "")
            menuItem.target = self
            menuItem.representedObject = ItemBox(item)
            menuItem.image = symbol(item.symbolName)
            menuItem.attributedTitle = MenuTitle.make(item.title, subtitle: menuSubtitle(for: item))

            let actions = item.actions()
            if !actions.isEmpty {
                menuItem.submenu = makeSubmenu(actions)
            }

            menu.addItem(menuItem)
        }

        menu.addItem(.separator())

        let permissionsItem = NSMenuItem(
            title: t("Permissions…"),
            action: #selector(showPermissions),
            keyEquivalent: ""
        )
        permissionsItem.target = self
        permissionsItem.image = symbol("checkmark.shield")
        menu.addItem(permissionsItem)

        let checkForUpdatesItem = NSMenuItem(
            title: t("Check for Updates…"),
            action: #selector(checkForUpdates),
            keyEquivalent: ""
        )
        checkForUpdatesItem.target = self
        checkForUpdatesItem.image = symbol("arrow.down.circle")
        menu.addItem(checkForUpdatesItem)

        let settings = NSMenuItem(title: t("Settings…"), action: #selector(showSettings), keyEquivalent: "")
        settings.target = self
        settings.image = symbol("gearshape")
        menu.addItem(settings)

        let quit = NSMenuItem(title: t("Quit SwitchDeck"), action: #selector(quit), keyEquivalent: "")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
    }

    private func makeSubmenu(_ actions: [SwitchItem.MenuAction]) -> NSMenu {
        let submenu = NSMenu()
        for action in actions {
            if action.startsSection, !submenu.items.isEmpty {
                submenu.addItem(.separator())
            }
            let menuItem = NSMenuItem(title: action.title, action: #selector(runAction(_:)), keyEquivalent: "")
            menuItem.target = self
            menuItem.representedObject = ActionBox(action.perform, isChecked: action.isChecked)
            menuItem.state = action.isChecked() ? .on : .off
            submenu.addItem(menuItem)
        }
        return submenu
    }

    private func symbol(_ name: String) -> NSImage? {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        image?.isTemplate = true
        return image
    }

    // MARK: - NSMenuDelegate

    func menuWillOpen(_ menu: NSMenu) {
        isMenuOpen = true
        for menuItem in menu.items {
            guard let box = menuItem.representedObject as? ItemBox else { continue }
            let item = box.item
            menuItem.state = (item.kind == .toggle && item.state()) ? .on : .off
            menuItem.attributedTitle = MenuTitle.make(item.title, subtitle: menuSubtitle(for: item))
            // Submenus are built once per rebuild, so refresh their checkmarks here.
            for subitem in menuItem.submenu?.items ?? [] {
                guard let action = subitem.representedObject as? ActionBox else { continue }
                subitem.state = action.isChecked() ? .on : .off
            }
        }
    }

    func menuDidClose(_ menu: NSMenu) {
        isMenuOpen = false
        if needsRebuild {
            needsRebuild = false
            rebuild()
        }
    }

    // MARK: - Actions

    @objc private func runItem(_ sender: NSMenuItem) {
        guard let box = sender.representedObject as? ItemBox else { return }
        perform { try box.item.perform() }
    }

    /// Entry point for a global shortcut: same path as clicking the row.
    func performSwitch(id: String) {
        guard let item = model.catalog.item(id: id) else { return }
        perform { try item.perform() }
    }

    /// Debug only (`--show-menu`): opens the menu so a screenshot can check it.
    func openMenuForDebug() {
        NSApp.activate(ignoringOtherApps: true)
        guard let menu = statusItem.menu, let button = statusItem.button else { return }
        menu.popUp(
            positioning: nil,
            at: NSPoint(x: 0, y: button.bounds.height + 4),
            in: button
        )
    }

    @objc private func runAction(_ sender: NSMenuItem) {
        guard let box = sender.representedObject as? ActionBox else { return }
        perform { try box.run() }
    }

    @objc private func checkForUpdates() {
        // `swift build` bundles carry no Info.plist version; treat that as 0.0.0.
        let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        let checker = UpdateChecker(currentVersion: current)

        Task {
            do {
                switch try await checker.check() {
                case .updateAvailable(let release):
                    showUpdateAvailable(release, currentVersion: current)
                case .upToDate:
                    showUpToDate(currentVersion: current)
                }
            } catch {
                showUpdateFailure(error)
            }
        }
    }

    private func showUpdateAvailable(_ release: ReleaseInfo, currentVersion: String) {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = tf("SwitchDeck %@ is available", release.version)
        alert.informativeText = tf("You have %@.", currentVersion)
        alert.addButton(withTitle: t("Download"))
        alert.addButton(withTitle: t("Later"))

        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(release.url)
        }
    }

    private func showUpToDate(currentVersion: String) {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = t("SwitchDeck is up to date")
        alert.informativeText = tf("Version %@ is the latest.", currentVersion)
        alert.addButton(withTitle: t("OK"))
        alert.runModal()
    }

    private func showUpdateFailure(_ error: Error) {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = t("Couldn't check for updates")
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: t("OK"))
        alert.runModal()
    }

    @objc private func showSettings() {
        openSettings()
    }

    @objc private func showPermissions() {
        openPermissions()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func perform(_ body: () throws -> Void) {
        do {
            try body()
        } catch {
            present(error)
        }
    }

    private func present(_ error: Error) {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = t("SwitchDeck")
        var text = error.localizedDescription
        if let hint = (error as? SwitchDeckError)?.recoveryHint {
            text += "\n\n" + hint
        }
        alert.informativeText = text
        alert.addButton(withTitle: t("OK"))

        let needsAutomation: Bool
        if case .automation = (error as? SwitchDeckError) ?? .message("") {
            needsAutomation = true
        } else {
            needsAutomation = false
        }

        if needsAutomation {
            alert.addButton(withTitle: t("Open Privacy Settings"))
            if alert.runModal() == .alertSecondButtonReturn {
                let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!
                NSWorkspace.shared.open(url)
            }
        } else {
            alert.runModal()
        }
    }
}
