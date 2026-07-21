# Architecture

This document describes how Clickit is put together and, more importantly, why. Read it before making structural changes.

## Guiding constraints

1. **The system clipboard must keep behaving normally.** Clickit is an additive observer. It never intercepts Command-C, never simulates Command-V, and never installs an event tap.
2. **Nothing leaves the machine.** No network stack is linked, no endpoint is called.
3. **SwiftUI views hold no persistence or system logic.** Everything system-facing sits behind a protocol so it can be replaced in tests.
4. **No third-party dependencies.** Apple frameworks only.

## Project layout

```
Clickit/
├── App/          Composition root, AppKit menu-bar shell
├── Models/       Value types: ClipboardItem, ClipboardItemType, ClickitSettings
├── Services/     Pasteboard, storage, monitoring, retention, shortcuts
│   └── Persistence/  SQLite wrapper and the disk-backed store
├── Views/        SwiftUI popover and settings
├── Utilities/    Hashing, formatting, logging
└── Resources/    Assets.xcassets
ClickitTests/     Unit tests and shared fixtures
```

Two deviations from the original sketch, both forced by Xcode rather than chosen:

- **`ClickitTests/` is a sibling of `Clickit/`, not a subfolder.** An Xcode unit-test bundle is a separate target with its own root folder.
- **`App/` contains `AppEnvironment.swift` and `MenuBarController.swift`** in addition to the app and delegate. The object graph has to be wired somewhere; putting it in `AppDelegate` would have made it unreachable from tests.

The Xcode project uses **file-system-synchronized groups** (`PBXFileSystemSynchronizedRootGroup`, Xcode 16+). Adding a `.swift` file to a folder adds it to the target automatically — there is no `project.pbxproj` churn in pull requests, and no merge conflicts over file references.

## Menu-bar application lifecycle

Clickit is an **accessory application**: `LSUIElement` is set in the generated `Info.plist`, and `AppDelegate` also calls `NSApp.setActivationPolicy(.accessory)` so a build run straight from DerivedData behaves the same. There is no Dock icon and no main window.

```
ClickitApp (@main, SwiftUI App)
  └── NSApplicationDelegateAdaptor → AppDelegate
        ├── AppEnvironment            (object graph, intents)
        └── MenuBarController         (NSStatusItem + NSPopover)
  └── Settings scene → SettingsView
```

`applicationDidFinishLaunching` builds the controller and calls `AppEnvironment.start()`, which runs a cleanup pass and starts the monitor. `applicationWillTerminate` calls `stop()`, which invalidates the poll timer.

### Why AppKit for the menu bar

SwiftUI's `MenuBarExtra` covers the click-to-open case, and it was the first choice. It was rejected because on macOS 14 it **cannot be opened programmatically** — there is no `isPresented` binding. The roadmap requires a configurable global shortcut that opens the *same* popover, which `MenuBarExtra` cannot support without replacing the whole shell later.

`NSStatusItem` plus `NSPopover` hosting an `NSHostingController` keeps that door open, and additionally gives:

- direct control over keyboard focus (an accessory app is not active by default, so `MenuBarController.showPopover` calls `NSApp.activate` before showing, or the search field never receives keystrokes),
- `NSPopover.behavior = .transient` for click-outside dismissal for free,
- `animates = false`, because a utility popover should feel instant.

This is the only place Clickit reaches for AppKit beyond `NSPasteboard`. The popover's content is ordinary SwiftUI.

The status-item icon reflects monitoring state: `list.clipboard` when active, `pause.circle` when paused. `MenuBarController` keeps it in sync with a `withObservationTracking` loop that re-arms itself, since that API fires only once per registration.

### Capture confirmation

The icon swaps to a checkmark for 450 ms whenever `AppEnvironment.captureCount` changes. macOS gives no feedback of its own when content reaches the clipboard, least of all a screenshot, so this is the only signal that Clickit recorded anything.

The icon is **swapped rather than animated**. Menu-bar items sit beside system indicators, where movement reads as something being wrong; a static mark confirms without competing for attention.

`captureCount` is an observable counter rather than a callback, so any number of observers can react and tests can assert on it without installing a spy. It ticks for duplicate captures too, because from the user's side a copy still happened and silence would look like a failure. Each flash cancels the previous pending restore, so a burst of copies ends on the correct icon instead of leaving a checkmark stranded.

