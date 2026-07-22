# Contributing to Clickit

Thanks for considering a contribution. Clickit is small and intends to stay that way, so the most useful contributions are usually focused ones.

Everyone participating is expected to follow the [Code of Conduct](CODE_OF_CONDUCT.md).

## Before you start

Read [ARCHITECTURE.md](ARCHITECTURE.md). It explains not just how the pieces fit but why several non-obvious choices were made — why AppKit for the menu bar, why polling, why the store sits behind a protocol. It will save you from proposing something that was already tried.

Check [ROADMAP.md](ROADMAP.md) too, especially the "Explicitly out of scope" section. Cloud sync, telemetry, AI features and automatic paste simulation are settled decisions, not gaps.

For anything larger than a bug fix, open an issue first and describe the approach. That is much cheaper than writing a pull request that gets turned down on direction.

## Getting set up

```bash
git clone https://github.com/<your-account>/clickit.git
cd clickit
open Clickit.xcodeproj
```

Requirements: macOS 14.0 or later, Xcode 16 or later. There are no dependencies to install.

```bash
xcodebuild build -project Clickit.xcodeproj -scheme Clickit -destination 'platform=macOS'
xcodebuild test  -project Clickit.xcodeproj -scheme Clickit -destination 'platform=macOS'
```

The project uses file-system-synchronized groups, so a new `.swift` file in `Clickit/` or `ClickitTests/` joins the target automatically. You should never need to edit `project.pbxproj` by hand, and a pull request that changes it deserves an explanation.

While developing, this is the fastest way to see what the app is doing:

```bash
log stream --info --predicate 'subsystem == "com.clickit.Clickit"'
```

## Coding standards

These are enforced by review, and partly by `.swiftlint.yml`.

- **No force unwrapping** (`!`), no force casts, no force `try`. Implicitly-unwrapped properties are acceptable only for initialisation-order problems, and must carry a comment saying why.
- **Never swallow an error.** Either surface it to the user through `AppEnvironment.lastErrorMessage`, or log it through `ClickitLog` with a comment explaining the recovery. An empty `catch` will not be merged.
- **Keep SwiftUI views small and free of logic.** Views call intents on `AppEnvironment`. They do not touch storage, the pasteboard, or the file system.
- **Put system integration behind a protocol.** Anything that talks to `NSPasteboard`, the file system, or the operating system needs a seam so it can be tested.
- **No third-party dependencies.** Use Apple frameworks. If you believe a dependency is genuinely necessary, open an issue and make the case before writing code.
- **Comment only what is not obvious.** Explain why a decision was made, not what the line does. `// increment the counter` is noise; `// URLs are resolved before image data because a Finder copy carries both` is worth keeping.
- **No emoji** in code, comments, documentation, or commit messages.
- **Never log clipboard contents.** Metadata only — type, byte size, counts. The system log is readable by other processes.

The project builds with `SWIFT_STRICT_CONCURRENCY = complete` and is currently warning-free. Keep it that way; new warnings will be treated as failures.

## Testing

Every behavioural change needs a test. Bug fixes need a test that fails before the fix.

Guidelines that come from how the existing suite is built:

- **Test through the protocol seams.** `MockPasteboardService` stands in for `NSPasteboard`. Use it rather than reaching for the real one.
- **Do not mock the file system.** `ClickitTestCase` gives you a real scratch image directory, so file creation and deletion are genuinely verified. Mocking that away would defeat the purpose of the image-retention tests.
- **Drive the monitor with `poll()`**, not by waiting on its timer. Sleeping in tests makes them slow and flaky.
- **Inject `now`.** Retention rules take a date parameter precisely so age-based behaviour can be tested without waiting.
- **Do not add UI tests for system clipboard behaviour.** They are slow, fragile and machine-dependent. The protocol seams make them unnecessary.

Use `ClickitTestCase` as your base class. It provides an isolated `UserDefaults` suite and scratch directory per test, torn down afterwards, so the suite never touches real user data. Note that it overrides the `async` variants of `setUp` and `tearDown`, because only those can be actor-isolated.

## Pull requests

1. Branch from `main`.
2. Keep the change focused. Unrelated refactors in the same pull request make review harder and are likely to be asked for separately.
3. Make sure `xcodebuild test` passes and the build is warning-free.
4. Update the docs that your change affects — README status table, ROADMAP checkboxes, ARCHITECTURE if you changed a structural decision, PRIVACY if you changed what is collected or stored.
5. Add an entry to [CHANGELOG.md](CHANGELOG.md) under "Unreleased".
6. Fill in the pull request template.

Write commit messages in the imperative mood, with a short subject line and a body explaining why when the reason is not obvious.

## Documenting incomplete work

Clickit is in early development, and half-built features are expected. The rule is that they must be **visibly** half-built:

- Never ship a stub that silently succeeds. When a feature is only partly built, make the gap unmistakable in code and in the UI.
- Mark unfinished behaviour in the UI. The reassignable global shortcut is the reference example: the binding works, but it is not editable yet, so Settings shows it read-only with a plain "cannot be changed yet" note rather than an editable field that does nothing.
- Say so in the README status table and in ROADMAP.
- If a feature is partly implemented, describe the limitation precisely. "Excluded applications use best-effort attribution and are not a security boundary" is useful; "may not always work" is not.

A feature that appears to work but does not is worse than one that is plainly absent.

## Reporting bugs and requesting features

Use the issue templates. For bugs, macOS version and reproduction steps matter most.

**Do not include real clipboard contents in an issue.** Redact anything sensitive, and never paste a screenshot of your clipboard history.

For anything with security or privacy implications, follow [SECURITY.md](SECURITY.md) and report it privately instead of opening an issue.
