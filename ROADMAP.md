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

## Phase 2 — Persistence — Planned

The one thing standing between Clickit and daily use: history currently dies with the process.

- [ ] Disk-backed `ClipboardStoring` implementation (SQLite over `libsqlite3`; see ARCHITECTURE.md for why not SwiftData)
- [ ] Schema and migration strategy
- [ ] Load history at launch
- [ ] Reconcile orphaned image files against records on startup
- [ ] Store-level tests reusing the existing protocol test suite
- [ ] Benchmark search and retention at 1,000+ items

Phase 2 requires no changes to views, retention rules, or the monitor. That is the point of the protocol.

## Phase 3 — Images — Planned

Phase 1 captures images already. Phase 3 makes them pleasant to work with.

- [ ] Larger preview on hover or selection
- [ ] Distinguish screenshots from other copied images
- [ ] Thumbnail cache so list scrolling never decodes full-size PNGs
- [ ] Original dimensions and format shown in the row
- [ ] Verify storage-size eviction against real screenshot volumes

## Phase 4 — Native experience — Planned

- [ ] Configurable global shortcut, implemented with `RegisterEventHotKey` (proposed default Option-V)
- [ ] Shortcut recorder UI in Settings, with conflict detection
- [ ] Layout-aware key naming via `UCKeyTranslate`
- [ ] Launch at login (`SMAppService`)
- [ ] Excluded-applications picker instead of typed bundle identifiers
- [ ] More reliable source-application attribution
- [ ] Keyboard navigation polish, including verified focus behaviour in the popover

## Phase 5 — Distribution — Planned

- [ ] Developer ID signing
- [ ] Notarization and stapling
- [ ] GitHub Releases with a signed archive
- [ ] Homebrew Cask
- [ ] Evaluate an update mechanism (Sparkle, or manual release checks) against the no-network commitment

---

## Engineering follow-ups

Not user-facing, but tracked:

- [ ] Adopt Swift 6 language mode (the project already builds warning-free under `SWIFT_STRICT_CONCURRENCY = complete`)
- [ ] Manual verification pass on popover keyboard navigation across keyboard layouts
- [ ] Application icon (the asset catalog currently holds an empty `AppIcon` set)
- [ ] Wire SwiftLint into CI once the rule set has settled

## Explicitly out of scope

These are not "later" items. They are decisions.

- Cloud sync, accounts, cross-device history
- Telemetry, analytics, crash reporting
- AI features, content analysis, OCR of clipboard contents
- Collaboration or sharing
- Automatic paste simulation, which would require Accessibility permission and make Clickit able to type into other applications
