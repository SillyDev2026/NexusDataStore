# Session Safety Implementation Plan

**Goal:** Repair transaction ownership and callback-path bugs and add safe default insertion.
**Architecture:** Retain the existing Session methods and copy-on-write commit path. Add behavioral regressions using the actual module under minimal service stubs.
**Tech Stack:** Luau, Python test bundler, GitHub Actions.
**Spec:** ../specs/2026-11-01-session-safety-design.md

## Constraints and review focus
Preserve record/codec compatibility and same-line local assignments. Test retained draft references, callback-edited paths, released sessions, false defaults, invalid/cyclic values, and unchanged mutation counters.

## Tasks
- [x] Add portable runner and failing regressions for draft ownership, path capture and callback lifecycle.
- [x] Repair failures; add GetDataSnapshot and SetDefault with insertion, existing-value, validation and aliasing tests.
- [x] Run behavioral tests, compile all Lua files, and run static release checks. Update version/docs and CI.
- [ ] Review diff, fix material findings, push the validated update and verify remote commit.