## Clipboard observation flow

```
User copies content
        ↓
macOS NSPasteboard changes
        ↓
ClipboardMonitor detects change
        ↓
Content is classified and hashed
        ↓
Duplicate check runs
        ↓
ClipboardStore persists metadata
        ↓
ImageStorageService stores images
        ↓
RetentionService performs cleanup
        ↓
SwiftUI menu-bar popover updates
```

### Polling

macOS offers no change notification for `NSPasteboard`. Polling is not a shortcut here; it is the only public mechanism. `ClipboardMonitor` reads `changeCount` — a single integer — on a `Timer` and touches actual pasteboard contents only when that integer moves. The timer is added to `RunLoop.main` in `.common` mode so it keeps firing while a menu or the popover is tracking.

Default interval is 0.5 s, configurable in Settings and clamped to a 0.1 s floor.

### Rules the monitor applies before reporting a change

- **Empty or unsupported content is dropped.** Whitespace-only strings do not count.
- **Clickit's own writes are dropped.** `PasteboardServicing.write` returns the resulting change count; the caller hands it to `monitor.ignoreChange(count:)`. Without this, restoring an item would immediately read back as a fresh copy.
- **Excluded applications are dropped**, matched against the frontmost app's bundle identifier.
- **Starting takes the current pasteboard as a baseline** and does not capture it. This is what makes Pause meaningful: resuming must not retroactively swallow everything copied while monitoring was off.

The monitor knows nothing about storage or SwiftUI. It reports a `CapturedClipboardContent` to an injected closure; `AppEnvironment` decides what to do with it.

### Do-not-record markers

