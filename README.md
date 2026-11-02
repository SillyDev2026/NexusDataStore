# NexusDataStore

**Typed, session-aware data persistence for Roblox.**

![Version](https://img.shields.io/badge/NexusDataStore-8.0.0-2563eb)
![Codec](https://img.shields.io/badge/Compression-2.6.1-0f766e)
![Luau](https://img.shields.io/badge/language-Luau-00a2ff)
![Platform](https://img.shields.io/badge/platform-Roblox-222222)

NexusDataStore brings standard Roblox DataStore persistence, session ownership, typed player profiles, validation, migrations, snapshots, adaptive compression, and numeric leaderboards into one server-side library.

**Current version:** `8.0.0` · **Compression:** `2.6.1` / codecs `230`–`233` · **Record format:** `700`

> [!IMPORTANT]
> This documentation describes the current source on `main`. Regression scripts are included, but production reliability and performance have not been certified by live-server load testing. Use a separate test universe before deploying changes to existing player data.

## New in 8.0.0 — Reliability, compression correctness and restart hardening

NexusDataStore **v8.0.0** is a major maintenance release built on v7.10.0. It preserves existing data, record format `700`, codecs `230`–`233`, and the soft-shutdown feature. There is **no mandatory migration for saved records**.

### Compression v2.6.1

- **Lossless signed zero:** Integer tagging could previously turn IEEE-754 `-0.0` into `0.0`. It now uses a floating-point tag and is excluded from lossy run grouping; v230–v233 readers remain compatible.
- **Candidate isolation:** An optional codec/transport failure cannot abort other valid candidate encodings. Compression reports and forecasts expose `CandidateFailures`.
- **Safe fallback:** Adaptive mode can persist the validated raw record when every compressor fails and the raw value fits storage limits. Mandatory compression modes **never** silently fall back to raw.
- No data is discarded; size improvements depend on actual player data.

### Soft-shutdown and save/load

- **Concurrent critical flush:** A pool of up to six workers saves different player profiles during the restart window. Each profile retains its authoritative session lock and `UpdateAsync` commit fencing.
- **Pre-save/final-save race:** A delayed early flush no longer claims the final save is ready. Final freeze and flush are still required.
- **Restart recovery:** Failed releases do not count as successful and the store can retry closing safely.
- **Multi-store isolation:** Restart UI identity and replicated profile-ready/error attributes are keyed by the configured store `Name`. The UI still accepts legacy v7.10 transfer screens.
- **Cleanup:** Transferred UI references are cleared after profile loading, and its countdown loop terminates when the player leaves.

### Recommended configuration

~~~lua
local Store = NexusDataStore.new({
    Name = "PlayerData",
    Template = PlayersData,
    Compression = true,
    CompressionPolicy = "always-smallest",
    CompressionTransport = "auto",
    CompressionOptions = {StringDictionary = true, BitPackedIntegers = true, RunLengthArrays = true},
    AutoPlayerLifecycle = true,
    EnableSoftShutdown = true,
    WaitForSessionLock = true,
    SoftShutdownPreSaveSeconds = 20,
    SoftShutdownFreezeSeconds = 6,
    SoftShutdownCloseTimeout = 25,
    AutoSave = true,
    BudgetAware = true,
})
~~~

Install the current `SoftShutdownClient.client.lua` as a **LocalScript in ReplicatedFirst** and make its `STORE_NAME` match your `Name`. Roblox Creator Dashboard **Restart Servers**, not a normal publish, performs the update migration. As before, deploy compatible decoders across all running servers before enabling any new codec.

**Production limitations:** Automated Luau and simulated failures do not certify Roblox infrastructure. Test delayed updates, loading, failed writes, and multiple simultaneous sessions in a published test universe before relying on v8 in production.

## Previously in 7.10.0 — Built-in soft shutdown and session-safe Roblox updates

This version adds a **fully opt-in restart coordinator** and a drop-in, responsive restart screen. It listens for Roblox's supported `game.ServerRestartScheduled` event, saves before the scheduled restart, freezes normal NexusDataStore mutations for the final save, and releases session locks in parallel when the server closes. The **actual teleport is performed by Roblox Restart Servers**; NexusDataStore intentionally does not launch a competing teleport that could strand players or bypass session ownership.

### Install in Roblox Studio

1. Put the newest `DataStore.lua`, `Compression.lua` and `PlayersData` modules in place as usual.
2. Copy `SoftShutdownClient.client.lua` into **ReplicatedFirst as a LocalScript**. The LocalScript creates its own entire GUI, including mobile-friendly scaling, a nonblocking top banner during long countdowns, full-screen saving/migration status in the final 30 seconds, a progress indicator and an arriving-server screen. No GUI objects need to be manually authored. Set its `STORE_NAME` to match your store's `Name`.
3. Configure your player store with:

~~~lua
local Store = NexusDataStore.new({
    Name = "PlayerData",
    Template = PlayersData,
    AutoPlayerLifecycle = true,
    EnableSoftShutdown = true,
    SoftShutdownPreSaveSeconds = 20,
    SoftShutdownFreezeSeconds = 6,
    SoftShutdownCloseTimeout = 25,
    WaitForSessionLock = true,
    LoadTimeout = 60,
    AutoSave = true,
    BudgetAware = true,
})
-- EnableSoftShutdown automatically binds the store's shutdown callback.
-- Do not register a duplicate manual SaveAsync/ReleaseAsync shutdown handler.
~~~

4. Publish the updated scripts to **every server** before using the feature.
5. On Creator Dashboard, publish your game update, then choose **Server Management > Restart Servers**, preferably **Restart only servers with outdated versions** and a delayed restart of at least one minute. Roblox schedules and migrates the server; the library reacts automatically. A normal publish **without Restart Servers** does not migrate existing players.

### Lifecycle and guarantees

- **Scheduled:** A restart notice and countdown appear to players. Attributes on the per-store server `RemoteEvent` let late-joining clients recover the current state. The feature also handles `RobloxMaintenance` scheduled restarts.
- **Pre-save:** At 20 seconds remaining (configurable), the coordinator requests a critical flush of active dirty profiles without dropping their session locks. Gameplay may continue in this phase.
- **Final save:** At six seconds remaining, `Session:Set`, `Increment`, `Mutate`, `Award`, and other NexusDataStore mutation methods return `SOFT_SHUTDOWN_FROZEN`. The final flush retries on errors. **Do not mutate `session.Data` directly**: uncontrolled table edits bypass the mutation freeze.
- **Migration:** Roblox automatically teleports players to updated servers. `PlayerRemoving` releases departing profiles via the existing verified lock-clearing commit. `BindToClose` makes bounded parallel release attempts across remaining profiles; a failed release is never treated as a successful handoff.
- **Arrival:** `WaitForSessionLock` is automatically enabled with soft shutdown and defaults to a 60-second load timeout unless overridden. The destination UI remains on the progress screen until `AutoPlayerLifecycle` confirms `NexusDataStoreProfileReady`; if load fails it shows a reconnect-required error instead of claiming success.
- **Developer diagnostics:** `Store:GetSoftShutdownStatus()`, `Store:On("SoftShutdownStatus", fn)`, `Store:On("SoftShutdownSaveFailed", fn)`, and counters `RestartsScheduled`, `SoftShutdownFlushes` and `SoftShutdownFlushFailed`.

### Important limitations

The restart timestamp is the **earliest scheduled** closure; Roblox may move players later. Scheduled restart notifications are only guaranteed for the **delayed** restart flow and may be absent for immediate/emergency closures. `BindToClose` is the fallback, bounded by Roblox's approximately 30-second shutdown window. Save requests may fail due to data-service outages or budgets: no implementation can guarantee an acknowledged save in those conditions. **Do not store currency/profile state in TeleportData or trust client data**; destination servers must acquire the real DataStore session. The UI depends on the provided LocalScript being installed in both the old and new published versions.

Studio cannot simulate real teleportation. GitHub Luau regressions validate the coordinator state machine and the library compiles, but **real publish/restart tests in a separate Roblox universe are still required**.

## Previously in 7.9.0 — Run-length compression for real player profiles

Compression v2.6.0 adds opt-in **codec 233** for arrays containing repeated **strings, finite numbers, or Booleans**, such as repeated inventory items, progress counters, and status flags. It stores each consecutive run once with its length. No array element, field, or required metadata is discarded.

- **Exact array-level size choice:** RLE is used only when it is smaller than ordinary scalar encoding and, where applicable, existing Boolean bitsets or minimal-width integer arrays. Non-repeating content keeps its efficient representation.
- **Existing bitpacking retained:** Codec 233 also understands compact integer and Boolean encoding. All codecs 230, 231 and 232 remain readable.
- **Strong corruption checks:** Reject zero-length runs, impossible counts, overruns, incomplete arrays, non-scalar run values and adjacent duplicate runs. Preserve checksum and depth/node guards.
- **Developer diagnostics:** `GetCompressionReport()` now reports `RunLengthArrays`, `RunLengthRuns`, and `RunLengthValues`. `GetStorageForecast()` includes run counts and value counts alongside packed bits and expansion.
- **Compatible record schema:** Record format 700, session ownership, revisions and migrations are unchanged.

### Enable RLE after upgrading every server

~~~lua
local Store = NexusDataStore.new({
    Name = "PlayerData",
    Template = PlayersData,
    Compression = true,
    CompressionPolicy = "always-smallest",
    CompressionTransport = "auto",
    CompressionOptions = {
        StringDictionary = true,
        BitPackedIntegers = true,
        RunLengthArrays = true,
    },
    AutoSave = true,
    BudgetAware = true,
})
~~~

`RunLengthArrays = true` makes `"always-smallest"` compare **eight** lossless candidates: codecs 230, 231, 232, and 233 with dictionaries enabled and disabled. The smallest complete stored compressed envelope wins. RLE defaults to **false**, preserving the previous v7.8 writes.

**Safe rollout:** Upgrade every running server to DataStore v7.9.0 with Compression v2.6.0 *before* setting `RunLengthArrays = true`. Older decoders cannot open new codec 233 records. Do not downgrade until such records have been safely rewritten with an older codec, and test in a separate Roblox universe.

**Limitations:** Lossless compression cannot make arbitrary high-entropy data smaller. The mode can increase size and CPU usage, especially when searching eight variants. Failed saves must be handled; Studio and live distributed tests are still necessary.

### Next compression opportunities

Future improvements worth evaluating include **delta encoding of sequential numeric values**, **schema-aware dictionary compression of repeated keys**, and **CPU-aware candidate search** during frequent autosaves. Each needs separate compatibility and performance testing.

## Previously in 7.8.0 — Minimal-width integer bitpacking and storage diagnostics

**Compression v2.5.0** adds an optional lossless **codec 232** for dense arrays of signed integers. Where a v231 array stores each small number with its own byte or tag, v232 packs consecutive integer values into one bitstream using the smallest number of bits needed for the array after zigzag encoding.

- A 256-entry array containing values from `-2` through `1` needs **2 bits per value**, or **512 value bits / 64 bytes**, before its array tag and header. Previous compact encoding needed at least 256 bytes for those values.
- The encoder uses packed arrays only when the complete array representation is smaller than the ordinary compact representation. It supports eligible integers `-32768` through `32767`; other numbers, strings, tables, and Booleans continue using the existing lossless representations.
- The decoder rejects invalid bit widths, short arrays, truncation, nonzero unused padding bits, and noncanonical widths. Checksums, depth/node limits, and the existing session/revision protections remain in place.
- Legacy **codec 230 and codec 231 remain readable**. Codecs 230/231 are still the default write choices. New codec 232 is **opt-in**, so existing saved profiles do not require conversion.

### Enable packed integers safely

Keep the v7.7 full-compression configuration, then add `BitPackedIntegers = true` to its `CompressionOptions`:

~~~lua
local Store = NexusDataStore.new({
    Name = "PlayerData",
    Template = PlayersData,
    Compression = true,
    CompressionPolicy = "always-smallest",
    CompressionTransport = "auto",
    CompressionOptions = {
        StringDictionary = true,
        BitPackedIntegers = true,
    },
    AutoSave = true,
    BudgetAware = true,
})
~~~

With `BitPackedIntegers = true` and `CompressionPolicy = "always-smallest"`, the store evaluates **six** candidates: codecs 230, 231 and 232 with dictionaries on/off. The smallest measured compressed envelope wins. Without this option it retains the previous four-candidate behavior.

**Safe rollout:** First deploy DataStore v7.8.0 with Compression v2.5.0 to **all** servers while leaving `BitPackedIntegers = false`. After old servers drain, enable it. Older codec libraries cannot read records encoded as v232; downgrading readers without migrating those records back is unsafe.

### Better save and load diagnostics

`GetStorageForecast(profile)` now includes the selected codec, whether compression was used, the selection reason, number of candidates checked, estimated bytes saved or expanded, and the packed-integer count and exact value bits. The existing `GetCompressionReport(profile)` also includes `PackedIntegerArrays`, `PackedIntegerValues` and `PackedIntegerValueBits`.

This is **lossless bit-width optimization, not removal of player information**. No compressor can shrink every arbitrary input. Real Roblox Studio multi-server persistence and stress tests are still required before describing the update as production-certified.

## Previously in 7.7.0 — Always compress the complete record

**`CompressionPolicy = "always-smallest"`** guarantees that every successfully written NexusDataStore record uses a **compressed packet envelope**, regardless of data shape, size, threshold or whether raw JSON would be smaller. The policy applies to records written during load acquisition, saves, heartbeats and release.

It evaluates four **lossless** combinations: legacy codec 230 or compact codec 231, each with the string dictionary enabled or disabled. With `CompressionTransport = "auto"`, it also compares buffer versus Base64 storage and picks the smallest compressed **complete persisted envelope**. It never selects a raw table.

### Configure always-smallest compression

~~~lua
local Store = NexusDataStore.new({
    Name = "PlayerData",
    Template = PlayersData,
    Compression = true,
    CompressionPolicy = "always-smallest",
    CompressionTransport = "auto",
    CompressionMinBytes = 0,
    CompressionOptions = {
        StringDictionary = true,
        AllowExpansion = false,
    },
    AutoSave = true,
    BudgetAware = true,
})
~~~

Keep your existing store name, template, schema and other settings. You do **not** need `ForceCompressedBuffer`; that is an older, separate, buffer-only mode that cannot be combined with `CompressionPolicy = "always-smallest"`. The new policy overrides compression thresholds and evaluates both codec modes even when `CompressionOptions.CompactEncoding` is false.

### Measure size and distinguish expansion from savings

~~~lua
local report, err = Store:GetCompressionReport(profile)
if report then
    print("Selection:", report.SelectionReason)
    print("Persisted bytes:", report.StorageBytes)
    print("Raw JSON bytes:", report.RawStorageEstimate)
    print("Selected codec:", report.SelectedCodec)
    print("Expanded:", report.CompressionExpanded)
    print("Extra bytes:", report.ExpansionBytes)
    print("Candidates checked:", report.AlternativeCodecCandidates)
else
    warn("Compression report failed:", err)
end
~~~

**Important limits:** Compression is lossless but **not guaranteed to make every record smaller**. High-entropy, tiny or already-compressed records can grow because checksums, headers and required metadata cannot be removed. If a compressed result exceeds `MaxStoredBytes`, saving returns `STORED_BYTES_EXCEEDED` instead of writing raw data. Unsupported Luau values (including Instances, cyclic tables and nonfinite numbers) are rejected rather than silently deleted. The four codec passes and transport measurements cost more CPU than the default balanced strategy.

**Safe rollout:** Deploy NexusDataStore v7.7.0 with Compression v2.4.0 everywhere **before** enabling this policy. The policy can select codec 231 for any record; old v230-only servers cannot read those packets. Perform staged tests, drain old servers, then enable the mode. Don't downgrade readers while 231 records are present.

The existing `CompressionStrategy = "smallest"` is adaptive and may choose uncompressed storage; `CompressionPolicy = "always-smallest"` deliberately never does.

## Previously in 7.6.0 — Compact binary codec

The new **Compression v2.4.0** retains legacy packet codec `230` by default and adds an opt-in compact packet codec `231`. The compact encoding removes redundant per-value tags where they are unnecessary:

- **Boolean array bit-packing:** eight Booleans per byte. Arrays with at least four Boolean elements use tag `9` plus a canonical bitset; unused trailing bits must be zero.
- **Small signed integer tags:** integers from `-8` through `15` use one byte instead of a tag plus a variable-length integer. Larger numbers and fractions preserve the original lossless encodings.
- **Version-aware decoding:** new decoders understand both v230 and v231. The encoder writes v230 unless `CompressionOptions.CompactEncoding = true`.
- **No data loss:** decoding validates packet magic, version, checksum, canonical varints, array sizes, and padding. The opt-in changes encoding, not data values or record schema.
- **Envelope checks:** compressed record metadata now checks the declared codec against the packet codec before decoding.
- **Same record format:** player record format `700` remains unchanged. Transport selection, session locks, and raw fallback remain available.

### Exact 80+ byte to 30 byte example

For `{Flag = {<64 Boolean values>}}`, the codec regression checks that the legacy v230 packet is at least **80 bytes** and the compact v231 packet is **30 bytes or less**, and verifies the round-trip. These are **packet bytes**, not complete Roblox DataStore record bytes. Other data compress less; irreducible data cannot be shrunk losslessly.

### Enable the new compact encoding

~~~lua
local Store = NexusDataStore.new({
    Name = "PlayerData",
    Template = PlayersData,
    Compression = true,
    CompressionStrategy = "smallest",
    CompressionTransport = "auto",
    CompressionMinBytes = 0,
    CompressionOptions = {
        CompactEncoding = true,
        StringDictionary = true,
        AllowExpansion = false,
    },
})
~~~

Keep existing settings in the same store constructor. `CompactEncoding` requires Compression v2.4.0; a legacy 2.3.x codec cannot write compact packets.

**Safe deployment order:** First distribute v7.6.0 + Compression v2.4.0 to every server with `CompactEncoding = false` (legacy writes, both codecs readable). Let all old servers drain, then opt into 231 writes. Older v2.3.x readers **cannot decode v231**, and may fail to load players during mixed-version deployment. Do not roll back to the old decoder until v231 records have been safely rewritten to v230 or raw format.

To measure a representative packet:

~~~lua
local Compression = require(script.Parent.NexusDataStore.Compression)
local legacy = Compression.CompressTablePacket(myData, {CompactEncoding = false})
local compact = Compression.CompressTablePacket(myData, {CompactEncoding = true})
print("Legacy bytes:", buffer.len(legacy), "Compact bytes:", buffer.len(compact))
assert(Compression.DecompressTable(compact).Flags ~= nil)
~~~

This optimization is strongest for Boolean arrays and small integers. Full player profiles require representative benchmarks and live Roblox verification.

## Previously in 7.5.0

**Opt-in MessagingService-assisted session handoff** reduces time spent waiting for an old server to release a player's profile without bypassing the authoritative `UpdateAsync` lock.

- `EnableSessionHandoff = true` activates handoff messaging and automatically enables `WaitForSessionLock`. The default is `false`.
- Contended loads publish a **targeted release request** to the owning server, including the observed job ID and session ID. Requests have a per-load `SessionHandoffCooldown` (default `6` seconds).
- The owner releases **only if the recorded session is still the target, belongs to a player who has left**, and is not already releasing. Active players and non-player records cannot be displaced by a message.
- A successful release sends a lightweight notification to awaken a waiting load ahead of its normal retry interval. Wait states are cleaned up after each open attempt, avoiding per-player retention.
- Invalid, cross-store, mismatched, or stale (over 30 seconds) messages are rejected. Missing or failed subscriptions fall back to timed polling.
- Added counters: `HandoffRequestsSent`, `HandoffRequestsDeclined`, `HandoffReleaseAttempts`, `HandoffReleaseFailed`, `HandoffWakeups`, `HandoffMessagesFailed`; events `SessionHandoffWake` and `SessionHandoffError`.
- New mock Studio handoff/crash recovery regression and portable message-validation tests.

### Recommended player-store settings

~~~lua
local Store = NexusDataStore.new({
    Name = "PlayerData",
    Template = PlayersData,
    AutoSave = true,
    BudgetAware = true,
    EnableSessionHandoff = true,
    SessionLockRetryInterval = 5,
    SessionHandoffCooldown = 6,
    LoadTimeout = 30,
})
~~~

Keep your current store name, template, schema and compression options in this **same** constructor. The longer retry interval reduces repeated contention requests when notifications work; missing messages can delay a retry until the interval ends. A `LoadTimeout` still bounds waiting. No session is force-stolen. Roblox MessagingService is **best effort**, has message/subscription quotas, and must never be the source of truth for player data. See [Roblox MessagingService](https://create.roblox.com/docs/reference/engine/classes/MessagingService).

**Compatibility:** v7.5.0 keeps record format `700` and compression codec `230`; no saved-data migration is required. Mixed-version servers continue to rely on lock-based retries; old servers do not understand handoff messages. Roll out to a staging universe first. Portable/CLI tests do not establish real-world cross-server service reliability.

## Previously in 7.4.0

Version 7.4.0 adds **opt-in bounded session-lock waiting**, rather than immediately failing every player load with `SESSION_LOCKED`. The default remains unchanged for existing games.

- `WaitForSessionLock = true`: when another server currently owns a key, `OpenAsync` retries ownership acquisition until the existing `LoadTimeout` deadline. It never overwrites an unexpired lock.
- `SessionLockRetryInterval = 2`: delay in seconds between conflicting `UpdateAsync` attempts (accepted range 0.5–30). Repeated attempts consume DataStore budgets. Use this selectively and monitor contention.
- `SESSION_CONTEXT_CONFLICT`: a locally owned session cannot silently be reused for a different explicit `Player` or `UserId`. Matching callers can still share the cached session.
- `SessionLockWait` event and `GetMetrics().SessionLockRetries` provide visibility into contention.
- The Studio mock regression `tests/SessionLockWaitRegression.server.lua` covers two mock servers, safe handoff after release, bounded timeouts, shutdown cancellation, and conflicting user contexts.

Version 7.4.0 introduced **polling-based lock waiting**; v7.5.0 extends it with best-effort MessagingService signals. It is intentionally conservative: no force-stealing and no guarantee of availability when the previous owner is alive or the backend is unavailable. Record format `700` and compression codec `230` are unchanged.

### Enable session contention waiting

~~~lua
local Store = NexusDataStore.new({
    Name = "PlayerData",
    Template = PlayersData,
    WaitForSessionLock = true,
    SessionLockRetryInterval = 2,
    LoadTimeout = 30,
    BudgetAware = true,
})
~~~

Use these options in your **existing single store constructor**, not a second store sharing player keys. For a teleport-heavy game, benchmark the extra request load and monitor `SessionLockRetries`. Failed loads should still be handled; timeout is not permission to replace the locked record.

## Previously in 7.3.0

- `Mutate` commits an independent copy so retained callback drafts and returned nested tables cannot edit live data afterward. This adds one full-data copy to successful transactions; path setters remain copy-on-write.
- `UpdatePath` captures and validates the path before invoking the callback. Editing the caller's path array cannot redirect the write.
- Both callback APIs recheck session activity after callbacks, including cancellation and unchanged-data paths.
- `SetDefault(path, value)` inserts only missing values, preserving existing `false` and `0`. Returns `ok, valueOrError, inserted`; returned tables are detached. A nil default is rejected when the field is missing. Parent-path and schema rules match `Set`.
- `GetDataSnapshot()` returns a detached whole-profile copy without using a retained `Snapshot` restore slot or marking the profile dirty. It is a read helper, not an owned restore token.
- GitHub Actions now compiles Luau and runs behavioral session and codec regressions in addition to static compatibility checks.

```lua
local ok, settings, inserted = profile:SetDefault("Settings", {Music = true, Volume = 0.5})
if not ok then warn(settings) end
local view = profile:GetDataSnapshot()
```

Historical v7.3 note: record format `700`, compression codec `230`, and defaults were unchanged at that time. Version 7.6 now recommends Compression `2.4.0` to support optional v231 packets.

## Contents

1. [Overview](#overview)
2. [Installation](#installation)
3. [Quick start](#quick-start)
4. [How persistence works](#how-persistence-works)
5. [Player lifecycle](#player-lifecycle)
6. [Supported data types](#supported-data-types)
7. [Profile operations and examples](#profile-operations-and-examples)
8. [Saving, releasing, and reading](#saving-releasing-and-reading)
9. [Schema validation and migrations](#schema-validation-and-migrations)
10. [Compression and storage options](#compression-and-storage-options)
11. [OrderedDataStore and leaderboards](#ordereddatastore-and-leaderboards)
12. [Configuration reference](#configuration-reference)
13. [API reference](#api-reference)
14. [Events, errors, and diagnostics](#events-errors-and-diagnostics)
15. [Production guidance](#production-guidance)
16. [Testing and troubleshooting](#testing-and-troubleshooting)

---

## Overview

### Session safety and developer tooling

Version 7.6.0 builds on 7.3.0's safer callback mutations and convenient profile helpers with migration previews, storage forecasts, bounded journals, and copy-on-write updates. It preserves the existing API, strict Luau profile types, and record format `700`; Compression `2.4.0` reads codecs `230` and `231` while defaulting to legacy `230` writes. No record schema migration is required, but enabling v231 must follow the staged rollout above.

- **Path-level copy-on-write:** `Set`, `Delete`, `Append`, `RemoveAt`, and multi-field `Patch` copy only affected table branches before validating and committing, rather than deep-cloning unrelated profile trees for each edit.
- **Incremental direct-change baseline:** Controlled path mutations update their independent observation snapshot by path when possible. Whole-profile changes and uncertain paths retain the full-clone fallback.
- **Same data semantics:** Session locks, validation, migrations, compression, OrderedDataStore interfaces, snapshot ownership, and saved keys remain unchanged.
- **Type checking:** The DataStore module now declares `--!strict` while retaining its `PlayersData.Data`, `Store<T>`, and `Session<T>` APIs. Run Roblox Studio Script Analysis; adding a directive does not constitute a completed analyzer run.
- **Expanded regression suite:** `CopyOnWriteRegression.server.lua` checks nested paths, old-reference isolation, watchers, rollback, and full-record validation with direct-change detection enabled and disabled.
- **One-million-call test harnesses:** `MillionLocalBenchmark.server.lua` and `MillionMockBackendBenchmark.server.lua` provide 1,000,000 iterations per selected case and show observed timings in Studio. They are not recorded benchmark results.

> **Verification scope:** Portable session and codec tests have run in the official Luau CLI. Studio integration suites, million-iteration benchmarks, live DataStore reliability, and Roblox-aware type analysis remain unverified. See [validation results](./docs/VALIDATION-7.3.0.md) and [testing instructions](#testing-and-troubleshooting).

### Developer tools

| Feature | Benefit | Persistence impact |
| --- | --- | --- |
| **Migration preview** | Inspect schema migrations and reconciled data before deploying; includes a field-level diff and full schema validation. | None; only operates on a clone in memory. |
| **Storage forecast** | Estimate the current record's encoded storage size, capacity usage, warning threshold, transport, and remaining space. | None; encodes locally without writing to Roblox DataStore. |
| **Bounded change journal** | Keep the last N committed mutation paths and timestamps to debug unexpected updates. | None; the journal is memory-only and disabled by default. |
| **Consistent Luau style** | Keep local assignments on one line, preserve strict typing, standardize indentation, and run a formatting guard in CI. | No record-format changes. |

### Developer tool API examples

**Preview a migration** without loading, locking, or saving a player key:

~~~lua
local preview, err = Store:PreviewMigration(oldData, 1, "ExampleKey")
if preview then
    print("Upgraded schema:", preview.ToVersion)
    print("Changes:", #preview.Changes)
    -- preview.Data is an independent table; only store it after review.
else
    warn("Migration failed:", err)
end
~~~

Migration callbacks are invoked by the preview; they should be deterministic and must not independently perform remote writes or irreversible side effects. Failure returns an error instead of replacing saved data.

**Check size before a large update:**

~~~lua
local forecast, err = Store:GetStorageForecast(profile, 0.8)
if forecast then
    print("Stored bytes:", forecast.StorageBytes)
    print("Remaining bytes:", forecast.RemainingBytes)
    print("Capacity ratio:", forecast.Utilization)
    if forecast.NearLimit then warn("Profile is approaching its size limit") end
else
    warn("Storage estimate failed:", err)
end
~~~

The forecast uses the record encoding selection, with an estimated session lock where applicable. It does not predict Roblox request budgets or actual network latency.

**Capture a bounded local mutation audit:**

~~~lua
local Store = NexusDataStore.new({
    Name = "PlayerData",
    Template = PlayersData,
    ChangeJournalLimit = 50,
})

local entries = profile:GetChangeJournal(10)
for _, entry in ipairs(entries) do
    print(entry.MutationId, entry.At, entry.Path)
end
profile:ClearChangeJournal()
~~~

Entries contain timestamps, mutation IDs, and changed paths (not full values, credentials, or player snapshots). Whole-profile operations use a `nil` path. Journals expire when the session ends, do not persist across servers, and are limited to `0–1000` entries per session.

### Why these features were chosen

| Feature | Why it matters | Compatibility |
| --- | --- | --- |
| **Zero-change suppression** | Avoid unnecessary validation, profile copies and watcher dispatch when an operation would not change the value. | Set `SkipUnchangedMutations = true` to opt in; defaults to `false` to preserve existing watcher behavior. |
| **Queued save coalescing** | If another save already persisted the same session while a request waited for the commit lock, the duplicate request can succeed without a second `UpdateAsync`. | Always enabled; never skips release or lock-renewal heartbeats. |
| **Operation profiler** | Diagnose which work is expensive before optimizing or adjusting settings. | Set `ProfileOperations = true` to opt in; defaults to `false`. |
| **Focused regression** | Explicitly checks no-op correctness, watcher behavior, coalesced writes, profiler reporting, and legacy defaults. | In `tests/EfficiencyRegression.server.lua`; requires Roblox Studio execution. |

#### Recommended performance options

~~~lua
local Store = NexusDataStore.new({
    Name = "PlayerData",
    Template = PlayersData,
    SkipUnchangedMutations = true,
    ProfileOperations = true, -- enable temporarily to measure workloads
    AutoSave = true,
    BudgetAware = true,
})
~~~

`SkipUnchangedMutations` skips unchanged `Set`, `Delete`, `Mutate`, and `Patch` calls. It preserves the current dirty flag and does not emit new mutation events for those no-ops. It still validates the **path structure**, so missing parent keys remain errors. `Increment`, `Toggle`, and `UpdatePath` naturally benefit when they delegate to `Set`. Actual changes still pass schema validation and the existing snapshot/commit logic.

~~~lua
local report = Store:GetPerformanceReport()
print("Profiler enabled:", report.Enabled)
print("No-op mutations avoided:", report.NoopMutations)
print("Duplicate saves avoided:", report.SavesCoalesced)
for operation, sample in pairs(report.Operations) do
    print(operation, sample.Count, sample.AverageMs, sample.MaxMs, sample.Failures)
end
~~~

The profiler currently records `MutationDraft` (validation, snapshot preparation and change dispatch) and `DataStoreCommit` (commit-lock wait and commit operation). Times are per-server measurements, not a distributed dashboard. The profiler is for development diagnostics; compare equivalent workloads before claiming speedups.

### Capabilities

| Area | What the library provides |
| --- | --- |
| Persistence | `UpdateAsync`-based writes, revisions, retry handling, error reporting |
| Session management | Ownership locks, heartbeats, conflict checks, player join/leave handling |
| Data model | `PlayersData`-derived Luau types, reconciliation, optional schema rules |
| Mutations | Nested paths, counters, inventory helpers, validated in-memory transactions |
| Data recovery | In-memory snapshots, restore, changes since last persisted snapshot |
| Compression | Codec 230, checksum validation, buffer/Base64 transports, raw fallback |
| Leaderboards | Numeric OrderedDataStore wrapper, ranking, configurable sync from profiles |
| Observability | Events, load/save metrics, request-budget and compression reports |

### Which interface should you use?

- Use **`Store:OpenPlayerAsync(player)`** for a Roblox player; use **`Store:OpenAsync(key)`** for an arbitrary key.
- Use **`Store:GetSession(player)`** after loading; use **`Store:WaitForSession(player, timeout)`** if another script must wait for a session.
- Use **`profile:Set`**, **`profile:Award`**, **`profile:Mutate`**, and other profile methods to change local data safely.
- Use **`profile:SaveAsync()`** for an explicit backend save, and **`profile:ReleaseAsync()`** when done.
- Use **`Store:GetOrderedStore(alias)`** for leaderboards; these stores are separate from compressed player records.

## Installation

### Recommended Roblox Studio layout

Create these ModuleScripts and Scripts in `ServerScriptService`:

~~~text
ServerScriptService
└── Data
    ├── NexusDataStore             ModuleScript (contents of DataStore.lua)
    │   ├── PlayersData            ModuleScript (your data template)
    │   └── Compression            ModuleScript (contents of Compression.lua)
    ├── DataService                ModuleScript (creates and shares one store)
    └── DataBootstrap              Script (starts the service)
~~~

**Requirements**

- The source in `DataStore.lua` must be inside the `NexusDataStore` ModuleScript.
- `PlayersData` is a **required direct child** of `NexusDataStore`; the library reads `require(script.PlayersData)`.
- Place `Compression` beneath `NexusDataStore`, next to it, or supply `CompressionModule`. **Compression v2.4.0 is recommended and required for compact encoding**; 2.3.x remains usable for legacy v230-only installations.
- All persistence code must execute on the **server**. Do not place these modules in `ReplicatedStorage` for clients to control.
- Published experiences must have Roblox DataStore permissions. Enable Studio API access only when appropriate, and use test keys/universes.

The GitHub repository contains [DataStore.lua](./DataStore.lua), [Compression.lua](./Compression.lua), and [regression tests](./tests).

## Quick start

### 1. Create a typed template

`NexusDataStore/PlayersData`:

~~~lua
--!strict
local PlayersData = {
    Coins = 0,
    Gems = 0,
    Level = 1,
    Experience = 0,
    Inventory = {} :: {string},
    Upgrades = {} :: {[string]: number},
    Settings = {Music = true, SFX = true},
    Stats = {Wins = 0, BestTime = 0},
}
export type Data = typeof(PlayersData)
return PlayersData
~~~

The `Data` type flows from `PlayersData` into the store and session types. With `--!strict`, `profile.Data.Coins` has the template's numeric type.

### 2. Create a reusable store module

`Data/DataService`:

~~~lua
--!strict
local NexusDataStore = require(script.Parent.NexusDataStore)
local PlayersData = require(script.Parent.NexusDataStore.PlayersData)

local Store = NexusDataStore.new({
    Name = "PlayerData",
    Template = PlayersData,
    Compression = true,
    CompressionStrategy = "balanced",
    CompressionTransport = "auto",
    CompactSessionLocks = false,
    AutoSave = true,
    AutoSaveInterval = 30,
    BudgetAware = true,
    Reconcile = true,
    ValidateOnWrite = true,
})

return Store
~~~

A ModuleScript is cached per Luau environment, so requiring `DataService` from multiple server Scripts shares the same store object. **Create one store instance for each logical store, not one per player or feature script.**

### 3. Start player lifecycle management

`Data/DataBootstrap`:

~~~lua
local Players = game:GetService("Players")
local Store = require(script.Parent.DataService)

Store:On("PlayerLoadFailed", function(player, errorCode)
    warn("[Data] Could not load", player.UserId, errorCode)
    if player.Parent == Players then
        player:Kick("Your data could not be loaded. Please rejoin.")
    end
end)

Store:On("SessionLost", function(profile, reason)
    warn("[Data] Session ownership lost", profile.Key, reason)
    if profile.Player and profile.Player.Parent == Players then
        profile.Player:Kick("Your data session was lost. Please rejoin.")
    end
end)

Store:AttachPlayerLifecycle()
Store:BindToClose()
~~~

This automatically starts loading existing/new players and attempts release on departure and shutdown. Register important failure listeners **before** calling `AttachPlayerLifecycle()`.

### 4. Use the store from another server script

~~~lua
local Store = require(game:GetService("ServerScriptService").Data.DataService)

local function awardCoins(player: Player, amount: number)
    local profile, err = Store:WaitForSession(player, 10)
    if not profile then return false, err end
    if amount <= 0 or amount > 1000 then return false, "INVALID_REWARD" end
    return profile:Award("Coins", amount)
end
~~~

In actual game logic, compute rewards on the **server**; do not trust arbitrary currency amounts sent by a client.

## How persistence works

NexusDataStore maintains a local **session** representing the player data currently owned by a server.

~~~text
Player connects
    |
    v
OpenPlayerAsync -> UpdateAsync
    |
    +-- Decode existing raw/compressed record (or create from template)
    +-- Reject active lock owned by another session
    +-- Run missing schema migrations
    +-- Reconcile template + validate profile
    +-- Acquire session lock with a unique session ID
    v
Active profile in server memory
    |
    +-- Get / Set / Mutate / Award / Patch
    +-- Autosave or SaveAsync -> UpdateAsync
    +-- Heartbeat -> renew lock
    v
Player leaves / ReleaseAsync
    |
    +-- Persist final snapshot and clear lock
    v
Session released
~~~

### Record layout

A standard record includes the following logical fields:

| Field | Meaning |
| --- | --- |
| `Format` | Persistent record version, currently `700` |
| `SchemaVersion` | Your application's schema version |
| `Revision` | Revision used to detect write conflicts |
| `Data` | Validated player-data table |
| `CreatedAt` / `UpdatedAt` | Record timestamps |
| `Lock` | Server job ID, session ID, heartbeat timestamp, expiration |
| `LastCommitId` | Commit identifier for checking ambiguous write acknowledgements |

The on-disk representation can be a raw table or an envelope containing a compressed packet; **do not edit stored record metadata directly**.

### Why session locks matter

An active session belongs to a specific server job and session ID. Another server opening the same key cannot overwrite an unexpired active lock. Heartbeats renew lock expiration, and saves verify ownership and revision within the `UpdateAsync` callback.

Roblox may fail to acknowledge an operation even when it has committed. In that case, the library performs an uncached verification read to look for matching ownership or the latest commit ID. An unverified outcome is **not** treated as a confirmed save.

Session locking reduces cross-server conflicts; it cannot guarantee a successful write during a Roblox outage or after a server is forcibly terminated.

## Player lifecycle

### Option A — automatic lifecycle (recommended)

Use **one** of these approaches:

~~~lua
Store:AttachPlayerLifecycle() -- after registering your listeners
-- Or set AutoPlayerLifecycle = true in the constructor, not both.
~~~

The library handles `PlayerAdded`, `PlayerRemoving`, and players already connected when attachment begins. Set `WaitForSessionLock = true` in the constructor to wait for another server to release a locked session rather than failing the load immediately. The server must still call `Store:BindToClose()` (or handle shutdown explicitly).

### Option B — custom lifecycle

Use this instead when you need custom player initialization or error handling. **Do not also enable automatic lifecycle.**

~~~lua
local Players = game:GetService("Players")
local Store = require(script.Parent.DataService)

local function load(player: Player)
    local profile, err = Store:OpenPlayerAsync(player)
    if not profile then
        warn("Load failed:", err)
        if player.Parent == Players then player:Kick("Data load failed; please rejoin.") end
        return
    end
    if player.Parent ~= Players then
        local ok, releaseErr = profile:ReleaseAsync()
        if not ok then warn("Late release failed:", releaseErr) end
        return
    end
    print("Profile ready:", player.UserId, profile.Data.Coins)
end

Players.PlayerAdded:Connect(function(player) task.spawn(load, player) end)
for _, player in ipairs(Players:GetPlayers()) do task.spawn(load, player) end

Players.PlayerRemoving:Connect(function(player)
    local profile = Store:GetSession(player)
    if profile then
        local ok, err = profile:ReleaseAsync()
        if not ok then warn("Release failed:", err) end
    end
end)

Store:BindToClose()
~~~

### Arbitrary keys

You can persist non-player data with an explicit key:

~~~lua
local profile, err = Store:OpenAsync("Guild_123")
if not profile then
    warn(err)
    return
end

local ok, saveErr = profile:Set("Coins", 500)
if not ok then warn(saveErr) end

local released, releaseErr = profile:ReleaseAsync()
if not released then warn(releaseErr) end
~~~

The key still uses the **same player-data template and schema**, so use a separate store with an appropriate template/name for structurally different records. Never create conflicting live sessions for the same keys.

## Supported data types

This specific NexusDataStore serializer intentionally supports a narrower set than the entire Roblox DataStore API.

| Value type | Example | Notes |
| --- | --- | --- |
| Boolean | `true` / `false` | Supported |
| Number | `100` / `12.5` / `-8` | Must be finite; safe integers recommended |
| String | `"Legendary"` | Strings and keys must pass validation |
| Dense array | `{"Sword", "Potion"}` | Contiguous numeric indices starting at 1 |
| String-keyed dictionary | `{Speed = 3, Luck = 2}` | No mixed numeric/string keys |
| Nested table | `{Settings = {Music = true}}` | Respect depth/node/size limits |
| Missing/optional field | `nil` | Omitted field; template reconciliation may restore it |
| `Vector3`, `Color3`, `CFrame` | Convert to numbers/arrays | Not persisted directly |
| `Instance`, `EnumItem` | Convert to stable IDs/names | Not persisted directly |
| `buffer` | Not supported in player `Data` | Binary codec uses buffers for its **transport**, not as nested saved values |
| Function, thread, cyclic/sparse table, `NaN`, infinity | Rejected | Do not save |

For a position, store serializable components:

~~~lua
local position = Vector3.new(12, 5, -9)
profile:Set("Position", {X = position.X, Y = position.Y, Z = position.Z})

local saved = profile:Get("Position")
local restored = Vector3.new(saved.X, saved.Y, saved.Z)
~~~

Add `Position = {X = 0, Y = 0, Z = 0}` to your template before using that example.

## Profile operations and examples

All following snippets assume `profile` is an **active** loaded session using the Quick Start template. Methods such as `Set` return `success, error?`; methods such as `Award` return `success, valueOrError`.

### Read values

~~~lua
local coins = profile:Get("Coins")
local level = profile:GetOr("Level", 1)
local hasInventory = profile:Has("Inventory")
local musicEnabled = profile:Get({"Settings", "Music"})
print(coins, level, hasInventory, musicEnabled)
~~~

`Get` returns a copy for table values, not a mutable reference to the active profile.

### Set, delete, and patch

~~~lua
local ok, err = profile:Set("Gems", 125)
if not ok then warn(err) end

profile:Set({"Settings", "Music"}, false)
profile:Patch({
    {Path = "Level", Value = 10},
    {Path = {"Settings", "SFX"}, Value = true},
})

-- Removes the field from this profile.
-- Its template default may return when the profile is reconciled on load.
local deleted, deleteErr = profile:Delete("Gems")
if not deleted then warn(deleteErr) end
~~~

Use a path array for nested keys: `{"Settings", "Music"}`, not a dotted string such as `"Settings.Music"`.

### Currency and progression

~~~lua
local rewarded, balance = profile:Award("Coins", 250)
local spent, remaining = profile:Spend("Coins", 50)
local leveled, newLevel = profile:Increment("Level", 1)
local bounded, nextLevel = profile:IncrementClamped("Level", 1, 1, 100)

if not rewarded then warn("Reward failed:", balance) end
if not spent then warn("Purchase failed:", remaining) end
~~~

`Spend` checks the available amount. All progression remains server-authoritative; validate the action that earns or spends currency.

### Inventory, settings, and maps

~~~lua
local added, sizeOrError = profile:Append("Inventory", "Potion")
local removed, itemOrError = profile:RemoveAt("Inventory", 1)
local toggled, musicOrError = profile:Toggle({"Settings", "Music"})

local upgraded, newValue = profile:UpdatePath({"Upgrades", "WalkSpeed"}, function(oldValue)
    return (oldValue or 0) + 1
end)

if not added then warn(sizeOrError) end
if not removed then warn(itemOrError) end
if not toggled then warn(musicOrError) end
if not upgraded then warn(newValue) end
~~~

`UpdatePath` can cancel by returning `nil`, producing the status `"CANCELLED"` in its third return value.

### Atomic in-memory multi-field changes

For a purchase affecting both currency and inventory, use **one** `Mutate` call:

~~~lua
local ok, result, status = profile:Mutate(function(data)
    if data.Coins < 100 then return false end
    data.Coins -= 100
    table.insert(data.Inventory, "IronSword")
    return "Purchased"
end)

if not ok then
    warn("Mutation rejected:", result)
elseif status == "CANCELLED" then
    print("Not enough coins")
else
    print(result)
end
~~~

The mutation is atomic **inside the current in-memory profile**, not across multiple DataStore keys. It is validated and marked dirty; it does **not** automatically mean a backend write has finished.

### React to profile changes

~~~lua
local subscription = profile:Watch("Coins", function(newValue, oldValue)
    print("Balance changed:", oldValue, "->", newValue)
end)

profile:Award("Coins", 20)
subscription:Disconnect()
~~~

Watchers fire for the library's controlled mutations. For direct table edits, the change detector may report a broader change rather than the exact field.

### Snapshots, rollback, and diffs

~~~lua
local checkpoint = profile:Snapshot("BeforeUpgrade")
profile:Award("Coins", 500)

local changes = profile:DiffFromPersisted()
print("Changes since last save:", #changes)

local restored, err = profile:Restore(checkpoint)
if not restored then warn(err) end
~~~

Snapshots are kept **in server memory** and are subject to `MaxSnapshots`. `Restore` requires a snapshot still owned by the same session, and always restores its internally retained data rather than a caller-modified copy. It returns `SNAPSHOT_NOT_OWNED` for foreign or evicted snapshots. These are not permanent Roblox DataStore backups or historical DataStore versions.

## Saving, releasing, and reading

### Save priorities

~~~lua
local saved, err = profile:SaveAsync("normal")
if not saved then warn(err) end

-- Use sparingly for explicit high-value actions.
local criticalSaved, criticalError = profile:SaveAsync("critical")
if not criticalSaved then warn(criticalError) end
~~~

| Priority | Behavior |
| --- | --- |
| `"normal"` | Can return `true, "DEFERRED"` when the minimum save interval has not elapsed |
| `"high"` | Requests a save without the normal-priority interval deferral |
| `"critical"` | Explicit higher-priority request; still subject to Roblox limits/errors |

The default manual save priority is `"high"`. A clean session may return success without issuing a backend write. Neither a mutation nor a `"DEFERRED"` result means the new state is immediately durable.

### Release and shutdown

~~~lua
local ok, err = profile:ReleaseAsync()
if not ok then warn("Release failed:", err) end

-- Store-wide administration, e.g. a controlled shutdown path:
local flushed, flushError = Store:FlushAsync(20)
if not flushed then warn(flushError) end

-- Attach once during startup; do not routinely CloseAsync in gameplay.
Store:BindToClose()
~~~

A release saves and clears ownership. Failed release or close operations must be monitored; backend failures can leave a lock until expiry/recovery.

### Read without acquiring a session

~~~lua
local data, metadataOrError = Store:PeekAsync(player.UserId)
if data then
    print("Stored coins:", data.Coins)
else
    warn("Peek failed:", metadataOrError)
end
~~~

`PeekAsync` is read-only. Do not use its output to overwrite the live profile owned by another server. It is not a replacement for `OpenPlayerAsync` when you intend to mutate data.

## Schema validation and migrations

### Optional schema rules

The template supplies baseline types. `Schema` adds runtime constraints:

~~~lua
local Store = NexusDataStore.new({
    Name = "PlayerData",
    Template = PlayersData,
    Schema = {
        Coins = {Type = "integer", Min = 0},
        Level = {Type = "integer", Min = 1, Max = 1000},
        Inventory = {Type = "array", ArrayOf = {Type = "string"}},
        Settings = {Type = "table", Children = {
            Music = {Type = "boolean"},
            SFX = {Type = "boolean"},
        }},
    },
    Strict = false,
    ValidateOnWrite = true,
})
~~~

Rules may use `Type`, `Required`, `Optional`, `Min`, `Max`, `MinLength`, `MaxLength`, `Enum`, `ArrayOf`, `Children`, `AllowUnknown`, and `Validate`. Enable `Strict` only when you want unknown root fields rejected.

The example above creates **one alternative store configuration**. Do not instantiate it alongside the original store against the same keys.

### Migrate existing player data

When changing saved structure, increment `SchemaVersion` and supply a migration for each skipped version:

~~~lua
-- First add Prestige = 0 to the PlayersData template.
local Store = NexusDataStore.new({
    Name = "PlayerData",
    Template = PlayersData,
    SchemaVersion = 2,
    Migrations = {
        [2] = function(data, context)
            data.Prestige = data.Prestige or 0
            return data
        end,
    },
})
~~~

On load the library applies missing migrations **in order**, reconciles against the current template, validates, and acquires the session lock. A missing or failing migration produces an error; it does **not** silently reset the player's data. Test migrations against copied test records before using the same store in production.

## Compression and storage options

Compression applies to **standard player records**, not OrderedDataStore numbers.

### Encoding strategy

| Strategy | Work performed | Use case |
| --- | --- | --- |
| `"balanced"` (default) | One codec pass; compare supported transports and raw storage | General-purpose games |
| `"smallest"` | Try dictionary-enabled and disabled packets; compare each transport and raw storage | When serialized byte size is the primary concern |
| `Compression = false` | Write the validated raw record without custom compression | Simpler path; useful for benchmarking |

`CompressionMinBytes` defaults to `512` measured raw bytes; smaller records bypass the custom codec. Set `CompressionMinBytes = 0` to evaluate every record.

~~~lua
-- Size-focused configuration, in the SAME one store constructor:
Compression = true,
CompressionStrategy = "smallest",
CompressionMinBytes = 0,
CompressionTransport = "auto",
CompressionOptions = {
    StringDictionary = true,
    DictionaryMinLength = 4,
    DictionaryMinUses = 2,
    AllowExpansion = false,
},
~~~

**Trade-off:** size-first mode can require twice the codec work, including writes that primarily renew locks. It minimizes the modeled **serialized representation**, not necessarily Roblox's final compressed-at-rest storage or operation latency. Profile data and access patterns determine whether it is worthwhile.

### Transport selection

- `"auto"` measures eligible buffer/Base64 representations and chooses the smaller candidate.
- `"buffer"` only evaluates the direct buffer transport.
- `"base64"` only evaluates the Base64 transport.

The library also evaluates raw storage for fallback according to its size/expansion options. Encoded packets retain codec `230` and checksum checks.

### Opt-in forced buffer storage

When you need every **written standard player record** to use a buffer payload, opt into `ForceCompressedBuffer = true`. The setting overrides the minimum-size threshold and disables the raw-table fallback; it uses the existing codec and record envelope, so the persisted value is still a table containing `Payload = buffer`, **not a naked buffer**.

~~~lua
local Store = NexusDataStore.new({
    Name = "PlayerData",
    Template = PlayersData,
    Compression = true,
    ForceCompressedBuffer = true,
    CompressionStrategy = "smallest",
    CompressionTransport = "buffer",
    CompressionMinBytes = 0,
    CompressionReports = true,
    CompressionOptions = {
        StringDictionary = true,
        DictionaryMinLength = 4,
        DictionaryMinUses = 2,
        AllowExpansion = false,
    },
})
~~~

- Existing raw records and v230 Base64/buffer envelopes remain readable; the next successful write can migrate them to buffer storage.
- Forced mode requires compression enabled and `CompressionTransport` omitted or set to `"buffer"`. Explicit `"auto"`/`"base64"` is rejected to avoid silent behavior changes.
- It **does not guarantee fewer bytes**. Small profiles (for example `{Coins = 0, Collected = 0}`) can grow due to the codec header and storage envelope. Use normal `"smallest"` mode without forcing for actual smallest *measured* persisted records.
- An oversized forced compressed record fails with `STORED_BYTES_EXCEEDED`; it will **not** be silently stored raw. The caller must handle save failures.
- When `CompressionReports = true`, the `CompressionReport` event now includes raw decisions as well as compressed ones. Inspect `PersistedCompressed`, `StorageBytes`, `RawStorageEstimate`, `Transport`, and `SelectionReason`. Possible reasons include `forced-buffer`, `compressed-smaller`, `raw-smaller-or-equal`, `below-minimum-bytes`, `compressed-exceeds-limit`, and `compression-disabled`.
- Do not deploy exclusively buffer-writing servers while any incompatible old readers are in production. Test with copied player records in Roblox Studio before enabling in a live game.

~~~lua
local report, err = Store:GetCompressionReport(PlayersData)
if report then
    print("Stored transport:", report.Transport, "Compressed:", report.PersistedCompressed)
    print("Bytes:", report.RawStorageEstimate, "->", report.StorageBytes)
    print("Reason:", report.SelectionReason)
else
    warn("Compression forecast failed:", err)
end
~~~

`GetCompressionReport` **predicts** the current write selection; it does not read or certify a previously saved record. The Studio-only `tests/ForcedBufferRegression.server.lua` verifies raw/buffer roundtrips and mocked persistence.

### Standalone codec API

`Compression` can also encode supported Luau values outside the persistence API:

~~~lua
local Compression = require(script.Parent.NexusDataStore.Compression)

local original = {Coins = 1000, Inventory = {"Potion", "Potion"}}
local packet, stats = Compression.CompressTablePacket(original, {
    StringDictionary = true,
    DeterministicMaps = true,
})

local decoded = Compression.DecompressTable(packet)
assert(decoded.Coins == original.Coins)
print(stats.RawBytes, stats.EncodedBytes, stats.SavingsPercent)
~~~

Standalone `CompressTablePacket` returns a **buffer**. Do not feed its buffer directly into a player-data field; use the persistence API for profiles.

### Storage reports

~~~lua
local report, err = Store:GetCompressionReport(profile)
if not report then
    warn("Compression report error:", err)
else
    print("Storage bytes:", report.StorageBytes)
    print("Selected transport:", report.Transport)
    print("Compressed:", report.PersistedCompressed)
    print("Compact lock:", report.CompactLock)
end
~~~

These are estimates for a modeled record and do not include exact backend-at-rest storage costs.

### Compact session locks and migration safety

`CompactSessionLocks = true` stores the four lock components as a compact array instead of a named dictionary. The decoder rebuilds the normal in-memory fields (`JobId`, `SessionId`, `HeartbeatAt`, `ExpiresAt`), so session ownership checks remain the same.

> [!WARNING]
> **Default is `false` for cross-version safety.** Older servers cannot decode compact lock arrays. Roll out v7.0.6+ everywhere with the flag off, drain older servers, then turn it on consistently. Before rolling back, rewrite compact locks with v7.0.6 while the option is off and drain active sessions. Do not enable compact locks during a mixed-version deployment.

## OrderedDataStore and leaderboards

Roblox OrderedDataStore values are **numeric**. NexusDataStore exposes ranking and optional sync from the last persisted profile snapshot.

### Automatic leaderboard synchronization

~~~lua
local Store = NexusDataStore.new({
    Name = "PlayerData",
    Template = PlayersData,
    OrderedDataStores = {
        Coins = {
            Name = "PlayerCoinsRank",
            Path = "Coins",
            Mode = "set", -- current saved balance, not lifetime highest
            AutoSync = true,
            Integer = true,
            ClampMin = 0,
        },
        Wins = {
            Name = "PlayerWinsRank",
            Path = {"Stats", "Wins"},
            Mode = "max", -- retain the best score
            AutoSync = true,
            Integer = true,
            ClampMin = 0,
        },
    },
})
~~~

`AutoSync` operates after successful qualifying profile persistence; leaderboard synchronization may fail separately and should be monitored. A leaderboard is not an atomic multi-key transaction with the player profile.

### Manual reads and writes

~~~lua
local ordered, err = Store:GetOrderedStore("Coins")
if not ordered then error(err) end

local wrote, writeResult = ordered:WriteAsync(player.UserId, 1500, "set")
if not wrote then warn(writeResult) end

local fetched, currentOrError = ordered:GetAsync(player.UserId)
if fetched then print(currentOrError) end

local topOK, entriesOrError = ordered:GetTopAsync(10)
if topOK then
    for _, entry in ipairs(entriesOrError) do
        print(entry.Rank, entry.Key, entry.Value)
    end
else
    warn(entriesOrError)
end

local rankOK, rankOrError = ordered:GetRankAsync(player.UserId, false, 5)
if rankOK then print("Rank:", rankOrError.Rank) end
~~~

`GetTopAsync` returns a page of at most 100 entries. `GetRankAsync` may scan several pages and consume ordered-read budget; set an appropriate scan limit.

| Mode | Meaning | Typical use |
| --- | --- | --- |
| `"set"` | Replace the current value | Current currency, current level |
| `"max"` | Keep the larger value | Highest score, lifetime wins |
| `"min"` | Keep the smaller value | Fastest completion time |

Additional methods: `SetAsync`, `UpdateAsync`, `MaxAsync`, `MinAsync`, `IncrementAsync`, `RemoveAsync`, `GetBottomAsync`, `GetPageAsync`, `GetSortedAsync`, and `SyncSessionAsync`.

### Projected leaderboard values

`ToNumber` converts a saved field into one number. `KeyFromSession` can customize the leaderboard key.

~~~lua
OrderedDataStores = {
    Wins = {
        Path = {"Stats", "Wins"},
        Mode = "max",
        AutoSync = true,
        Integer = true,
        ToNumber = function(value)
            return tonumber(value)
        end,
        KeyFromSession = function(profile)
            return profile.UserId or profile.Key
        end,
    },
}
~~~

Set `RemoveWhenNil = true` if a missing projected path should remove the corresponding entry. Use `Round = "nearest"`, `"floor"`, or `"ceil"` and `ClampMin`/`ClampMax` for normalization.

## Configuration reference

The following are the defaults in **v7.3.0**. Every option goes inside `NexusDataStore.new({...})` unless otherwise stated.

### Store identity and data model

| Option | Default | Description |
| --- | --- | --- |
| `Name` | Required | Standard DataStore name |
| `Scope` | `"Global"` | DataStore scope |
| `Template` | Required | Base data shape and Luau type |
| `Schema` | `nil` | Optional validation rules |
| `SchemaVersion` | `1` | Persistent schema version |
| `Migrations` | `{}` | Migration functions keyed by destination version |
| `Strict` | `false` | Reject unknown root fields |
| `Reconcile` | `true` | Refill missing template fields |
| `EnforceTemplateTypes` | `true` | Validate template-compatible shapes |
| `ValidateOnWrite` | `true` | Validate controlled mutations |
| `DetectDirectChanges` | `true` | Detect direct edits to `profile.Data` |
| `ChangeJournalLimit` | `0` | Keep up to 1000 recent in-memory mutation summaries; 0 disables the journal |
| `SkipUnchangedMutations` | `false` | Opt-in suppression of identical controlled mutations and their events |
| `KeyPrefix` | `""` | Prefix for standard-store keys |
| `PlayerKey` | `nil` | Optional custom player-key function |

### Persistence and lifecycle

| Option | Default | Description |
| --- | --- | --- |
| `AutoSave` | `true` | Enable periodic autosaving |
| `AutoSaveInterval` | `30` seconds | Autosave target interval |
| `LockTimeout` | `120` seconds | Lock expiration window |
| `HeartbeatInterval` | Derived | Default approximately one-third of lock timeout, bounded by implementation |
| `RetryAttempts` | `6` | Backend attempts |
| `RetryBaseDelay` | `0.5` seconds | Initial retry backoff |
| `RetryMaxDelay` | `10` seconds | Backoff limit |
| `BudgetAware` | `true` | Wait for adequate request budget |
| `BudgetWaitTimeout` | `10` seconds | Budget wait per attempt |
| `MinimumSaveInterval` | `3` seconds | Normal-priority save throttle |
| `LoadTimeout` | `30` seconds | Load deadline, including opt-in lock waiting |
| `WaitForSessionLock` | `false` | Opt-in retry on `SESSION_LOCKED`; never force-steals |
| `SessionLockRetryInterval` | `2` seconds | Fallback interval between locked-key attempts (0.5–30 seconds) |
| `EnableSessionHandoff` | `false` | Subscribe/publish safe targeted handoff messages; also enables lock waiting |
| `SessionHandoffCooldown` | `6` seconds | Minimum spacing of requests per waiting load (1–60 seconds) |
| `SaveTimeout` | `30` seconds | Save deadline |
| `AutoPlayerLifecycle` | `false` | Attach join/leave management in constructor |

### Compression and limits

| Option | Default | Description |
| --- | --- | --- |
| `Compression` | `true` | Enable custom compressed/raw selection; compact packets remain opt-in |
| `CompressionModule` | Auto-resolved | Override codec ModuleScript |
| `CompressionOptions` | `{}` | Codec-specific options |
| `CompressionStrategy` | `"balanced"` | `"balanced"` or `"smallest"` for adaptive selection |\n| `CompressionPolicy` | `"adaptive"` | `"always-smallest"` always persists a compressed packet chosen from four variants |
| `CompressionMinBytes` | `512` | Compression threshold (ignored for forced buffer writes) |
| `ForceCompressedBuffer` | `false` | Opt-in mandatory compressed buffer envelope; may increase bytes |
| `CompressionTransport` | `"auto"` | `"auto"` / `"buffer"` / `"base64"` |
| `CompactSessionLocks` | `false` | Opt-in compact lock representation |
| `CompressionReports` | `false` | Emit compression-selection events for compressed and raw writes |
| `MaxDataNodes` | `50000` | Data node limit |
| `MaxDataBytes` | `3900000` | Approximate raw data limit |
| `MaxStoredBytes` | `3900000` | Measured final storage limit |
| `MaxDepth` | `64` | Table-depth limit |
| `MaxSnapshots` | `10` | Snapshots retained per session |

### Integration and diagnostics

| Option | Default | Description |
| --- | --- | --- |
| `OrderedDataStores` | `{}` | Ordered leaderboard configurations |
| `EnableCrossServerEvents` | `false` | Publish/subscribe optional general MessagingService events; handoff works independently |
| `CrossServerTopic` | Derived | MessagingService topic |
| `Debug` | `false` | Debug logging |
| `ProfileOperations` | `false` | Opt-in per-server operation time/count profiling |

The codec's `CompressionOptions` include opt-in `CompactEncoding` (v231), `BitPackedIntegers` (v232), and `RunLengthArrays` (v233), all disabled by default, `StringDictionary`, `DictionaryMinLength`, `DictionaryMinUses`, `DictionaryMaxEntries`, `DictionaryMaxCandidates`, `DeterministicMaps`, `MaxDepth`, `MaxNodes`, `PreallocateLimit`, and `AllowExpansion`. Tune only with representative profile benchmarks.

## API reference

### Store methods

| Method | Purpose |
| --- | --- |
| `OpenPlayerAsync(player)` / `OpenAsync(key, context?)` | Load and acquire session |
| `GetSession(playerOrKey)` / `WaitForSession(playerOrKey, timeout?)` | Find/wait for active local session |
| `PeekAsync(key)` | Read saved data without acquiring ownership |
| `SaveAsync(profile, priority?)` / `ReleaseAsync(profile)` | Persist/release |
| `FlushAsync(timeout?)` / `ReleaseAllAsync()` / `CloseAsync(timeout?)` | Bulk persistence and shutdown |
| `AttachPlayerLifecycle()` / `BindToClose()` | Player events and server shutdown |
| `Validate(data)` / `GetTemplate()` / `GetSchema()` | Data validation and schema |
| `PreviewMigration(data, fromVersion, key?)` | Non-persisting migration and reconcile preview with diff |
| `GetStorageForecast(dataOrSession, warningRatio?)` | Current-format stored-byte estimate and limit warnings |
| `EncodeCompressed(data)` / `DecodeCompressed(buffer)` | Codec convenience methods |
| `GetCompressionReport(dataOrProfile)` | Modeled compression report |
| `GetOrderedStore(alias)` / `SyncOrderedAsync(profile, alias?)` / `SyncAllOrderedAsync(alias?)` | Leaderboard access/synchronization |
| `GetMetrics()` / `GetHealth()` / `GetVersion()` / `GetPerformanceReport()` | Operational diagnostics and opt-in timing report |
| `On(name, callback)` / `Once(name, callback)` | Event subscriptions |

### Profile methods

| Category | Methods |
| --- | --- |
| Read | `Get`, `GetOr`, `Has`, `GetDataSnapshot` |
| Write | `Set`, `SetDefault`, `Delete`, `Patch`, `UpdatePath`, `Mutate` |
| Counters | `Increment`, `IncrementClamped`, `Award`, `Spend` |
| Containers | `Append`, `RemoveAt`, `Toggle` |
| History | `Snapshot`, `Restore`, `DiffFromPersisted`, `GetChangeJournal`, `ClearChangeJournal` |
| Observability | `Watch`, `GetStatus`, `GetStats`, `IsDirty`, `IsActive` |
| Persistence | `SaveAsync`, `ReleaseAsync` |

#### Defaults and detached reads

| Method | Returns | Behavior |
| --- | --- | --- |
| `SetDefault(path, value)` | `true, value, inserted` or `false, error` | Inserts only when the path's value is nil; existing false and zero are preserved. Tables returned to the caller are independent copies. |
| `GetDataSnapshot()` | Independent data table | Copies the whole profile without marking it dirty, firing change events, or consuming a retained restore slot. |

`SetDefault` requires an active, non-releasing session. Missing fields require a non-nil default; invalid paths, circular defaults, invalid parents, and validation failures are rejected. Existing values are returned without applying the fallback or incrementing the mutation counter. A successful insertion changes local session data; autosave or `SaveAsync` performs persistence.

~~~lua
local ok, value, inserted = profile:SetDefault({"Settings", "Music"}, true)
if not ok then
    warn("Default failed:", value)
elseif inserted then
    print("Initialized music setting:", value)
end

local displayData = profile:GetDataSnapshot()
displayData.Coins = 0 -- does not modify profile.Data.Coins
~~~

The parent `Settings` table must already exist for this nested-path example. Use `Snapshot(label)` when you need an owned token for `Restore`; `GetDataSnapshot()` is only a read helper.

`Mutate` commits a detached copy of its callback draft. Retaining that draft or returning one of its nested tables cannot change committed data afterward. Successful transactions incur an additional whole-profile copy; prefer path setters for frequent small changes. `UpdatePath` captures its path before running the callback, so later edits to the caller's path array cannot redirect the write. Both methods recheck session activity after callbacks, including cancellation and no-op paths.

The library also exports `Data`, `Profile`, `PlayerProfile`, `PlayerStore`, and the generic `Session<T>`/`Store<T>` type aliases for strict Luau.

## Events, errors, and diagnostics

### Subscribe to events

~~~lua
Store:On("Opened", function(profile)
    print("Loaded", profile.Key)
end)

Store:On("Saved", function(profile, priority, releasing)
    print("Saved", profile.Key, priority, releasing)
end)

Store:On("OrderedSyncFailed", function(profile, reason)
    warn("Leaderboard sync failed", profile.Key, reason)
end)
~~~

Common event names include `Opened`, `Saved`, `Released`, `Changed`, `SessionLockWait`, `SessionHandoffWake`, `SessionHandoffError`, `SessionLost`, `PlayerLoadFailed`, `PlayerReleaseFailed`, `AutoSaveFailed`, `HeartbeatFailed`, `CompressionReport`, `OrderedSyncCompleted`, `OrderedSyncFailed`, `CloseFailed`, and `Closed`.

### Inspect health and metrics

~~~lua
local metrics = Store:GetMetrics()
local health = Store:GetHealth()

print("Active sessions:", metrics.ActiveSessions)
print("Failed saves:", metrics.SaveFailed)
print("Average save time:", metrics.AverageSaveTime)
print("Library version:", health.Version)
print("Compression engine:", health.CompressionVersion)
~~~

Metrics describe this **server process** and are not a permanent analytics warehouse. `ChangeJournalLimit` stores debug summaries in server memory only and does not affect record encoding or the persistent data schema.

### What to do with an error

| Result | Meaning / response |
| --- | --- |
| `SESSION_LOCKED` | Another session appears to own the profile; do not overwrite it |
| `SESSION_LOCK_WAIT_TIMEOUT` | Opt-in lock waiting exhausted the configured load deadline |
| `SESSION_CONTEXT_CONFLICT` | A different Player/UserId tried to reuse a locally active key |
| `PLAYER_LEFT` | Player departed while waiting to acquire a locked session |
| `SESSION_LOST` / `REVISION_CONFLICT` | Ownership or revision changed; stop modifying that session |
| `LOAD_VALIDATION_FAILED` / `SAVE_VALIDATION_FAILED` | Data failed validation; inspect field types/limits |
| `MIGRATION_MISSING` / `MIGRATION_FAILED` | Missing/broken migration; repair code, do not reset data |
| `SNAPSHOT_NOT_OWNED` | A snapshot belongs to another session or has been evicted; choose a retained snapshot |
| `INVALID_PATH` | A path is empty, sparse, or otherwise invalid; use a dense key array |
| `COMPRESSED_DECODE_FAILED` / `INVALID_COMPRESSED_ENVELOPE` | Record could not be decoded; preserve stored data for investigation |
| `DEFERRED` | Normal save was postponed, **not** durably confirmed |
| `SAVE_TIMEOUT` / `LOAD_TIMEOUT` | Backend deadline exceeded; treat persistence as uncertain |
| `OPEN_IN_FLIGHT_TIMEOUT` | Closing could not wait for all outstanding loads; handle failed close |

These are examples, not the complete error-code list. Check returned values and subscribe to lifecycle/error events.

## Production guidance

1. **Protect saved data.** Never replace corrupted, incompatible, or locked profiles with new template data.
2. **Own the server boundary.** Clients may request actions, but the server decides rewards, prices, and inventory changes.
3. **Avoid duplicate store instances** using the same keys in one running server. Share a single `DataService` module.
4. **Validate all changes.** Favor controlled profile APIs rather than unsignaled direct edits.
5. **Manage budgets.** Large profiles, frequent critical saves, heartbeats, and rank scans can increase DataStore usage.
6. **Limit data growth.** Cap inventory length, dynamic map keys, string lengths, and total record size.
7. **Roll out migrations safely.** Use test universes and copied records; keep `SchemaVersion` changes deliberate.
8. **Roll out compact locks in stages.** Keep them disabled while any older reader is active.
9. **Handle shutdown failures.** A successful `BindToClose` callback cannot guarantee persistence during abnormal server termination.
10. **Measure compression.** Compare compression-on/off, balanced/smallest, and forced buffer mode using real profile sizes, CPU use, and observed save latency.

## Testing and troubleshooting

> **v7.5.0 validation status:** This release adds a Studio-only mock two-server test. A passing compile or static check does not establish live Roblox server handoff reliability. The historical v7.3.0 results below remain version-specific.

The [`tests/` directory](./tests) includes [SessionHandoffRegression.server.lua](./tests/SessionHandoffRegression.server.lua) for two-server mocked messaging and expired-lock recovery, plus [SessionLockWaitRegression.server.lua](./tests/SessionLockWaitRegression.server.lua) for bounded lock contention and shutdown tests, along with [DeveloperToolsRegression.server.lua](./tests/DeveloperToolsRegression.server.lua) for migration previews, storage forecasts, and bounded journals, plus Roblox Studio regression scripts for codec correctness, malformed payloads, copy-on-write isolation, **zero-change suppression, coalesced saves and profiling** (see [EfficiencyRegression.server.lua](./tests/EfficiencyRegression.server.lua)), compact locks, ambiguous acknowledgements, and load/close races. Place test Scripts with the required ModuleScripts as directed by their headers; do **not** run them against production player keys.

### Recorded v7.3.0 validation

| Check | Recorded result |
| --- | --- |
| Portable session regressions | 17 passed, including a 10,000-operation mixed-operation sequence |
| Compression regressions | 22 passed |
| Static compatibility checks | 33 passed |
| Luau compilation | All root modules and regression/benchmark scripts compiled |
| Independent code review | No blocking regression found |

These are the local results for the v7.3.0 implementation, not a live production certification. See the [validation report](./docs/VALIDATION-7.3.0.md) for exact scope and the [GitHub Actions runs](https://github.com/SillyDev2026/NexusDataStore/actions/workflows/source-compatibility.yml) for current CI status.

### Portable behavioral checks

With the official Luau CLI installed:

```sh
python3 tools/verify_release.py
python3 tools/run_behavioral_tests.py --luau /path/to/luau
```

The portable runner executes real module methods with minimal service stubs and the existing compression regression script. It does not emulate Roblox scheduling, DataStore budgets, server shutdown, or network persistence. Run the included `.server.lua` suites in Studio for those paths. CLI compilation checks syntax, not Roblox-aware strict type analysis.

### One-million-iteration performance and correctness suites

These scripts are **executable Studio test harnesses**, not benchmark results. The new efficiency features have their own focused regression and must also be run in Studio. For every selected case, the script attempts `1_000_000` iterations, checking each result and printing actual microseconds per iteration:

| Script | Coverage | Backend |
| --- | --- | --- |
| [MillionLocalBenchmark.server.lua](./tests/MillionLocalBenchmark.server.lua) | Profile reads/writes, counters, transactions, snapshots, validation, compression, watcher APIs | Fabricated in-memory session |
| [MillionMockBackendBenchmark.server.lua](./tests/MillionMockBackendBenchmark.server.lua) | Open/release, persistence, OrderedDataStore reads, writes, ranking and synchronization | In-memory mocked DataStores |

To run: create a server **Script** beside the `DataStore` and `Compression` ModuleScripts (with `PlayersData` under `DataStore`), copy one benchmark file into that Script, and run in Roblox Studio. At the top of the script, set:

~~~lua
local ITERATIONS = 1_000_000
local BATCH_SIZE = 1000
local SUITE = "Set" -- or "all"; backend suite uses names such as "OrderedGetAsync"
~~~

- Select an individual case first. Running `"all"` requests tens of millions of iterations and can be slow even with batches/yields.
- The local `Append+RemoveAt` case calls **both** methods once per iteration and reports combined time.
- CPU timings exclude batch yields, but include correctness assertions. Compare against the **same** profile shape, Studio/device and options on the previous release before claiming a speedup.
- The mocked suite exercises actual library methods with fake backend instances. It does **not** issue one million Roblox DataStore requests, exercise cross-server contention, or establish real-world latency/budget safety.
- Some lifecycle operations need live Player objects and real servers, and are **not** eligible for million-call local benchmarks. Test them with targeted integration scenarios instead.
- Record measured counts, completion/errors, allocation behavior and CPU timings; only treat a suite as passed if its `PASS`/summary output appears without assertion errors.

Suggested pre-release test matrix:

| Scenario | Expected outcome |
| --- | --- |
| New player joins | Template-based profile opens and saves |
| Existing player rejoins | Previously saved progression loads |
| Two servers open one key | Only an authorized session proceeds |
| Session owner crashes | Expiration/recovery behavior is safe |
| Save succeeds but acknowledgement fails | Uncached verification handles the ambiguity |
| Release during in-flight load | Session is not silently stranded |
| Schema is upgraded | Migration runs before validation |
| Compressed payload is corrupted | Decoder reports failure, never resets data |
| Normal and compact locks | v7.3.0 can read both |
| Leaderboard sync fails | Standard profile save and ordered error are handled separately |

For DataStore fundamentals and limits, consult [Roblox Data Stores](https://create.roblox.com/docs/cloud-services/data-stores), [best practices](https://create.roblox.com/docs/cloud-services/data-stores/best-practices), and [error codes and limits](https://create.roblox.com/docs/cloud-services/data-stores/error-codes-and-limits).

---

**Version 7.9.0** · [Source](./DataStore.lua) · [Compression](./Compression.lua) · [Tests](./tests)
