import XCTest
@testable import SwitchKit

final class ConfigTests: XCTestCase {
    func testOrderedIDsPlacesUnknownIDsNextToTheirCatalogNeighbour() {
        let config = SwitchDeckConfig(order: ["darkMode", "keepAwake"], disabled: [])
        let result = config.orderedIDs(from: ["showHiddenFiles", "keepAwake", "darkMode", "ejectDisk"])
        XCTAssertEqual(result, ["darkMode", "showHiddenFiles", "keepAwake", "ejectDisk"])
    }

    func testOrderedIDsIgnoresStaleAndDuplicateIDs() {
        let config = SwitchDeckConfig(order: ["removedSwitch", "ejectDisk", "ejectDisk"], disabled: [])
        let result = config.orderedIDs(from: ["keepAwake", "ejectDisk"])
        XCTAssertEqual(result, ["keepAwake", "ejectDisk"], "the unseen id lands before its next catalog neighbour")
    }

    func testDisableAndEnableRoundTrip() {
        var config = SwitchDeckConfig()
        config.setEnabled(false, for: "darkMode")
        XCTAssertFalse(config.isEnabled("darkMode"))
        config.setEnabled(true, for: "darkMode")
        XCTAssertTrue(config.isEnabled("darkMode"))
    }

    func testMoveSwapsNeighboursOnly() {
        var config = SwitchDeckConfig()
        let ids = ["a", "b", "c"]
        config.move("b", by: -1, allIDs: ids)
        XCTAssertEqual(config.order, ["b", "a", "c"])
        config.move("c", by: 1, allIDs: ids)
        XCTAssertEqual(config.order, ["b", "a", "c"], "moving past the end is a no-op")
    }

    func testDragReorderUsesSwiftUIIndices() {
        var config = SwitchDeckConfig()
        let ids = ["a", "b", "c", "d"]

        config.move(fromOffsets: IndexSet(integer: 0), toOffset: 3, allIDs: ids)
        XCTAssertEqual(config.order, ["b", "c", "a", "d"])

        config.move(fromOffsets: IndexSet(integer: 3), toOffset: 1, allIDs: ids)
        XCTAssertEqual(config.order, ["b", "d", "c", "a"])
    }

    func testCodableRoundTrip() throws {
        let config = SwitchDeckConfig(order: ["keepAwake"], disabled: ["darkMode"])
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(SwitchDeckConfig.self, from: data)
        XCTAssertEqual(config, decoded)
    }

    func testConfigStoreFallsBackWhenFileIsMissing() {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("switchdeck-\(UUID().uuidString)/config.json")
        let store = ConfigStore(url: url)
        XCTAssertEqual(store.config, SwitchDeckConfig())
    }

    func testConfigStorePersistsUpdates() {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("switchdeck-\(UUID().uuidString)/config.json")
        let store = ConfigStore(url: url)
        store.update { $0.setEnabled(false, for: "ejectDisk") }
        XCTAssertFalse(store.config.isEnabled("ejectDisk"))
        XCTAssertFalse(ConfigStore(url: url).config.isEnabled("ejectDisk"))
    }

    func testCatalogHasUniqueIDsAndKnownDefaults() {
        let catalog = SwitchCatalog.standard()
        XCTAssertEqual(Set(catalog.ids).count, catalog.ids.count)
        XCTAssertNotNil(catalog.item(id: "keepAwake"))
        XCTAssertNotNil(catalog.item(id: "darkMode"))
        XCTAssertNotNil(catalog.item(id: "screenClean"))
        XCTAssertNotNil(catalog.item(id: "lockKeyboard"))
        XCTAssertNotNil(catalog.item(id: "nightShift"))
        XCTAssertNotNil(catalog.item(id: "stageManager"))
        XCTAssertNotNil(catalog.item(id: "emptyTrash"))
        XCTAssertNotNil(catalog.item(id: "recording"))
        XCTAssertNotNil(catalog.item(id: "hideDesktopIcons"))

        let ids = catalog.ids
        if let hiddenFiles = ids.firstIndex(of: "showHiddenFiles"),
           let desktopIcons = ids.firstIndex(of: "hideDesktopIcons") {
            XCTAssertEqual(desktopIcons, hiddenFiles + 1, "the two Finder switches sit together")
        } else {
            XCTFail("both Finder switches must exist")
        }
    }