Before anything is read, `PasteboardService` checks for the informal [nspasteboard.org](http://nspasteboard.org) flavours `org.nspasteboard.ConcealedType`, `TransientType` and `AutoGeneratedType`. If any is present, `read()` returns `nil` and the content is never classified, hashed, or stored. Password managers use `ConcealedType` to ask clipboard managers to stay out of the way; honouring it is the difference between Clickit ignoring a vault and quietly archiving its secrets.

This is a cooperative convention, not an enforcement mechanism — it only works when the writing application sets the marker.

### Classification

Order matters and is deliberate:

1. **URL** — via `NSURL(from:)`, falling back to parsing the pasteboard string (browsers often supply only a string). Restricted to `http`, `https`, `file`, `ftp`, `mailto`.
2. **Image** — `public.png` if present, otherwise TIFF normalised to PNG through `NSBitmapImageRep`. Screenshots arrive as TIFF.
3. **Text** — anything else with a non-blank string.

URLs are resolved before image data because a file copied in Finder carries a file URL *and* sometimes image data; checking images first would record a Finder copy as a screenshot. A real screenshot carries image data and no URL, so it falls through correctly.

## Data model

`ClipboardItem` is a plain `struct`, not a persistence-framework object:

| Field | Notes |
| --- | --- |
| `id` | `UUID` |
| `type` | `.text`, `.url`, `.image` |
| `textContent` | `nil` for images |
| `imagePath` | Filename relative to the image directory; `nil` for text and URLs |
| `contentHash` | SHA-256 fingerprint, used for duplicate detection |
| `createdAt` | First time this content was seen |
| `lastUsedAt` | Updated on capture-again and on restore; drives all age and ordering rules |
| `sourceApplication` | Best-effort bundle identifier |
| `isPinned` | Exempt from all automatic deletion |
| `byteSize` | UTF-8 length for text, file size for images |

Keeping the model free of any storage framework is what allowed the disk-backed store to be added in Phase 2 without touching a single view, retention rule, or existing test.

`ClipboardItemType.rawValue` is folded into hashes and will be persisted, so existing cases must keep their spelling once a release ships.

## Persistence strategy

History is stored in SQLite at `~/Library/Application Support/Clickit/clickit.sqlite`, through the system `libsqlite3` — which ships with macOS and is therefore not a third-party dependency.

All access goes through the `ClipboardStoring` protocol:

```swift
@MainActor
protocol ClipboardStoring: AnyObject {
    var items: [ClipboardItem] { get }
    func item(id: UUID) -> ClipboardItem?
    @discardableResult func promoteDuplicate(contentHash: String, at date: Date) -> Bool
    func insert(_ item: ClipboardItem)
    func markUsed(id: UUID, at date: Date)
    func setPinned(_ isPinned: Bool, id: UUID)
    func delete(ids: [UUID])
    func deleteAll(includingPinned: Bool)
    func loadImageData(for item: ClipboardItem) throws -> Data
}
```

Two implementations exist:

- **`SQLiteClipboardStore`** is what ships. It persists to disk.
- **`InMemoryClipboardStore`** is the fallback used when the database cannot be opened, and the simplest subject for tests.

Both are held to the same standard by `ClipboardStoreContractTests`, an abstract suite that each concrete store inherits, so they cannot quietly diverge.

### Why SQLite rather than SwiftData

- The retention rules are naturally set-based (order by `lastUsedAt`, sum `byteSize`, filter on `isPinned`) and read better as SQL than as fetch descriptors.
- SwiftData's `@Model` macro requires the model to be a managed class, which is exactly the coupling `ClipboardStoring` exists to avoid. `ClipboardItem` stays a plain `struct`.
- It keeps the macOS 14.0 floor comfortable, with no framework-version caveats.

### Write-through cache

`items` is an in-memory array loaded from the database at launch. Every mutation updates the array **and** the database together; if the write fails, the cache is left untouched, so memory never claims something the database does not hold.

This is what keeps search, retention and the views synchronous — `items` is still a plain array, exactly as it was before persistence landed. The cache is affordable because history is bounded (1,000 items by default) and image bytes are never in it, only filenames.

Writes cannot throw through `ClipboardStoring`, so `SQLiteClipboardStore` takes an `onError` closure. `AppEnvironment` routes it to `lastErrorMessage`, which surfaces as a banner in the popover. A failed write is never dropped silently.

### Schema and migrations

One table, `items`, plus two indexes: a unique index on `content_hash` and a descending index on `last_used_at`. The unique index means duplicate prevention is enforced by the schema, not only by the capture path, so a bug upstream cannot corrupt the history.

Migrations are keyed off `PRAGMA user_version` and run in order. Adding a version means appending a case, never editing an existing one. The database opens in WAL mode, which survives an unclean shutdown far better than the rollback journal — and Clickit is usually killed rather than quit.

A row that fails to decode is skipped rather than aborting the load, so one bad record never costs the user their history.

### Startup reconciliation

Image files with no surviving record are deleted when the store opens. These accumulate when a delete is interrupted between removing the row and unlinking the file. The store asks `ImageStoring` for the filenames it holds rather than reading the directory itself, so the storage location stays owned by one type — and tests cannot be pointed at the real user directory by accident.

### Fallback

If the database cannot be opened at all, `AppEnvironment` falls back to `InMemoryClipboardStore` and surfaces an explicit warning that history will not be saved. A corrupt or unwritable file costs persistence, not the whole application.

### Ordering

`items` is always **most-recently-used first, with pinned entries left in place**. Pins are hoisted to the top by the *view*, not the store. This is a deliberate split: retention rules walk the store's order looking for the oldest candidates, and never have to reason about pins except to skip them.

## Image storage

Image bytes never live in the item record. `ImageStorageService` writes PNGs to:

```
~/Library/Application Support/Clickit/Images/<uuid>.png
```

and the record keeps only the filename. This keeps history listing and searching cheap regardless of how many screenshots are stored.

The service is behind `ImageStoring`, so tests use a real implementation pointed at a scratch directory — file creation and deletion are genuinely exercised rather than mocked.

Clickit is **not sandboxed**, which is what allows the conventional Application Support path. If the directory cannot be created, `AppEnvironment` falls back to a temporary directory and logs the failure rather than refusing to launch.

**File lifetime is owned by the store.** `InMemoryClipboardStore.delete` and `deleteAll` unlink the associated files. A failed unlink is logged and leaves an orphan; it does not abort the record removal. `AppEnvironment` also discards the freshly written file when a captured image turns out to be a duplicate.

## Duplicate detection

`ContentHasher` produces a SHA-256 digest over the type's raw value, a separator byte, and the content bytes. Folding the type in means the string `https://example.com` captured as `.url` never collides with the same string captured as `.text`.

Hashing is exact: case- and whitespace-sensitive. Two snippets that differ only in trailing whitespace are two entries. This is intentional — normalising would silently discard content the user may have copied deliberately.

On capture, `AppEnvironment` asks the store to `promoteDuplicate(contentHash:at:)`. If a match exists it moves to the front and its `lastUsedAt` is refreshed while `createdAt` is preserved; otherwise the new item is inserted.

## Session lifecycle

History is scoped to the current session at the machine rather than kept as a permanent archive. `SessionResetService` clears unpinned items when the Mac has restarted since Clickit last ran.

Restarts are detected by reading the kernel boot time (`sysctl` `KERN_BOOTTIME`) and comparing it against the value recorded at the previous launch. Boot time does not change when the app is relaunched, so quitting Clickit, or having it crash, clears nothing — only a genuine restart does. That distinction is the reason persistence and session-scoping are not in conflict.

Details worth knowing:

- The reset runs **before** retention cleanup. A restart discards the whole unpinned working set, so ageing out items that are about to be dropped is wasted work.
- The boot time is recorded even when the behaviour is switched off, so re-enabling it later does not treat the running session as new and wipe history unexpectedly.
- The first ever launch has no recorded value; it adopts the current boot time rather than clearing history the user cannot have accumulated yet.
- Comparison uses a five-second tolerance. The reported boot time shifts slightly when the system clock is adjusted, and an exact comparison would occasionally clear history without a restart having happened.
- If the boot time cannot be read, nothing is cleared. Failing closed here would silently destroy data.

`BootTimeProviding` is a protocol so a restart can be simulated in tests without one.

## Retention cleanup

`RetentionService` is stateless. Every decision derives from the store snapshot, a `ClickitSettings` value, and an injected `now`, which is what makes age-based rules testable without waiting or stubbing a global clock.

These are the backstop for machines that go a long time between restarts; in normal use the session reset above is what bounds history.

Rules run in order:

1. **Expired unpinned items.** Per-type windows: 30 days for text and links, 7 days for images. Measured from `lastUsedAt`, so re-using an old entry resets its clock.
2. **Oldest unpinned items over the count limit.** Pinned entries count toward the total but are never the ones removed, so a user who pins more than `maxItems` keeps all of them and simply stops accumulating new history.
3. **Oldest unpinned images over the size limit.** Only images are evicted here. Images are what consume the disk budget, and dropping text to satisfy a byte limit would lose far more history than it reclaims. If only text remains the pass stops rather than looping.
4. **Pinned items are never removed automatically**, by any rule.

Removing an image record always removes its file, because deletion goes through the store.

Cleanup runs at launch, after every capture, and whenever retention settings change. It returns a `RetentionReport` rather than logging blindly, so tests can assert on it.

## Shortcut handling

**Not implemented.** `ShortcutService` exists, conforms to `GlobalShortcutRegistering`, reports `isSupported == false`, and throws from `register`. It deliberately does not register anything: a stub that silently succeeded would be indistinguishable from a broken hotkey. Settings displays the proposed binding with an explicit "not implemented yet" note.

The binding itself is already a value type, `KeyboardShortcutConfiguration`, stored as a virtual key code plus modifier flags rather than a character, so it will survive keyboard-layout changes. The proposed default is Option-V, defined in exactly one place so Settings can replace it.

The intended implementation is Carbon's `RegisterEventHotKey`, still the only public API for a global hotkey that does **not** require Accessibility permission. `AppEnvironment.openPopoverRequested` is already wired to `MenuBarController.showPopover`, so the handler has somewhere to land.

## Privacy boundaries

- No networking framework is used anywhere in the codebase.
- Logs record type and byte size only. Clipboard contents are never logged, at any level, because the log stream is readable by other processes on the machine.
- `Pause Monitoring` stops the timer entirely rather than filtering after the fact.
- `Clear History` keeps pinned items by default; the Settings screen offers a separate destructive action that removes everything.
- Unpinned history does not outlive a restart by default, which bounds how long a copied password or token can sit on disk.
- Excluded applications are enforced in the monitor, before content reaches the store. Attribution is best-effort (`NSWorkspace.frontmostApplication`) and is marked as such in the UI, because it is a heuristic, not a guarantee of which process wrote to the pasteboard.

## Threading

Clickit is a small, UI-driven application. Almost everything is `@MainActor`-isolated on purpose: `ClipboardMonitor`, `ClipboardStore`, `RetentionService`, `PasteboardService`, and `AppEnvironment`. This is not laziness — `NSPasteboard` and `NSStatusItem` are main-thread APIs, and the data volume (at most a few thousand small records) does not justify the complexity of cross-actor coordination.

The exception is `ImageStoring`, which is `Sendable` and does plain file I/O, so it can be moved off the main actor when image volumes justify it.

`SQLiteDatabase` is deliberately not thread-safe. It is owned by a `@MainActor` store, so every call already arrives on the main actor, and adding locking would guard against a caller that does not exist.

The project builds with `SWIFT_STRICT_CONCURRENCY = complete` and **no warnings**. Swift 6 language mode is a tracked follow-up, not a blocker.

`ClipboardMonitor` has no `deinit` cleanup by design: the run loop owns the timer, and invalidating it from a `deinit` that may run off the main actor would be a data race. Owners call `stop()` explicitly.

## Error handling

The project rule is that errors are neither force-unwrapped away nor silently swallowed.

- There are **no force unwraps** in the codebase. Two implicitly-unwrapped properties exist (`AppEnvironment.monitor`, because its capture closure captures `self`; and test fixture properties), both assigned during initialisation.
- Errors that the user should know about — a failed image write, restoring an item whose file has vanished — surface as `AppEnvironment.lastErrorMessage` and appear as a dismissible banner in the popover.
- Errors the user can do nothing about — a failed unlink of an already-orphaned file, an undecodable settings blob from an older build — are logged through `ClickitLog` at `error` level and recovered from with a documented fallback.
- `ImageStorageError` is a `LocalizedError` with messages written for a person, not a stack trace.

## Testing strategy

105 unit tests, run with `xcodebuild test`.

The system boundary is the protocol seam. `PasteboardServicing` is mocked (`MockPasteboardService`), so capture, deduplication, self-write suppression and exclusion rules are all exercised deterministically without a window server. `ImageStoring` is *not* mocked — tests use the real service pointed at a scratch directory, so file creation and deletion behaviour is genuinely verified.

The concrete `PasteboardService` gets its own suite driven against a private `NSPasteboard.withUniqueName()` rather than `NSPasteboard.general`. That covers the parts a mock cannot — real type negotiation, TIFF-to-PNG normalisation, and the do-not-record markers — without touching the developer's actual clipboard.

The monitor is driven by calling `poll()` directly rather than by waiting on its timer, which keeps the suite fast and free of flakes. Timer scheduling itself is covered only by `start()`/`stop()` state assertions.

There are deliberately **no UI tests** for system clipboard behaviour in this milestone. They would be slow, fragile, and dependent on machine state; the protocol seams make them unnecessary for the logic that matters.

Coverage by area:

| File | Covers |
| --- | --- |
| `ContentHasherTests` | Fingerprint stability, type separation, case and whitespace sensitivity |
| `ClipboardStoreContractTests` | Ordering, duplicate promotion, pinning, image-file deletion, byte accounting. Abstract; inherited by both store suites so they cannot diverge |
| `SQLiteClipboardStoreTests` | Everything above, plus durability across reopen, field round-trips, schema version, orphan reconciliation, unique-hash enforcement |
| `RetentionServiceTests` | Per-type expiry, count limit, size limit, pinned preservation, idempotence |
| `ClipboardMonitorTests` | Change detection, self-write suppression, exclusions, pause baseline |
| `PasteboardServiceTests` | Real-pasteboard classification, TIFF normalisation, do-not-record markers, write round-trips |
| `SessionResetServiceTests` | Restart detection, pinned-item survival, image cleanup, opt-out, clock drift, unreadable boot time |
| `AppEnvironmentTests` | End-to-end capture, classification, restore, duplicate file cleanup |

Fixtures live in `ClickitTests/TestSupport.swift`. `ClickitTestCase` provides a scratch image directory and an isolated `UserDefaults` suite per test, both torn down afterwards, so the suite never touches real user data.

The `async` variants of `setUp`/`tearDown` are used throughout because only those can be actor-isolated, and the fixtures hand out main-actor state.
