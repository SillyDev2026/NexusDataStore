# NexusDataStore

**Typed, session-aware data persistence for Roblox.**

![Version](https://img.shields.io/badge/NexusDataStore-7.1.0-2563eb)
![Codec](https://img.shields.io/badge/Compression-2.3.4-0f766e)
![Luau](https://img.shields.io/badge/language-Luau-00a2ff)
![Platform](https://img.shields.io/badge/platform-Roblox-222222)

NexusDataStore brings standard Roblox DataStore persistence, session ownership, typed player profiles, validation, migrations, snapshots, adaptive compression, and numeric leaderboards into one server-side library.

**Current version:** `7.1.0` · **Compression:** `2.3.4` / codec `230` · **Record format:** `700`

> [!IMPORTANT]
> This documentation describes the current source on `main`. Regression scripts are included, but production reliability and performance have not been certified by live-server load testing. Use a separate test universe before deploying changes to existing player data.

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

### Efficiency and observability — v7.1.0

This release builds on path-level copy-on-write with three targeted improvements: optional zero-change suppression, duplicate-save coalescing, and opt-in performance diagnostics. It preserves the existing API, strict Luau profile types, record format `700`, and Compression `2.3.4` / codec `230`. No saved-data migration is required.

- **Path-level copy-on-write:** `Set`, `Delete`, `Append`, `RemoveAt`, and multi-field `Patch` copy only affected table branches before validating and committing, rather than deep-cloning unrelated profile trees for each edit.
- **Incremental direct-change baseline:** Controlled path mutations update their independent observation snapshot by path when possible. Whole-profile changes and uncertain paths retain the full-clone fallback.
- **Same data semantics:** Session locks, validation, migrations, compression, OrderedDataStore interfaces, snapshot ownership, and saved keys remain unchanged.
- **Type checking:** The DataStore module now declares `--!strict` while retaining its `PlayersData.Data`, `Store<T>`, and `Session<T>` APIs. Run Roblox Studio Script Analysis; adding a directive does not constitute a completed analyzer run.
- **Expanded regression suite:** `CopyOnWriteRegression.server.lua` checks nested paths, old-reference isolation, watchers, rollback, and full-record validation with direct-change detection enabled and disabled.
- **One-million-call test harnesses:** `MillionLocalBenchmark.server.lua` and `MillionMockBackendBenchmark.server.lua` provide 1,000,000 iterations per selected case and show observed timings in Studio. They are not recorded benchmark results.

> **Required verification:** The new regression and million-iteration scripts require Roblox Studio. No Luau runtime, actual one-million-call run, benchmark speedup, or live DataStore reliability result is claimed by these source changes. Run the relevant suites, compare before/after timings, and test real cross-server ownership before production rollout.

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
- Place `Compression` beneath `NexusDataStore`, next to it, or provide it through `CompressionModule`. The required codec is `230` from the `2.3.x` series.
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

The library handles `PlayerAdded`, `PlayerRemoving`, and players already connected when attachment begins. The server must still call `Store:BindToClose()` (or handle shutdown explicitly).

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

The following are the defaults in **v7.1.0**. Every option goes inside `NexusDataStore.new({...})` unless otherwise stated.

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
| `LoadTimeout` | `30` seconds | Load deadline |
| `SaveTimeout` | `30` seconds | Save deadline |
| `AutoPlayerLifecycle` | `false` | Attach join/leave management in constructor |

### Compression and limits

| Option | Default | Description |
| --- | --- | --- |
| `Compression` | `true` | Enable custom compressed/raw selection |
| `CompressionModule` | Auto-resolved | Override codec ModuleScript |
| `CompressionOptions` | `{}` | Codec-specific options |
| `CompressionStrategy` | `"balanced"` | `"balanced"` or `"smallest"` |
| `CompressionMinBytes` | `512` | Compression threshold |
| `CompressionTransport` | `"auto"` | `"auto"` / `"buffer"` / `"base64"` |
| `CompactSessionLocks` | `false` | Opt-in compact lock representation |
| `CompressionReports` | `false` | Emit compression-report events |
| `MaxDataNodes` | `50000` | Data node limit |
| `MaxDataBytes` | `3900000` | Approximate raw data limit |
| `MaxStoredBytes` | `3900000` | Measured final storage limit |
| `MaxDepth` | `64` | Table-depth limit |
| `MaxSnapshots` | `10` | Snapshots retained per session |

### Integration and diagnostics

| Option | Default | Description |
| --- | --- | --- |
| `OrderedDataStores` | `{}` | Ordered leaderboard configurations |
| `EnableCrossServerEvents` | `false` | Publish/subscribe optional MessagingService events |
| `CrossServerTopic` | Derived | MessagingService topic |
| `Debug` | `false` | Debug logging |
| `ProfileOperations` | `false` | Opt-in per-server operation time/count profiling |

The codec's `CompressionOptions` include `StringDictionary`, `DictionaryMinLength`, `DictionaryMinUses`, `DictionaryMaxEntries`, `DictionaryMaxCandidates`, `DeterministicMaps`, `MaxDepth`, `MaxNodes`, `PreallocateLimit`, and `AllowExpansion`. Tune only with representative profile benchmarks.

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
| `EncodeCompressed(data)` / `DecodeCompressed(buffer)` | Codec convenience methods |
| `GetCompressionReport(dataOrProfile)` | Modeled compression report |
| `GetOrderedStore(alias)` / `SyncOrderedAsync(profile, alias?)` / `SyncAllOrderedAsync(alias?)` | Leaderboard access/synchronization |
| `GetMetrics()` / `GetHealth()` / `GetVersion()` / `GetPerformanceReport()` | Operational diagnostics and opt-in timing report |
| `On(name, callback)` / `Once(name, callback)` | Event subscriptions |

### Profile methods

| Category | Methods |
| --- | --- |
| Read | `Get`, `GetOr`, `Has` |
| Write | `Set`, `Delete`, `Patch`, `UpdatePath`, `Mutate` |
| Counters | `Increment`, `IncrementClamped`, `Award`, `Spend` |
| Containers | `Append`, `RemoveAt`, `Toggle` |
| History | `Snapshot`, `Restore`, `DiffFromPersisted` |
| Observability | `Watch`, `GetStatus`, `GetStats`, `IsDirty`, `IsActive` |
| Persistence | `SaveAsync`, `ReleaseAsync` |

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

Common event names include `Opened`, `Saved`, `Released`, `Changed`, `SessionLost`, `PlayerLoadFailed`, `PlayerReleaseFailed`, `AutoSaveFailed`, `HeartbeatFailed`, `CompressionReport`, `OrderedSyncCompleted`, `OrderedSyncFailed`, `CloseFailed`, and `Closed`.

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

Metrics describe this **server process** and are not a permanent analytics warehouse.

### What to do with an error

| Result | Meaning / response |
| --- | --- |
| `SESSION_LOCKED` | Another session appears to own the profile; do not overwrite it |
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
10. **Measure compression.** Compare compression-on/off and balanced/smallest using real profile sizes, CPU use, and observed save latency.

## Testing and troubleshooting

The [`tests/` directory](./tests) contains Roblox Studio regression scripts for codec correctness, malformed payloads, copy-on-write isolation, **zero-change suppression, coalesced saves and profiling** (see [EfficiencyRegression.server.lua](./tests/EfficiencyRegression.server.lua)), compact locks, ambiguous acknowledgements, and load/close races. Place test Scripts with the required ModuleScripts as directed by their headers; do **not** run them against production player keys.

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
| Normal and compact locks | v7.1.0 can read both |
| Leaderboard sync fails | Standard profile save and ordered error are handled separately |

For DataStore fundamentals and limits, consult [Roblox Data Stores](https://create.roblox.com/docs/cloud-services/data-stores), [best practices](https://create.roblox.com/docs/cloud-services/data-stores/best-practices), and [error codes and limits](https://create.roblox.com/docs/cloud-services/data-stores/error-codes-and-limits).

---

**Version 7.1.0** · [Source](./DataStore.lua) · [Compression](./Compression.lua) · [Tests](./tests)