    func testFinderBoolParsing() {
        for value in ["1", "true", "TRUE", "yes", " yes "] {
            XCTAssertEqual(FinderDefaults.parseBool(value), true, "\(value) should read as true")
        }
        for value in ["0", "false", "No", "no\n"] {
            XCTAssertEqual(FinderDefaults.parseBool(value), false, "\(value) should read as false")
        }
        XCTAssertNil(FinderDefaults.parseBool("garbage"))
    }

    // MARK: - Empty Trash

    func testEmptyTrashCountsVisibleTopLevelItems() throws {
        let folder = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("switchdeck-trash-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        FileManager.default.createFile(atPath: folder.appendingPathComponent("a.txt").path, contents: nil)
        FileManager.default.createFile(atPath: folder.appendingPathComponent("b.txt").path, contents: nil)
        FileManager.default.createFile(atPath: folder.appendingPathComponent(".hidden").path, contents: nil)
        try FileManager.default.createDirectory(
            at: folder.appendingPathComponent("nested"),
            withIntermediateDirectories: true
        )

        let trash = EmptyTrashSwitch(access: FileTrash(url: folder))
        XCTAssertEqual(trash.subtitle, "3 items")

        try trash.empty()
        XCTAssertEqual(trash.subtitle, "Empty")
    }

    func testEmptyTrashOnMissingFolderIsHarmless() throws {
        let folder = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("switchdeck-missing-\(UUID().uuidString)")
        let trash = EmptyTrashSwitch(access: FileTrash(url: folder))
        XCTAssertEqual(trash.subtitle, "Empty")
        XCTAssertNoThrow(try trash.empty())
    }

    func testEmptyTrashReportsNoAccessInsteadOfEmpty() throws {
        // A directory that exists but cannot be listed stands in for ~/.Trash
        // without Full Disk Access.
        let folder = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("switchdeck-denied-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: folder.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path)
            try? FileManager.default.removeItem(at: folder)
        }

        let trash = EmptyTrashSwitch(access: FileTrash(url: folder))
        XCTAssertEqual(trash.subtitle, "No access")
    }

    // MARK: - Hotkeys

    func testHotkeyDisplayStringUsesCanonicalOrder() {
        let binding = HotkeyBinding(
            keyCode: 40,
            modifiers: HotkeyBinding.commandModifier
                | HotkeyBinding.optionModifier
                | HotkeyBinding.shiftModifier
                | HotkeyBinding.controlModifier,
            label: "K"
        )
        XCTAssertEqual(binding.displayString, "⌃⌥⇧⌘K")
    }

    func testHotkeyWithoutCommandOptionOrControlIsNotUsable() {
        let shiftOnly = HotkeyBinding(keyCode: 40, modifiers: HotkeyBinding.shiftModifier, label: "K")
        XCTAssertFalse(shiftOnly.isUsable)
        let withCommand = HotkeyBinding(keyCode: 40, modifiers: HotkeyBinding.commandModifier, label: "K")
        XCTAssertTrue(withCommand.isUsable)
    }

    func testHotkeyRoundTripAndClearing() {
        var config = SwitchDeckConfig()
        let binding = HotkeyBinding(keyCode: 40, modifiers: HotkeyBinding.commandModifier, label: "K")
        config.setHotkey(binding, for: "keepAwake")
        XCTAssertEqual(config.hotkey(for: "keepAwake"), binding)

        config.setHotkey(nil, for: "keepAwake")
        XCTAssertNil(config.hotkey(for: "keepAwake"), "a cleared shortcut is removed, not stored empty")
    }

    func testConfigWithoutHotkeysKeyStillDecodes() throws {
        let legacy = Data(#"{"order":["keepAwake"],"disabled":["darkMode"]}"#.utf8)
        let config = try JSONDecoder().decode(SwitchDeckConfig.self, from: legacy)
        XCTAssertEqual(config.order, ["keepAwake"])
        XCTAssertTrue(config.hotkeys.isEmpty)
        XCTAssertFalse(config.didCompleteSetup, "a config from before setup existed has not completed setup")
    }

    func testSetupFlagSurvivesRoundTrip() throws {
        var config = SwitchDeckConfig()
        XCTAssertFalse(config.didCompleteSetup)
        config.didCompleteSetup = true
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(SwitchDeckConfig.self, from: data)
        XCTAssertTrue(decoded.didCompleteSetup)
    }
}
