# SwitchDeck vs AnySwitch vs OnlySwitch

A factual comparison of SwitchDeck against the two apps it borrows its shape from.
Written 2026-11-12; versions change, so treat the numbers as a snapshot.

- **SwitchDeck** — this repository. A locally built, unsigned-for-distribution menu-bar app with 14 switches.
- **AnySwitch** — App Store app by anyfun.studio, free with a US$4.99 unlock. Last release 3.8.8 (September 2023). Sandboxed, drives the system through ~20 precompiled AppleScripts.
- **OnlySwitch** — MIT-licensed open-source app (jacklandrin/OnlySwitch, ~6k stars, commits through November 2026). Much broader feature set: switches, tabs, widgets, schedules, remote control.

## What SwitchDeck has

**Switches (16)**

| Switch | Implementation |
|---|---|
| Show Hidden Files | `defaults` on `com.apple.finder` + Finder restart |
| Screen Clean | Black overlay per screen at screen-saver level + keyboard lock |
| Keep Awake | `ProcessInfo` power assertion, 5 min – 4 h durations, expiry in the menu |
| Dark Mode | System Events appearance preferences |
| Lock Keyboard | `CGEventTap` swallowing key events, auto-unlocks after 5 minutes |
| Lock Screen | private `SACLockScreenImmediate` (`login.framework`) |
| Night Shift | private `CBBlueLightClient` (`CoreBrightness`) |
| Stage Manager / Autohide | `com.apple.WindowManager` + window-manager restart |
| Empty Trash | Finder AppleScript, top-level item count |
| Empty Pasteboard | `NSPasteboard` |
| Recording | `AVAudioRecorder` to `~/Music/SwitchDeck` |
| Screenshot | ScreenCaptureKit; borderless editor (rect, ellipse, line, arrow, pen, highlighter, text, number, mosaic, blur); adjustable selection, copy/save/pin |
| Hide Windows | `NSRunningApplication.hide()`, fully reversible |
| Quit All Apps | `NSRunningApplication.terminate()` |
| Eject Disk | `NSWorkspace.unmountAndEjectDevice`, all removable volumes |

**Beyond the switches**

- Native `NSMenu` list with a right-aligned grey status column, submenus, checkmarks.
- Global shortcuts: Carbon `RegisterEventHotKey`, inline recorder, in-app and system conflict reporting, shortcut shown in the menu.
- Sidebar settings: General, Customize, Shortcuts, About.
- Customize: drag to reorder, toggle to hide, context-menu fallback.
- One-time Setup window for Accessibility, System Events, Finder and Microphone, with live status and per-permission "Grant" / "Settings" actions.
- Single-instance lock, ad-hoc-free local signing identity that keeps TCC grants across rebuilds.
- Diagnostics: `--dump`, `--run <id>`, `--menu`, `--hotkeys`, `--permissions`, `--probe-automation`.
- 17 unit tests over config, ordering, hotkeys and Trash counting.

## Comparison

| Aspect | SwitchDeck | AnySwitch | OnlySwitch |
|---|---|---|---|
| Distribution | Built locally from source | Mac App Store | GitHub (MIT), plus releases |
| Price | Free | Free + US$4.99 unlock | Free |
| Menu shape | Native `NSMenu` list + submenus | `NSMenu` list (same shape) | Popover panel with a grid and tabs |
| Switch count | 16 | ~20 | ~35 plus optional tool tabs |
| Global shortcuts | Carbon + recorder + conflict report | Yes | Yes, plus macOS Shortcuts import |
| Ordering / hiding | Drag to reorder | Yes, in its Customize page | Yes, with categories and search |
| Permission flow | One Setup window, live status | Guided prompts | Guided prompts |
| Sandbox | Not sandboxed | App Store sandbox | Not sandboxed |
| Night Shift | Private `CBBlueLightClient` | Private `CBBlueLightClient` | Private APIs |
| Trash | Finder AppleScript + count | AppleScript + count | Empties only, no count |
| Extensibility | Edit Swift sources | Closed | Modular; schedules, Shortcuts, remote |
| Localisation | English only | 12+ languages | 20+ languages |
| Maintained | By whoever builds it | No release since Sep 2023 | Active |
| Tests / CLI diagnostics | 17 tests, 6 debug modes | None known | Tests for some modules |
| Licence | No LICENSE file yet | Proprietary | MIT |

## Where SwitchDeck wins

1. **Permission and signing hygiene.** One Setup window, queryable state, and a stable self-signed identity so Accessibility/Automation grants survive rebuilds. AnySwitch fights its sandbox with AppleScript; OnlySwitch asks for more permissions across a much larger surface.
2. **Menu feel.** A flat list is faster to scan and click than a grid with tabs, which is exactly why AnySwitch was preferred over OnlySwitch here.
3. **Hackability.** A new switch is one `SwitchItem` plus a test; both diagnostics and tests already exist. AnySwitch is closed and OnlySwitch requires learning its module system.

## Where SwitchDeck loses

- No localisation, no auto-update, no Developer ID signature, no App Store distribution.
- Far fewer switches: no Do Not Disturb / Focus, Screenshot, Screen Saver, Resolution, Low Power Mode, Bluetooth, AirPods, radio, music controls.
- None of OnlySwitch's scheduling, widgets, iPhone remote, or Shortcuts import.

## Candidate additions

Chosen to keep the "one row, one action" shape and avoid new permissions:

- **Do Not Disturb** — no public API; either run a user Shortcut or script the menu bar. The fragile one.
- **Screenshot** — `screencapture -i`, needs Screen Recording.

## Adjacent tools

Four other ways people get the same job done. None of them is a switch list in the same sense; they are what a user weighs against AnySwitch or this project.

| Tool | Shape | Why it matters |
|---|---|---|
| One Switch (Fireball Studio) | Paid, five switches, 7-day trial | The polish bar: fewer switches, refined for years |
| Control Center + Shortcuts | Built in | The default answer; no install, no shared list |
| Raycast | Keyboard commands and extensions | Wins for people who never open a menu |
| Amphetamine | One job, done deeply | Keep Awake with schedules and triggers |

Deliberately left out: menu-bar managers (Ice, Bartender), cleaners (CleanMyMac, OnyX) and screenshot tools (CleanShot). They overlap on at most one switch and would blur the comparison; revisit them if SwitchDeck ever grows "Hide Menu Bar Icons" or "Screenshot".

## Sources

- App Store listing for AnySwitch (id6444313776) and the app bundle at `/Applications/AnySwitch.app`.
- OnlySwitch README and `Modules/Sources/AppFeature/EverySwitch/EjectDiscsSwitch.swift`, `EmptyTrashSwitch.swift` on GitHub.
- One Switch product page at fireball.studio/oneswitch.
- This repository's sources, tests and `scripts/`.
