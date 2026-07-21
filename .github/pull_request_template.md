## What this changes

<!-- A short description of the change and why it is needed. -->

## Related issue

<!-- e.g. Closes #12. For anything larger than a bug fix, an issue should exist first. -->

## Type of change

- [ ] Bug fix
- [ ] New feature
- [ ] Refactor with no behaviour change
- [ ] Documentation
- [ ] Build, CI, or tooling

## How this was tested

<!--
Which tests were added or changed, and what you verified manually.
For clipboard behaviour, say what you copied and what you observed.
Do not paste real clipboard contents.
-->

## Checklist

- [ ] `xcodebuild test -project Clickit.xcodeproj -scheme Clickit -destination 'platform=macOS'` passes
- [ ] The build produces no new warnings
- [ ] Behavioural changes are covered by tests; bug fixes include a test that failed before the fix
- [ ] No force unwraps, force casts, or force `try`
- [ ] No error is silently swallowed; anything caught is surfaced to the user or logged with a reason
- [ ] No persistence, pasteboard, or file-system access was added to a SwiftUI view
- [ ] New system integration sits behind a protocol so it can be tested
- [ ] No third-party dependency was added
- [ ] No clipboard contents are written to the log
- [ ] No emoji in code, comments, documentation, or commit messages

## Documentation

- [ ] README status table updated, if the set of working features changed
- [ ] ROADMAP updated, if a phase item was completed or added
- [ ] ARCHITECTURE updated, if a structural decision changed
- [ ] PRIVACY updated, if what is collected, stored, or logged changed
- [ ] CHANGELOG entry added under "Unreleased"

## Incomplete work

<!--
If this ships something partly implemented, describe the limitation precisely and
say where it is marked in the UI and docs. Stubs must not silently succeed:
see ShortcutService for the reference pattern. Delete this section if it does not apply.
-->

## Notes for the reviewer

<!-- Anything you want a second opinion on, or trade-offs you were unsure about. -->
