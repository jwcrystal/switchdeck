# SwitchDeck

A local reimplementation of the menu-bar switches in [AnySwitch](https://apps.apple.com/us/app/anyswitch-powerful-switches/id6444313776), built for this Mac without the App Store sandbox.

Where AnySwitch ships ~20 AppleScript files and a sandbox, SwitchDeck talks to the system directly: `ProcessInfo` power assertions, `NSWorkspace`, `NSPasteboard`, `defaults`, and (only when there is no public API) System Events.

## First launch

SwitchDeck shows a **Set up SwitchDeck** window when a permission is missing. That window is the only place the app triggers a macOS permission dialog:

- **Accessibility** — Lock Keyboard and Screen Clean.
- **Automation — System Events** — Dark Mode.
- **Automation — Finder** — Empty Trash and its item count.
- **Microphone** — Recording.

Grant there once and the menu never prompts again; using a switch with a missing permission just explains what is off. Reopen the window from the menu's **Permissions…** item or Settings › General.

## Status

Milestones M1–M4 are done: sixteen switches, the menu-bar UI, global shortcuts with an inline recorder, a setup window for permissions, an app icon, and a stable local signature.

| Switch | How it works | Note |
|---|---|---|
| Show Hidden Files | `defaults write com.apple.finder AppleShowAllFiles` + Finder restart | Closes Finder windows |
| Screen Clean | Black overlay on every screen at screen-saver level + keyboard lock | Click once to reveal Stop Clean |
| Keep Awake | `ProcessInfo.beginActivity`, optional duration and expiry in the menu | Shown in `pmset -g assertions` |
| Dark Mode | System Events appearance preferences | Needs Automation |
| Lock Keyboard | `CGEventTap` swallowing key events, auto-unlocks after 5 min | Needs Accessibility |
| Lock Screen | private `SACLockScreenImmediate` from `login.framework` | Falls back to ⌃⌘Q via System Events |
| Night Shift | private `CBBlueLightClient` from `CoreBrightness` (`dlopen`) | No public API; verified on macOS 27 |
| Stage Manager | `com.apple.WindowManager GloballyEnabled` + WindowManager restart | Key name needs a visual check on this Mac |
| Stage Manager Autohide | `com.apple.WindowManager AutoHide` + restart | Same |
| Empty Trash | Finder AppleScript: `count items in trash`, `empty trash` | Needs Automation; direct `~/.Trash` reads are blocked by TCC |
| Empty Pasteboard | `NSPasteboard.clearContents()` | |
| Recording | `AVAudioRecorder` to `~/Music/SwitchDeck`, elapsed time in the menu | Needs Microphone |
| Screenshot | ScreenCaptureKit region/window/full-screen capture; borderless editor with rectangle, ellipse, line, arrow, pen, highlighter, text, numbering, mosaic and blur; copy, save, pin | Needs Screen Recording |
| Hide Windows | `NSRunningApplication.hide()`, skips Finder and SwitchDeck | Reversible: click the app in the Dock |
| Quit All Apps | `NSRunningApplication.terminate()`, skips Finder and SwitchDeck | Unsaved work still prompts |
| Eject Disk | `NSWorkspace.unmountAndEjectDevice`, counts removable volumes | |

Settings › Customize reorders and hides switches; the choice is stored in
`~/Library/Application Support/SwitchDeck/config.json`. Rows are dragged into place; a context menu offers Move Up / Move Down / Show in Menu for keyboard use.

## Screenshot

- `⌥E` starts a capture (installed once as a default; change it in Settings › Shortcuts).
- Dragging a region enters editing **in place**: the selection stays on screen, everything outside dims, and the toolbar appears under the region — no second window. Clicking a window edits at that window's frame; `F` selects the whole screen; `R` restores the last region.
- The default tool is Select, so the toolbar is optional: click an active tool again to cancel it and go back to selecting. With a tool active, dragging inside draws:
  -  rectangle, ellipse, line, arrow (straight / curved / elbow), freehand, highlighter, text (S/M/L, optional bubble), numbered markers, mosaic and blur.
- The region keeps its eight handles while editing, so it can still be resized; while dragging, the live screen shows through and the frozen image is refreshed on release.
- While selecting, the colour under the pointer is shown with its value; `⌥` cycles HEX / RGB / HSL, and `C` copies the value, leaves capture mode and shows a short "Copied …" toast. The readout is hidden once editing starts.
- The region is frozen the moment editing starts, so mosaic and blur preview exactly what gets saved.
- The toolbar keeps every tool on one row; only variant options (arrow style, text size and bubble) open a small submenu.
- The signature button adds a watermark (the macOS full user name); its popover edits the text, colour, position (four corners, centre or a tiled pattern), size (S/M/L), angle (0/30/45°) and opacity. It is clipped to the capture, so a rotated or tiled watermark never spills outside the selection. The eye-slash button hides it from the image but keeps the text in the PNG metadata.
- `Enter` copies, `Space` saves a PNG straight into ~/Downloads as `SwitchDeck Screenshot <date>.png` (folder and prefix are the UserDefaults keys that Settings will expose), `P` pins on screen, `⌘Z` undoes, `Esc` closes.
- Pinned images: the corner × or `Esc` closes, scroll resizes, `⌘`-scroll changes opacity, right-click has Copy / 50% Opacity / Close.

## Global shortcuts (M2)

Settings › Shortcuts records one shortcut per switch:

- Click **Record Shortcut**, press a combination. Esc cancels, Delete clears.
- A shortcut needs ⌘, ⌥ or ⌃; otherwise it could swallow ordinary typing.
- Recording uses a local event monitor, so it never asks for Accessibility.
- Registration uses Carbon `RegisterEventHotKey`, which also reports a shortcut another app already owns.
- Duplicates inside SwitchDeck and registration failures show up as red lines at the bottom of the pane.
- The menu shows the shortcut in the grey column, next to the live state.
- Hidden switches keep their shortcut in the config but do not register it.

## Build and run

```bash
cd ~/dev/switchdeck
swift test                      # 8 tests, no UI needed
./scripts/build-app.sh          # builds build/SwitchDeck.app
open build/SwitchDeck.app
```

The app is an `LSUIElement` accessory: it lives only in the menu bar. Quit it from its own menu.

Handy command-line checks that use the same switch code:

```bash
build/SwitchDeck.app/Contents/MacOS/SwitchDeck --dump          # every switch + live state
build/SwitchDeck.app/Contents/MacOS/SwitchDeck --run keepAwake # run one switch, print result
build/SwitchDeck.app/Contents/MacOS/SwitchDeck --hotkeys       # register a probe shortcut, report conflicts
build/SwitchDeck.app/Contents/MacOS/SwitchDeck --permissions   # what the app sees for each permission
build/SwitchDeck.app/Contents/MacOS/SwitchDeck --menu          # the menu as it is built
build/SwitchDeck.app/Contents/MacOS/SwitchDeck --capture-test  # capture the main display, report the result
```

## Layout

```
Sources/SwitchKit/             # no AppKit UI, unit-testable
  SwitchItem.swift             # one menu row: title, icon, state, action, submenu
  SwitchCatalog.swift          # built-in switches in original-app order
  Config.swift                 # order, visibility and shortcuts, JSON persistence
  HotkeyBinding.swift          # key + Carbon modifiers + key-cap label
  Shell.swift / Automation.swift
  Switches/                    # one file per switch
Sources/SwitchDeckApp/         # AppKit shell
  MenuController.swift         # NSStatusItem + NSMenu, rebuilt on config change
  HotkeyCenter.swift           # Carbon registration, conflict reporting
  HotkeyRecorder.swift         # NSEvent -> binding, local capture monitor
  SettingsView.swift           # SwiftUI settings
Tests/SwitchKitTests/
scripts/build-app.sh           # SPM binary -> .app with Info.plist + ad-hoc signature
```

## Permissions

macOS TCC cannot be pre-granted. The first time a switch needs something, macOS asks:

- **Automation** — Dark Mode (System Events) and Empty Trash (Finder). Also listed in Settings › General.
- **Accessibility** — Lock Keyboard and Screen Clean. The first attempt shows the macOS prompt; the switch then explains how to grant it.
- **Microphone** — Recording. macOS asks the first time you start one.
- **Screen Recording** — Screenshot. macOS applies the grant after a relaunch.

### Why rebuilds used to lose permissions

An ad-hoc signature identifies the app by its CDHash, which changes on every build, so macOS treated each rebuild as a brand new app and asked again. `scripts/setup-signing.sh` (run once per machine) creates a locally trusted, self-signed `SwitchDeck Local Signing` certificate, and `scripts/build-app.sh` signs with it automatically. The designated requirement then stays

```
identifier "studio.anyfun.switchdeck" and certificate leaf = H"…"
```

across rebuilds, so Accessibility and Automation grants survive. Verify with `codesign -d -r- build/SwitchDeck.app`.

The build is signed with a local self-signed identity (see Permissions below). Launch at login needs the app in `/Applications`; until then the toggle in General reports the system error.

## Roadmap

- **M1–M3 — done** — menu, switches, settings, global shortcuts, the hard system integrations.
- **M4 — done** — setup window and permission status, app icon, stable local signing, About pane.
- **Screenshot follow-ups** — blur/mosaic, cropping, OCR, scrolling capture, selection handles to adjust the region after capture.
- **Later** — live menu updates while recording, localisation.

## Why not copy AnySwitch's scripts

AnySwitch is App Store sandboxed, so it does everything through precompiled AppleScripts. Those scripts are its code, and they solve sandbox problems this app does not have. SwitchDeck implements the behaviour natively; only the menu layout follows the original.
