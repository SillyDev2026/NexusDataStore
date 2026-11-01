# Session safety and usability

Preserve v7 save format 700 and codec 230. Repair confirmed mutation ownership bugs without rewriting persistence. Keep local assignment values on the declaration line.

A targeted compatibility update is preferable to a full rewrite: the existing persistence recovery and codec paths already have regression coverage. A rewrite would enlarge the data-loss risk without evidence of a need.

Detach callback-owned transaction drafts, freeze the interpretation of callback paths by normalizing once, and reject commits after callbacks close/release sessions. Add SetDefault(path, value), returning success, detached resulting value, and whether it inserted. Existing false/zero values must remain intact. Add GetDataSnapshot() for a detached whole-profile read without consuming restore slots. Invalid paths and values must fail without changing data.

Add a portable Luau behavioral test runner with explicit service stubs. It verifies actual module methods but does not claim Roblox backend integration coverage. Keep Studio regressions available and document runtime limitations.
