<img src="assets/clickit-icon.png" alt="Clickit" width="128" align="right">

# Clickit

Clipboard history for the macOS menu bar. Keep copying and pasting the way you always have — Clickit records what you copy in the background, and one keystroke brings back anything from your recent history: text, links, images, screenshots. Nothing leaves your Mac.

<p align="center">
  <img src="assets/screenshot-popover.png" alt="Clickit menu-bar popover showing recent clipboard history" width="320">
</p>

## Status

Early, and unsigned. The loop works — copy, search, restore, paste — history survives quitting, and the global shortcut and launch-at-login are in. What it is not yet: signed, notarized, or on Homebrew, so the first launch takes one extra step (see [Installation](#installation)).

Don't rely on Clickit as your only copy of anything.

| Working | Not yet |
| --- | --- |
| Menu-bar popover: search, pin, delete | Signed, notarized release |
| Text, link, image and screenshot capture | Homebrew |
| Command-Shift-V to open; Option-Shift-V for Live Queue | Reassignable shortcuts |
| Launch at login | Reliable per-app exclusion |
| Duplicate detection, retention, cleanup | |
| History across quits, cleared on restart | |

## What it does

- Lives in the menu bar — no Dock icon, no window to manage.
- **Command-Shift-V** opens it at your text cursor. It has one job and no hold behavior.
- **Option-Shift-S** starts the native area selector and copies the screenshot to the clipboard. Clickit records it while monitoring is active.
- Press **Option-Shift-V** to turn Live Queue on or off without opening Clickit.
- With Live Queue on, each Command-C or Option-Shift-S capture is queued automatically, including repeated copies. A compact HUD at the top-right of the main display shows the next five entries and stacks the rest. Ordinary **Command-V** pastes the next item; the queue turns itself off after the last one.
- Records text, links, images and screenshots, sorted by type automatically.
- Search as you type. Pin what you want to keep; delete the rest.
- Copy the same thing twice and the existing entry moves up instead of piling on a duplicate.
- History lives in a local SQLite database, survives quitting or a crash, and clears on restart. Pinned items always stay.

## Installation

Download the latest `.dmg` from [**Releases**](https://github.com/rohankc69/clickit/releases/latest), open it, and drag Clickit to Applications.

Because the build isn't signed or notarized yet, macOS blocks it on first launch — usually claiming it "is damaged and can't be opened". It isn't damaged; it's unsigned. Clear the quarantine flag once, after copying to Applications:

```bash
xattr -d com.apple.quarantine /Applications/Clickit.app
```

Only do this for a build you trust. Removing quarantine defeats a real safety check, so it isn't something to hand to users casually — signing and notarization, which would make the step unnecessary, are on the roadmap.

Prefer to build it yourself? See [Development setup](#development-setup) below, or package your own disk image with `./scripts/build-dmg.sh` (output in `dist/`).

## Requirements

- macOS 14.0 (Sonoma) or later
- Xcode 16 or later, to build from source
- No third-party dependencies

## Development setup

```bash
git clone https://github.com/<your-account>/clickit.git
cd clickit
open Clickit.xcodeproj
```

Press Command-R, or from the command line:

```bash
# Build
xcodebuild build -project Clickit.xcodeproj -scheme Clickit -destination 'platform=macOS'

# Test
xcodebuild test -project Clickit.xcodeproj -scheme Clickit -destination 'platform=macOS'
```

The app launches with no Dock icon (`LSUIElement`) — look for the clipboard icon in the menu bar. Clickit is **not sandboxed**, because it writes to `~/Library/Application Support/Clickit/`.

Logs carry metadata only, never clipboard contents:

```bash
log stream --info --predicate 'subsystem == "com.clickit.Clickit"'
```

## How clipboard monitoring works

macOS gives no notification when the pasteboard changes, so polling is the only option. `ClipboardMonitor` samples `NSPasteboard.general.changeCount` — a single integer — every 0.5 s, and only reads the actual contents when that number moves. The poll is cheap enough not to register in Activity Monitor.

On a change, Clickit:

1. Skips it if the writing app marked it concealed, transient, or auto-generated.
2. Reads and classifies it as text, URL, or image.
3. Skips it if it's empty, unsupported, or from an excluded app.
4. Skips it if the change was Clickit's own write — restoring an item must not read back as a fresh copy.
5. Hashes it with SHA-256 to catch duplicates.
6. Moves an existing duplicate to the top, or records a new entry.
7. Runs cleanup.

## Pasting

Press Command-Shift-V in any app and Clickit opens at your text cursor. Pick an item and it pastes there. This shortcut never toggles Live Queue.

For repeated entry, press Option-Shift-V and keep copying normally, or stage existing history rows with their queue button or Option-Return. The read-only queue HUD stays on the main display without taking focus, shows up to five numbered entries with image previews, and stacks any overflow. While Live Queue is active, each ordinary Command-V stages the next item and then passes your original paste keystroke through unchanged. The final item turns Live Queue off automatically; Option-Shift-V can stop it manually without clearing the remaining queue. The queue holds item references in memory only and clears when Clickit quits.

Picker positioning and automatic picker paste need macOS Accessibility permission. Live Queue uses that authorization plus Input Monitoring because it must stage the next queued payload before your physical Command-V reaches the current app. The monitor exists only while Live Queue is active and never suppresses or replaces Command-V.

Finding the cursor depends on the app reporting it. Native text fields do; some web views and cross-platform apps don't, and Clickit then falls back to the focused window, then the pointer.

## Local storage

Everything lives on your Mac:

```
~/Library/Application Support/Clickit/
├── clickit.sqlite   # history: text, links, and metadata
└── Images/          # PNG files for copied images and screenshots
```

Text and metadata go in a local SQLite database. Image bytes are kept as separate files, with only the filename on the entry, and the list renders from small cached thumbnails — so browsing history never pages full-size screenshots into memory. The database is read in once at launch and kept as a write-through cache: search stays instant while every change commits to disk immediately. Nothing is written anywhere else.

### How long history is kept

Two mechanisms, in the order they usually fire.

**Restarting the Mac clears unpinned history.** This is the main lifecycle, on by default. Clipboard history is a working set for the session you're in; holding weeks of it is both more than anyone reuses and more exposure than it's worth. Quitting and relaunching Clickit clears nothing — only a real restart does, detected from the system boot time.

**Retention limits are the backstop**, for machines that go a long time between restarts:

| Setting | Default |
| --- | --- |
| Maximum items | 1,000 |
| Maximum storage | 500 MB |
| Text and link retention | 30 days |
| Image and screenshot retention | 7 days |
| Pinned items | Never expire |

All configurable in Settings, including turning the restart behaviour off. Cleanup runs at launch, after every capture, and whenever retention settings change: it removes expired unpinned items first, then the oldest unpinned items over the count limit, then the oldest unpinned *images* over the size limit. Removing an image record always deletes its file.

## Privacy

Clipboard history is sensitive by nature — it collects passwords, tokens, private messages and screenshots without you thinking about it. Clickit's stance is that this never leaves your machine.

- No network requests, at all.
- No accounts, no cloud, no cross-device sync.
- No telemetry, analytics, or crash reporting.
- No AI or content analysis. Clickit decides only whether something is text, a link, or an image — it doesn't read, classify, or OCR it.
- Logs hold metadata only — type and byte size, never contents.
- Pause monitoring and Clear history are always one click away.
- Password managers can opt out: Clickit honours the [nspasteboard.org](http://nspasteboard.org) conventions, so anything marked concealed, transient, or auto-generated is never read or recorded. This relies on the source app setting the marker.

**Per-app exclusion is only partly implemented.** You can add bundle identifiers in Settings and copies from those apps are dropped, but attribution uses the frontmost app at the moment of the copy — a best-effort guess, not proof of which process wrote to the pasteboard. Don't treat it as a security boundary yet.

See [PRIVACY.md](PRIVACY.md) for the full statement.

## Getting a screenshot into history

Press **Option-Shift-S** anywhere while Clickit is running. The native macOS crosshair appears; drag over an area and release to copy the screenshot to the clipboard. When monitoring is active, Clickit records it like any other copied image. Press Escape to cancel.

This is a Clickit global shortcut. macOS may ask for Screen Recording permission the first time it is used. The system's own default screenshot shortcuts also work:

| Default shortcut | Result |
| --- | --- |
| `Command-Shift-3` / `Command-Shift-4` | Saves a file. Clickit doesn't see it. |
| `Command-Control-Shift-3` / `Command-Control-Shift-4` | Copies to the clipboard. Clickit records it. |

Your macOS shortcuts may differ if they were changed in **System Settings → Keyboard → Keyboard Shortcuts → Screenshots**. Any binding that copies the image instead of saving it works with Clickit. If the defaults above do not work, check the current binding for "Copy picture of selected area to the clipboard" in System Settings.

## Keyboard shortcuts

These work globally while Clickit is running:

| Key | Action |
| --- | --- |
| Option-Shift-S | Select an area and copy the screenshot to the clipboard |
| Option-Shift-V | Turn Live Queue on or off |
| Command-Shift-V | Open Clickit at the text cursor |
| Command-V | Paste the next item while Live Queue is active; paste normally otherwise |

Inside the popover:

| Key | Action |
| --- | --- |
| Up / Down | Move through history |
| Return | Restore the selected item and close |
| Option-Return | Add or remove the selected item from the paste queue |
| Command-1 to 9 | Restore by position |
| Escape | Clear the search, or close if it's empty |
| Command-F | Focus the search field |
| Command-P | Pin or unpin the selected item |
| Delete | Delete the selected item (when the search field is empty) |
| Command-Delete | Delete the selected item (always) |
| Command-K | Clear history, keeping pinned items |
| Command-M | Pause or resume monitoring |
| Command-Comma | Open Settings |
| Command-Q | Quit Clickit |

Then press **Command-V** wherever you want to paste. The global shortcuts aren't reassignable yet; Settings shows them read-only.

## Roadmap

The menu-bar app, clipboard monitoring, restore, the popover, local persistence, the global shortcut, and launch at login are all done. Still ahead: more reliable per-app exclusion, richer image handling, and a signed, notarized release with a Homebrew cask. Full detail in [ROADMAP.md](ROADMAP.md).

## Contributing

Contributions are welcome. Read [CONTRIBUTING.md](CONTRIBUTING.md) for the workflow, coding standards, and testing expectations, and [ARCHITECTURE.md](ARCHITECTURE.md) for how the pieces fit before making structural changes. Everyone participating follows the [Code of Conduct](CODE_OF_CONDUCT.md).

## Security

Please **don't** open a public issue for security problems — see [SECURITY.md](SECURITY.md) for how to report them privately.

## License

[MIT](LICENSE)
