# Roadmap

Clickit ships in phases. Each phase is a usable increment, not a checkpoint on the way to one big release.

Status legend: **Done**, **In progress**, **Planned**.

---

## Phase 1 — Foundation — Done

The vertical slice: copy something, find it, put it back.

- [x] Menu-bar application (`NSStatusItem`, no Dock icon)
- [x] Clipboard text monitoring via `NSPasteboard` change count
- [x] In-memory history
- [x] Clipboard item restoration
- [x] Basic popover UI

Delivered beyond the original scope, because the protocol seams made it cheap and the retention tests needed real data to work against:

- [x] URL and image classification
- [x] Duplicate detection and promotion
- [x] Search, pin, delete
- [x] Retention cleanup rules
- [x] Image files on disk under Application Support
- [x] Pause monitoring, with the state shown in the menu-bar icon
- [x] Settings window
- [x] nspasteboard.org do-not-record conventions honoured, so password managers can opt out
- [x] 63 unit tests

## Phase 2 — Persistence — Done

History survives quitting.

- [x] Disk-backed `ClipboardStoring` implementation (SQLite over the system `libsqlite3`; see ARCHITECTURE.md for why not SwiftData)
- [x] Schema and migration strategy keyed off `PRAGMA user_version`, WAL mode
- [x] Load history at launch as a write-through cache
- [x] Reconcile orphaned image files against records on startup
- [x] Shared contract test suite, so both stores are held to identical behaviour
- [x] Graceful fallback to in-memory history if the database cannot be opened
- [x] Unpinned history cleared when the Mac restarts, detected from the kernel boot time, on by default and switchable in Settings
- [ ] Benchmark search and retention at 1,000+ items

Phase 2 required no changes to views, retention rules, or the monitor. That was the point of the protocol.

## Phase 3 — Images — In progress

Phase 1 captures images already. Phase 3 makes them pleasant to work with.

- [ ] Larger preview on hover or selection
- [ ] Distinguish screenshots from other copied images
- [x] Thumbnail cache so list scrolling never decodes full-size PNGs (shipped in 0.2.1)
- [ ] Original dimensions and format shown in the row
- [ ] Verify storage-size eviction against real screenshot volumes

## Phase 4 — Native experience — In progress

- [x] Global shortcut to open the clipboard picker on the active display, via `RegisterEventHotKey` (default Command-Shift-V)
- [x] Global Option-Shift-S shortcut for a selected screenshot copied directly to the clipboard
- [ ] Make the shortcut reassignable: a recorder UI in Settings with conflict detection (it is fixed and shown read-only today)
- [ ] Layout-aware key naming via `UCKeyTranslate`
- [x] Auto-paste after selecting an item, so Command-V is not needed. Shipped enabled by default; it uses Accessibility permission, with a first-run prompt that explains why and a clipboard-only fallback when permission is refused
- [x] Paste queue for lining up history items, activating automatically when staged, and pasting them in sequence (suggested by Yavuz on Product Hunt)
- [x] Launch at login (`SMAppService`)
- [ ] Excluded-applications picker instead of typed bundle identifiers
- [ ] More reliable source-application attribution
- [ ] Keyboard navigation polish, including verified focus behaviour in the popover

## Phase 5 — Distribution — In progress

- [x] Application icon
- [x] Unsigned disk image build via `scripts/build-dmg.sh`
- [x] Unsigned builds published to GitHub Releases (v0.1.0 onward)
- [ ] Developer ID signing
- [ ] Notarization and stapling
- [ ] A signed, notarized archive on Releases
- [ ] Homebrew Cask
- [ ] Evaluate an update mechanism (Sparkle, or manual release checks) against the no-network commitment

---

## Engineering follow-ups

Not user-facing, but tracked:

- [ ] Adopt Swift 6 language mode (the project already builds warning-free under `SWIFT_STRICT_CONCURRENCY = complete`)
- [ ] Manual verification pass on popover keyboard navigation across keyboard layouts
- [ ] Wire SwiftLint into CI once the rule set has settled

## Explicitly out of scope

These are not "later" items. They are decisions.

- Cloud sync, accounts, cross-device history
- Telemetry, analytics, crash reporting
- AI features, content analysis, OCR of clipboard contents
- Collaboration or sharing
- Automatic paste simulation was originally out of scope for this reason. It was reconsidered on 2026-07-21 and moved into Phase 4 as an enabled-by-default feature; see that phase for the conditions attached.
