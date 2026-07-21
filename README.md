# Clickit

Clickit is a lightweight, open-source clipboard-history utility for macOS. It lives in the menu bar and lets users find and reuse recently copied text, links, images, and screenshots without sending data to the cloud.

---

## Development status

**Early development. Not production-ready.**

Clickit is at the end of roadmap **Phase 1**. The core loop works — copy, find, restore, paste — but the app is not signed, not notarized, not distributed, and **history is held in memory only, so it is lost when you quit**. Disk persistence is Phase 2.

Do not rely on Clickit as your only copy of anything.

| Area | Status |
| --- | --- |
| Menu-bar app, popover UI | Working |
| Text / URL / image capture | Working |
| Duplicate detection, search, pin, delete | Working |
| Retention and cleanup rules | Working (over in-memory history) |
| Image files on disk | Working |
| History survives quit | Not yet — Phase 2 |
| Global shortcut | Not implemented — Phase 4 |
| Launch at login | Not implemented — Phase 4 |
| Excluded applications | Partial — see [Privacy](#privacy) |
| Signed release, notarization, Homebrew | Not available — Phase 5 |

## Screenshot

> Placeholder — a screenshot of the menu-bar popover will be added here once the UI settles.

## Core features

- **Menu-bar only.** No Dock icon, no window clutter. Click the icon for a compact popover.
- **Additive, never disruptive.** Command-C and Command-V keep working exactly as macOS intends. Clickit only watches and restores.
- **Text, links, images and screenshots.** Content is classified automatically.
- **Search** across your history as you type.
- **Pin** items you want to keep, **delete** the ones you do not.
- **Duplicate-aware.** Copying the same thing twice moves the existing entry to the top instead of piling up.
- **Pause monitoring** at any time; the menu-bar icon shows which mode you are in.
- **Automatic cleanup** with configurable size, count and age limits.
- **Local only.** No network requests, no accounts, no telemetry, no AI.

## Installation

**There is no release yet.** Clickit is not on Homebrew, and there is no signed application to download. Building from source (below) is the only way to run it today. Distribution is roadmap Phase 5.

## Requirements

- macOS 14.0 (Sonoma) or later
- Xcode 16 or later to build from source
- No third-party dependencies

## Development setup

```bash
git clone https://github.com/<your-account>/clickit.git
cd clickit
open Clickit.xcodeproj
```

Then press Command-R. Or from the command line:

```bash
# Build
xcodebuild build -project Clickit.xcodeproj -scheme Clickit -destination 'platform=macOS'

# Run the tests
xcodebuild test -project Clickit.xcodeproj -scheme Clickit -destination 'platform=macOS'
```

The app launches with no Dock icon (`LSUIElement`); look for the clipboard icon in the menu bar. Clickit is **not sandboxed**, because it writes to `~/Library/Application Support/Clickit/`.

Logs, which contain metadata only and never clipboard contents:

```bash
log stream --info --predicate 'subsystem == "com.clickit.Clickit"'
```

## How clipboard monitoring works

macOS provides no notification when the system pasteboard changes, so the only available mechanism is polling. `ClipboardMonitor` samples `NSPasteboard.general.changeCount` — a single integer — every 0.5 s by default, and only reads the actual pasteboard contents when that integer has moved. The poll is cheap and does not meaningfully register in Activity Monitor.

When a change is detected, Clickit:

1. Skips it entirely if the writing app marked it as concealed, transient, or auto-generated.
2. Reads and classifies the content as text, URL, or image.
3. Skips it if it is empty, unsupported, or came from an excluded app.
4. Skips it if the change was Clickit's own write (restoring an item must not read back as a fresh copy).
5. Hashes the content with SHA-256 to detect duplicates.
6. Moves an existing duplicate to the top, or records a new entry.
7. Runs the retention cleanup.

**Clickit never simulates a paste keystroke.** Clicking an item puts it back on the system clipboard; you press Command-V yourself. This is deliberate — it means Clickit needs no Accessibility permission.

## Local storage

Everything lives on your Mac, under:

```
~/Library/Application Support/Clickit/
└── Images/          # PNG files for copied images and screenshots
```

Text and metadata are held in memory for now (Phase 2 adds a local database in the same directory). Image bytes are always kept as files on disk, with only the filename recorded alongside the entry, so browsing history never pages megabytes of screenshots into memory.

### Retention defaults

| Setting | Default |
| --- | --- |
| Maximum items | 1,000 |
| Maximum storage | 500 MB |
| Text and link retention | 30 days |
| Image and screenshot retention | 7 days |
| Pinned items | Never expire, never auto-deleted |

Cleanup runs at launch, after every capture, and whenever retention settings change. It removes expired unpinned items first, then the oldest unpinned items over the count limit, then the oldest unpinned *images* over the size limit. Removing an image record always deletes its file.

## Privacy

Clipboard history is sensitive by nature — it accumulates passwords, tokens, private messages and screenshots without you thinking about it. Clickit's position is that this data should never leave your machine.

- **No network requests.** Clickit makes none, at all.
- **No accounts, no cloud sync, no cross-device sync.**
- **No telemetry, no analytics, no crash reporting.**
- **No AI or content analysis.** Clickit does not read, classify, or OCR your clipboard beyond deciding whether it is text, a link, or an image.
- **Logs contain metadata only** — type and byte size, never contents.
- **Pause monitoring** and **Clear history** are always one click away.
- **Password managers can opt out.** Clickit honours the [nspasteboard.org](http://nspasteboard.org) conventions, so content marked concealed, transient, or auto-generated is never read or recorded. This depends on the source application setting the marker.

**Excluded applications are only partly implemented.** You can add bundle identifiers in Settings, and copies from those apps are dropped. However, attribution uses the frontmost application at the moment of the copy, which is a best-effort guess rather than a guarantee of which process wrote to the pasteboard. Do not treat it as a security boundary yet. A proper app picker and more reliable attribution are Phase 4.

See [PRIVACY.md](PRIVACY.md) for the full statement.

## Keyboard shortcuts

Inside the popover:

| Key | Action |
| --- | --- |
| Up / Down | Move through history |
| Return | Restore the selected item to the clipboard and close |
| Escape | Clear the search, or close the popover if the search is empty |
| Delete | Delete the selected item (when the search field is empty) |
| Command-Delete | Delete the selected item (always) |

Then press **Command-V** wherever you want to paste.

> The global shortcut to open Clickit from anywhere (proposed default Option-V) is **not implemented yet**. Settings shows it as unavailable rather than pretending it works. See Phase 4.

## Roadmap

Phase 1 (menu-bar app, monitoring, restore, popover) is complete. Phase 2 adds disk persistence, Phase 3 richer image support, Phase 4 the global shortcut and launch-at-login, Phase 5 a signed and notarized release.

Full detail in [ROADMAP.md](ROADMAP.md).

## Contributing

Contributions are welcome. Please read [CONTRIBUTING.md](CONTRIBUTING.md) for the workflow, coding standards, and testing expectations, and [ARCHITECTURE.md](ARCHITECTURE.md) to understand how the pieces fit together before making structural changes.

Everyone participating is expected to follow the [Code of Conduct](CODE_OF_CONDUCT.md).

## Security

Please **do not** open a public issue for security problems. See [SECURITY.md](SECURITY.md) for how to report them privately.

## License

[MIT](LICENSE)
