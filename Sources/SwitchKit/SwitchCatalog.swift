import AppKit
import Foundation

/// The built-in switches, in the order the original app shows them.
///
/// New switches get appended here; saved configs that do not mention them still
/// show them, after the ids the user has already ordered.
public struct SwitchCatalog {
    public let items: [SwitchItem]

    public init(items: [SwitchItem]) {
        self.items = items
    }

    public var ids: [String] { items.map(\.id) }

    public func item(id: String) -> SwitchItem? {
        items.first { $0.id == id }
    }

    public static func standard() -> SwitchCatalog {
        let keepAwake = KeepAwakeSwitch()
        let hiddenFiles = ShowHiddenFilesSwitch()
        let desktopIcons = HideDesktopIconsSwitch()
        let dockAutohide = DockAutohideSwitch()
        let darkMode = DarkModeSwitch()
        let pasteboard = EmptyPasteboardSwitch()
        let quitAll = QuitAllAppsSwitch()
        let eject = EjectDiskSwitch()
        let nightShift = NightShiftSwitch()
        let lockScreen = LockScreenSwitch()
        let stageManager = StageManagerSwitch()
        let trash = EmptyTrashSwitch()
        let recording = RecordingSwitch()
        let keyboard = KeyboardLockSwitch()
        let screenClean = ScreenCleanSwitch(keyboard: keyboard)

        let items: [SwitchItem] = [
            SwitchItem(
                id: "showHiddenFiles",
                title: t("Show Hidden Files"),
                symbolName: "eye",
                kind: .toggle,
                state: { hiddenFiles.isOn() },
                perform: { try hiddenFiles.toggle() }
            ),
            SwitchItem(
                id: "hideDesktopIcons",
                title: t("Hide Desktop Icons"),
                symbolName: "rectangle.on.rectangle.slash",
                kind: .toggle,
                state: { desktopIcons.areIconsHidden },
                subtitle: { desktopIcons.areIconsHidden ? t("Icons hidden") : nil },
                perform: { try desktopIcons.toggle() }
            ),
            SwitchItem(
                id: "dockAutohide",
                title: t("Dock Autohide"),
                symbolName: "dock.rectangle",
                kind: .toggle,
                state: { dockAutohide.isOn },
                perform: { try dockAutohide.toggle() }
            ),
            SwitchItem(
                id: "screenClean",
                title: t("Screen Clean"),
                symbolName: "sparkles",
                kind: .action,
                subtitle: { screenClean.isActive ? t("Active") : nil },
                perform: { screenClean.start() }
            ),
            SwitchItem(
                id: "keepAwake",
                title: t("Keep Awake"),
                symbolName: "cup.and.saucer",
                kind: .toggle,
                state: { keepAwake.isOn },
                subtitle: { keepAwake.subtitle },
                actions: {
                    KeepAwakeSwitch.durations.map { duration in
                        .init(title: t(duration.title)) { keepAwake.start(minutes: duration.minutes) }
                    } + [
                        .init(
                            title: t("Keep Display On"),
                            isChecked: { keepAwake.keepsDisplayOn },
                            startsSection: true
                        ) { keepAwake.keepsDisplayOn.toggle() },
                    ]
                },
                perform: {
                    if keepAwake.isOn {
                        keepAwake.stop()
                    } else {
                        keepAwake.start(minutes: nil)
                    }
                }
            ),
            SwitchItem(
                id: "darkMode",
                title: t("Dark Mode"),
                symbolName: "moon",
                kind: .toggle,
                state: { darkMode.isDark },
                perform: { try darkMode.toggle() }
            ),
            SwitchItem(
                id: "lockKeyboard",
                title: t("Lock Keyboard"),
                symbolName: "keyboard.badge.ellipsis",
                kind: .toggle,
                state: { keyboard.isLocked },
                subtitle: { keyboard.subtitle },
                perform: {
                    if keyboard.isLocked {
                        keyboard.unlock()
                    } else {
                        try keyboard.lock()
                    }
                }
            ),
            SwitchItem(
                id: "lockScreen",
                title: t("Lock Screen"),
                symbolName: "lock.display",
                kind: .action,
                perform: { try lockScreen.lock() }
            ),
            SwitchItem(
                id: "nightShift",
                title: t("Night Shift"),
                symbolName: "moon.stars",
                kind: .toggle,
                state: { nightShift.isOn },
                subtitle: { nightShift.isAvailable ? nil : t("Not available") },
                perform: { try nightShift.toggle() }
            ),
            SwitchItem(
                id: "stageManager",
                title: t("Stage Manager"),
                symbolName: "rectangle.3.group",
                kind: .toggle,
                state: { stageManager.isOn },
                perform: { try stageManager.toggle() }
            ),
            SwitchItem(
                id: "stageManagerAutohide",
                title: t("Stage Manager Autohide"),
                symbolName: "rectangle.3.group.bubble",
                kind: .toggle,
                state: { stageManager.isAutohideOn },
                perform: { try stageManager.toggleAutohide() }
            ),
            SwitchItem(
                id: "emptyTrash",
                title: t("Empty Trash"),
                symbolName: "trash",
                kind: .action,
                subtitle: { trash.subtitle },
                perform: { try trash.empty() }
            ),
            SwitchItem(
                id: "emptyPasteboard",
                title: t("Empty Pasteboard"),
                symbolName: "doc.on.clipboard",
                kind: .action,
                subtitle: { pasteboard.isEmpty ? t("Empty") : nil },
                perform: { pasteboard.empty() }
            ),
            SwitchItem(
                id: "recording",
                title: t("Recording"),
                symbolName: "record.circle",
                kind: .toggle,
                state: { recording.isRecording },
                subtitle: { recording.subtitle },
                actions: {
                    [
                        .init(title: t("Open Recordings Folder")) {
                            try? FileManager.default.createDirectory(
                                at: recording.folder,
                                withIntermediateDirectories: true
                            )
                            NSWorkspace.shared.open(recording.folder)
                        },
                    ]
                },
                perform: { try recording.toggle() }
            ),
            SwitchItem(
                id: "quitAllApps",
                title: t("Quit All Apps"),
                symbolName: "xmark.rectangle",
                kind: .action,
                subtitle: { quitAll.subtitle },
                perform: { quitAll.quitAll() }
            ),
            SwitchItem(
                id: "ejectDisk",
                title: t("Eject Disk"),
                symbolName: "eject",
                kind: .action,
                subtitle: { eject.subtitle },
                perform: { try eject.ejectAll() }
            ),
        ]

        return SwitchCatalog(items: items)
    }
}
