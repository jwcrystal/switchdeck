# Adding a switch

A switch is one small class plus one row in the catalog. No AppKit, no
registration, no settings plumbing: the menu is built from data, so a new entry
appears in the menu, in Settings › Customize and in the config file on its own.

## 1. Write the behaviour

`Sources/SwitchKit/Switches/ShowHiddenFilesSwitch.swift` is the smallest
complete example. Three rules keep it testable:

- **No AppKit UI.** SwitchKit has no views; anything the menu draws comes from `SwitchItem`.
- **State reads are cheap.** `state` and `subtitle` run every time the menu opens, so read a preference or a cached value, never the network or a process.
- **Throw `SwitchDeckError`.** A `.message` shows up as an alert; `.automation` additionally gets an "Open Privacy Settings" button.

```swift
import Foundation

public final class ShowHiddenFilesSwitch {
    public init() {}

    public func isOn() -> Bool {
        FinderDefaults.bool("AppleShowAllFiles") ?? false
    }

    public func set(_ on: Bool) throws {
        try FinderDefaults.setBool(on, for: "AppleShowAllFiles")
    }

    public func toggle() throws {
        try set(!isOn())
    }
}
```

Reuse `Shell`, `FinderDefaults` and `Automation` instead of calling `Process` or
`osascript` yourself: they already handle quoting, timeouts and the error shapes
the alert expects.

## 2. Add the row

In `Sources/SwitchKit/SwitchCatalog.swift`, inside `standard()`:

```swift
SwitchItem(
    id: "showHiddenFiles",              // stable forever: it keys the config and the shortcut
    title: t("Show Hidden Files"),
    symbolName: "eye",                  // an SF Symbol name
    kind: .toggle,                       // .action for a one-shot, which draws no checkmark
    state: { hiddenFiles.isOn() },
    subtitle: { nil },                   // grey text on the right, e.g. "101 items"
    actions: { [] },                     // submenu entries; empty means no submenu
    perform: { try hiddenFiles.toggle() }
)
```

The position in the array is the default order. Existing users keep the order in
their `config.json`; a new id lands next to its catalog neighbour, and the menu
shows it until someone hides it.

## 3. If it needs a permission

Permissions are wired by hand, not declared. A switch that needs one must:

- add the query and the request to `Sources/SwitchDeckApp/PermissionCenter.swift`,
- add a row to `Sources/SwitchDeckApp/PermissionViews.swift` (the setup window),
- add the same row to the General pane in `Sources/SwitchDeckApp/SettingsView.swift`,
- add the usage string to `Info.plist` in `scripts/build-app.sh` if macOS requires one (microphone, screen recording).

The rule the app follows: the setup window is the only place that triggers a
system prompt, and using a switch with a missing permission explains what is off
instead of asking again.

## 4. Translate it

Every user-facing string goes through `t()` or, when it has placeholders, `tf()`:

```swift
subtitle: { count == 1 ? t("1 item") : tf("%d items", count) }
```

Add the pairs to `Resources/zh-Hant.lproj/Localizable.strings` and run:

```bash
./scripts/check-localizations.sh
```

It fails on a key with no translation, a translation that loses a `%@`/`%d`, and
user-facing AppKit text that never reached `t()`.

## 5. Test the logic, not the menu

`Tests/SwitchKitTests/` covers behaviour. Keep the switch testable by injecting
what it touches — `EmptyTrashSwitch` takes a `TrashAccess` for exactly this
reason — so a test never has to change the real system:

```swift
struct StubTrash: TrashAccess {
    let count: Int
    func itemCount() -> Int? { count }
    func empty() throws {}
}

func testSubtitleCountsTopLevelItems() {
    let trash = EmptyTrashSwitch(access: StubTrash(count: 3))
    XCTAssertEqual(trash.subtitle, "3 items")
}
```

## 6. Run it

```bash
./scripts/build-app.sh
build/SwitchDeck.app/Contents/MacOS/SwitchDeck --dump      # id, title, live state for every switch
build/SwitchDeck.app/Contents/MacOS/SwitchDeck --run <id>  # toggles once, prints the result
build/SwitchDeck.app/Contents/MacOS/SwitchDeck --menu      # the menu as it is actually built
```

`--dump` prints in the current interface language; add `-AppleLanguages '(en)'`
to read it in English.

## What you do not have to touch

Settings › Customize, the order and hidden state in `config.json`, global
shortcut registration, the menu rebuild on config change, and the checkmark
logic — all of it follows from the row you added.
