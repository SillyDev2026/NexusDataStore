# NexusDataStore

**Typed, session-aware Roblox DataStore persistence.** Written for server-side Luau with profile locks, safe updates, migration support, compression, ordered leaderboards, and restart integration.

![Version](https://img.shields.io/badge/NexusDataStore-8.5.0-2563eb)
![Compression](https://img.shields.io/badge/Compression-2.6.1-0f766e)
![Luau](https://img.shields.io/badge/Luau-strict-00a2ff)
![Roblox](https://img.shields.io/badge/Roblox-server--side-222222)

**Current version:** `8.5.0` · **Record format:** `700` · **Compression:** `2.6.1` (codecs `230`–`233`).

> [!IMPORTANT]
> This project has automated source checks and portable Luau behavioral tests, but those are not a substitute for Roblox Studio and published-server tests. **Use a test universe and test keys before rolling changes out to existing player records.**

## Contents

1. [Install and quick start](#install-and-quick-start)
2. [Player lifecycle and reliable saves](#player-lifecycle-and-reliable-saves)
3. [Complete profile API examples](#complete-profile-api-examples)
4. [Complete store API examples](#complete-store-api-examples)
5. [Ordered leaderboards](#ordered-leaderboards)
6. [Compression and record size](#compression-and-record-size)
7. [Schemas and migrations](#schemas-and-migrations)
8. [Restart and cross-server handoff](#restart-and-cross-server-handoff)
9. [Configuration reference](#configuration-reference)
10. [API reference](#api-reference)
11. [Testing and troubleshooting](#testing-and-troubleshooting)

## New in 8.5.0

- `profile:TryGet("Coins")` returns `true, value` or `false, error` without throwing for invalid read paths. Read tables are detached.
- `Store:WaitForSession(player, timeout)` handles zero-second timeouts, closing stores, invalid keys, and departed players more precisely.
- Save/open retry paths clear attempt-local errors; verified writes with lost acknowledgments are not rejected solely because of stale error state.
- `profile:GetStatus()` exposes `CommitBusy`, `Releasing`, `SavePending`, `HeartbeatPending`, `LastHeartbeatAge`, and `NextAutoSaveIn`.
- The optional restart UI uses server-synchronized time, can connect to RemoteEvents created after 30 seconds, and exposes status attributes.
- The persisted record format, compression codec versions, and existing DataStore keys are unchanged.

**Prior release notes:** [archived README and v7–v8 history](docs/README-HISTORY-v8.5.md). **Release validation:** [v8.5.0 checks and deployment notes](docs/8.5.0-validation.md).

## Install and quick start

### 1. Roblox Studio layout

Create this structure in **ServerScriptService**:

~~~text
ServerScriptService
└── Data
    ├── NexusDataStore                  ModuleScript: paste DataStore.lua
    │   ├── PlayersData                 ModuleScript: your template
    │   └── Compression                 ModuleScript: paste Compression.lua
    ├── DataService                     ModuleScript: create one shared Store
    └── DataBootstrap                   Script: attach lifecycle
~~~

`PlayersData` must be a **direct child** of `NexusDataStore`, because the library uses `require(script.PlayersData)`. A `Compression` ModuleScript must be resolvable or provided via `CompressionModule`. Do **not** place the server DataStore service in ReplicatedStorage for clients.

To persist data in Studio, publish your experience and enable **Studio Access to API Services** only in a safe test experience under **Game Settings > Security**. Do not test against production user keys.

### 2. PlayersData (typed default template)

Paste into `Data/NexusDataStore/PlayersData`:

~~~lua
--!strict
local PlayersData = {
    Coins = 0,
    Gems = 0,
    Level = 1,
    Experience = 0,
    Rebirths = 0,
    Inventory = {} :: {string},
    Upgrades = {} :: {[string]: number},
    Settings = {Music = true, SFX = true},
    Stats = {Wins = 0, TotalClicks = 0},
}
export type Data = typeof(PlayersData)
return PlayersData
~~~

The template defines the Luau `Data` type. Reconciliation fills missing template fields. Changing the meaning of old fields may require a schema migration (see below). Keep values serializable.

### 3. DataService (one shared Store per logical data set)

Paste into `Data/DataService`:

~~~lua
--!strict
local NexusDataStore = require(script.Parent.NexusDataStore)
local PlayersData = require(script.Parent.NexusDataStore.PlayersData)

local Store = NexusDataStore.new({
    Name = "PlayerData",
    Template = PlayersData,
    Compression = true,
    CompressionStrategy = "balanced",
    CompressionPolicy = "adaptive",
    CompressionTransport = "auto",
    CompactSessionLocks = false,
    AutoSave = true,
    AutoSaveInterval = 30,
    MinimumSaveInterval = 3,
    BudgetAware = true,
    RetryAttempts = 6,
    LoadTimeout = 60,
    SaveTimeout = 30,
    WaitForSessionLock = true,
    SessionLockRetryInterval = 2,
    Reconcile = true,
    ValidateOnWrite = true,
    EnforceTemplateTypes = true,
    DetectDirectChanges = true,
    SkipUnchangedMutations = true,
})

return Store
~~~

`CompressionPolicy = "adaptive"` lets the store select raw storage when compressing would be worse. The minimum save interval applies to normal-priority manual saves, not the act of modifying an in-memory profile. This configuration is a starting point, not a guarantee of minimal bytes or successful writes during an outage.

### 4. DataBootstrap (register listeners before attaching)

Paste into `Data/DataBootstrap`:

~~~lua
--!strict
local Players = game:GetService("Players")
local Store = require(script.Parent.DataService)

Store:On("PlayerLoadFailed", function(player, err)
    warn("[Nexus] Load failed:", player.UserId, err)
    if player.Parent == Players then
        player:Kick("Unable to load your data. Please rejoin.")
    end
end)

Store:On("SessionLost", function(profile, reason)
    warn("[Nexus] Session lost:", profile.Key, reason)
    if profile.Player and profile.Player.Parent == Players then
        profile.Player:Kick("Your data session was lost. Please rejoin.")
    end
end)

Store:On("PlayerReleaseFailed", function(player, err)
    warn("[Nexus] Final release failed:", player.UserId, err)
end)

Store:AttachPlayerLifecycle()
Store:BindToClose()
~~~

Do not also write your own `PlayerAdded` / `PlayerRemoving` loader when using `AttachPlayerLifecycle()`. An alternative is `AutoPlayerLifecycle = true` **in the constructor instead of** manually attaching; still call `Store:BindToClose()`. The service is cached per Luau environment, so require the same `DataService` from other server Scripts.

### 5. Give coins from a server Script

~~~lua
--!strict
local ServerScriptService = game:GetService("ServerScriptService")
local Store = require(ServerScriptService.Data.DataService)

local function awardCoins(player: Player, amount: number)
    if amount <= 0 or amount > 1000 then return false, "INVALID_REWARD" end
    local profile, err = Store:WaitForSession(player, 10)
    if not profile then return false, err end
    return profile:Award("Coins", amount)
end

-- Call awardCoins(player, serverCalculatedAmount) only after verifying the reward.
~~~

All rewards, costs, cooldowns, inventory permissions, and purchases must be validated **on the server**. Never trust a client-supplied currency amount.

## Player lifecycle and reliable saves

The lifecycle is **join → acquire exclusive session → read/mutate in memory → autosave → release lock on leave**.

- `OpenPlayerAsync` acquires a lock and either decodes an existing record or creates a new template record.
- `WaitForSession` waits for an **already locally opened** profile; it does not open a new one.
- A successful mutation changes server memory and marks the profile dirty; it **does not** immediately confirm a remote DataStore write.
- An explicit `SaveAsync("normal")` may return `true, "DEFERRED"`. This means the write was deferred, **not** durably committed.
- `SaveAsync("high")` or `SaveAsync("critical")` attempts a save without the normal-priority interval deferral. All writes remain subject to Roblox budgets, deadlines and failures.
- `ReleaseAsync` saves and clears ownership. Do not continue using that session after release.
- Session locks and revision fencing reduce concurrent-server conflicts; **they do not guarantee persistence during outages**.

### Manual lifecycle (alternative to the automatic loader)

Only use this if `Store:AttachPlayerLifecycle()` and `AutoPlayerLifecycle = true` are **not** in use:

~~~lua
local Players = game:GetService("Players")
local Store = require(script.Parent.DataService)

local function load(player: Player)
    local profile, err = Store:OpenPlayerAsync(player)
    if not profile then
        warn("Load failed:", err)
        if player.Parent == Players then player:Kick("Data unavailable; rejoin.") end
        return
    end
    if player.Parent ~= Players then
        local ok, releaseErr = profile:ReleaseAsync()
        if not ok then warn("Late release failed:", releaseErr) end
        return
    end
    print("Loaded profile:", player.UserId, profile:Get("Coins"))
end

Players.PlayerAdded:Connect(function(player) task.spawn(load, player) end)
for _, player in ipairs(Players:GetPlayers()) do task.spawn(load, player) end
Players.PlayerRemoving:Connect(function(player)
    local profile = Store:GetSession(player)
    if not profile then return end
    local ok, err = profile:ReleaseAsync()
    if not ok then warn("Release failed:", err) end
end)

Store:BindToClose()
~~~

### Client RemoteEvent: validate, never directly save client input

Example server Script with a RemoteEvent named `RequestClick` inside ReplicatedStorage:

~~~lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Store = require(ServerScriptService.Data.DataService)
local RequestClick = ReplicatedStorage:WaitForChild("RequestClick") :: RemoteEvent
local lastClick: {[Player]: number} = {}

RequestClick.OnServerEvent:Connect(function(player: Player)
    local current = os.clock()
    if current - (lastClick[player] or 0) < 0.1 then return end
    lastClick[player] = current
    local profile = Store:GetSession(player)
    if not profile or not profile:IsActive() then return end
    local ok, result = profile:Award("Coins", 1)
    if not ok then warn("Reward rejected:", result) end
end)

game:GetService("Players").PlayerRemoving:Connect(function(player)
    lastClick[player] = nil
end)
~~~

This is a basic server-side rate limit, **not** a general anti-exploit system. For valuable rewards, verify the underlying gameplay action too. Do not call `SaveAsync` on every click.

## Complete profile API examples

Assume `profile` is an active session returned by `Store:WaitForSession(player, 10)`, and the template above is used. **Examples are independent**, not intended to run sequentially on one player's real data.

### Read, inspect, and defaults

~~~lua
local active = profile:IsActive()
local dirty = profile:IsDirty()
local coins = profile:Get("Coins")
local level = profile:GetOr("Level", 1)
local hasInventory = profile:Has("Inventory")
local music = profile:Get({"Settings", "Music"})

local ok, valueOrError = profile:TryGet("Coins")
if ok then print("Coins:", valueOrError) else warn(valueOrError) end

local snapshotForUI = profile:GetDataSnapshot()
snapshotForUI.Coins = -1 -- Does not change the live session.

local defaultOK, defaultValue, inserted = profile:SetDefault("Coins", 0)
if not defaultOK then warn("SetDefault:", defaultValue) end
print(active, dirty, coins, level, hasInventory, music, inserted)
~~~

`TryGet` returns `true, nil` for a valid missing field; invalid paths return `false, error`. All returned tables are copies. `GetDataSnapshot()` **does not** create a restorable snapshot; use `Snapshot()` for that.

### Set, delete, patch, and nested paths

~~~lua
local setOK, setErr = profile:Set("Gems", 100)
local nestedOK, nestedErr = profile:Set({"Settings", "Music"}, false)
local patchOK, patchErr = profile:Patch({
    {Path = "Level", Value = 5},
    {Path = {"Stats", "Wins"}, Value = 10},
})
local deleteOK, deleteErr = profile:Delete("Gems")
if not setOK then warn(setErr) end
if not nestedOK then warn(nestedErr) end
if not patchOK then warn(patchErr) end
if not deleteOK then warn(deleteErr) end
~~~

Nested paths are arrays like `{"Stats", "Wins"}`, **not** dotted strings such as `"Stats.Wins"`. Deleting a template-backed field may cause reconciliation to recreate it next time the profile loads.

### Currency, counters, toggles, lists

~~~lua
local ok1, nextCoins = profile:Increment("Coins", 5)
local ok2, nextLevel = profile:IncrementClamped("Level", 1, 1, 100)
local ok3, reward = profile:Award("Coins", 250)
local ok4, remainder = profile:Spend("Coins", 50)
local ok5, musicEnabled = profile:Toggle({"Settings", "Music"})
local ok6, inventorySize = profile:Append("Inventory", "Potion")
local ok7, removedItem = profile:RemoveAt("Inventory", 1)

if not ok1 then warn(nextCoins) end
if not ok2 then warn(nextLevel) end
if not ok3 then warn(reward) end
if not ok4 then warn(remainder) end
if not ok5 then warn(musicEnabled) end
if not ok6 then warn(inventorySize) end
if not ok7 then warn(removedItem) end
~~~

`Spend` checks the balance and rejects insufficient funds. It does not validate whether the player should be allowed to purchase the requested item; that decision belongs in your server code.

### Atomic in-memory purchases with Mutate

~~~lua
local ok, result, status = profile:Mutate(function(data)
    if data.Coins < 500 then return false end
    data.Coins -= 500
    table.insert(data.Inventory, "GoldenSword")
    return "PURCHASED"
end)

if not ok then
    warn("Transaction failed:", result)
elseif status == "CANCELLED" then
    print("Not enough coins")
else
    print(result)
end
~~~

This applies related field changes as **one validated in-memory transaction**, not a transaction across multiple DataStore keys. A `Mutate` callback can yield, but must not overwrite concurrent changes; the library rejects conflicts. Prefer simple path operations for high-frequency updates.

### UpdatePath (one transformed value)

~~~lua
local ok, nextValue = profile:UpdatePath({"Upgrades", "Speed"}, function(oldValue)
    return (oldValue or 0) + 1
end)
if not ok then warn(nextValue) end
~~~

Return `nil` from the callback to cancel the change. A conflicting callback-time mutation is rejected instead of blindly overwriting newer state.

### Watch, journal, snapshots, rollback

~~~lua
local connection = profile:Watch("Coins", function(newValue, oldValue)
    print("Coin change:", oldValue, "to", newValue)
end)
local allChanges = profile:Watch(nil, function(newValue, oldValue, currentProfile, path)
    print("Change path:", path)
end)

local checkpoint = profile:Snapshot("BeforePurchase")
local awarded, newBalance = profile:Award("Coins", 100)
local changes = profile:DiffFromPersisted()
print("Unsaved differences:", #changes)

local restored, restoreError = profile:Restore(checkpoint)
if not restored then warn(restoreError) end
local journal = profile:GetChangeJournal(10)
for _, entry in ipairs(journal) do print(entry.At, entry.MutationId, entry.Path) end
local cleared = profile:ClearChangeJournal()

connection:Disconnect()
allChanges:Disconnect()
~~~

`Snapshot()` retains an in-memory snapshot token owned by the session; `Restore()` refuses foreign or evicted snapshots. These are **not** Roblox DataStore backups. Journaling is disabled unless `ChangeJournalLimit > 0`; clearing the journal affects only memory.

### Save, release, and diagnostics

~~~lua
local saved, saveError = profile:SaveAsync("high")
if not saved then warn("Save failed:", saveError) end

local status = profile:GetStatus()
print(status.Active, status.Dirty, status.CommitBusy)
print(status.LastHeartbeatAge, status.NextAutoSaveIn, status.SavePending)

local stats = profile:GetStats()
print(stats.Valid, stats.Nodes, stats.EstimatedBytes)

-- Only release when the player leaves or your workflow finishes.
-- local released, releaseError = profile:ReleaseAsync()
~~~

`profile:SaveAsync("normal")` can return `true, "DEFERRED"`. For important progress, use `"high"` or `"critical"` sparingly, handle errors, and avoid promise-like claims of durability until a save is confirmed.

## Complete store API examples

Assume `Store` is the shared instance from `DataService`.

### Find active sessions, manual opens, and read-only peeks

~~~lua
local profile = Store:GetSession(player)
local waited, waitError = Store:WaitForSession(player, 10)

-- Manual lifecycle only; do not duplicate automatic lifecycle ownership.
-- local opened, openError = Store:OpenPlayerAsync(player)

-- For arbitrary non-player keys, use a separate Store when data shape differs.
-- local guild, guildError = Store:OpenAsync("Guild_123", {Metadata = {Kind = "Guild"}})

-- Peek does not acquire ownership; never use it to overwrite another owner.
local archivedData, metadataOrError = Store:PeekAsync(player.UserId)
if archivedData then print(archivedData.Coins) else warn(metadataOrError) end
~~~

`Store:OpenAsync(key, context?)` and `Store:OpenPlayerAsync(player)` acquire session ownership. If the player is already managed by the automatic loader, use `GetSession` or `WaitForSession` instead.

### Store-level saving and controlled shutdown

~~~lua
local profile = Store:GetSession(player)
if profile then
    local saved, err = Store:SaveAsync(profile, "high")
    if not saved then warn(err) end
    -- Store:ReleaseAsync(profile) is the store equivalent of profile:ReleaseAsync().
end

-- Admin/shutdown paths; do NOT call these on every normal gameplay action.
-- local flushed, flushError = Store:FlushAsync(20)
-- local releaseResults = Store:ReleaseAllAsync()
-- local closed, closeError = Store:CloseAsync(25)
-- Store:BindToClose() is registered once when the service starts.
-- Store:AttachPlayerLifecycle() is called once when using automatic loading.
~~~

`FlushAsync` saves active sessions but does not itself close the Store. `ReleaseAllAsync` releases all active sessions and reports per-key results. `CloseAsync` is a terminal lifecycle operation, not a per-player cleanup function.

### Validation, template, schema, migrations

~~~lua
local valid, validationError = Store:Validate(profile:GetDataSnapshot())
local template = Store:GetTemplate()
local schema = Store:GetSchema()
local version = Store:GetVersion()

local preview, previewError = Store:PreviewMigration(template, 1, "test-player")
if preview then
    print(preview.FromVersion, preview.ToVersion, #preview.Changes)
else
    warn(previewError)
end
~~~

`PreviewMigration` runs migration callbacks and reconciliation **in memory**; callbacks should be deterministic and free of external side effects. It does not lock, load, or write keys.

### Compression helpers and byte forecasts

~~~lua
local encoded, encodeErrorOrReport = Store:EncodeCompressed(profile:GetDataSnapshot())
if encoded then
    local decoded, decodeError = Store:DecodeCompressed(encoded)
    if not decoded then warn(decodeError) end
else
    warn(encodeErrorOrReport)
end

local report, reportError = Store:GetCompressionReport(profile)
if report then
    print(report.StorageBytes, report.Transport, report.SelectedCodec)
else
    warn(reportError)
end

local forecast, forecastError = Store:GetStorageForecast(profile, 0.80)
if forecast then
    print(forecast.StorageBytes, forecast.RemainingBytes, forecast.NearLimit)
else
    warn(forecastError)
end
~~~

`EncodeCompressed` returns a **codec buffer packet**. It is not a complete player-record lock/envelope and must not be stored as a substitute for a NexusDataStore record. `GetCompressionReport` and `GetStorageForecast` model storage; they do not issue backend writes.

### Metrics, performance, health, and event subscriptions

~~~lua
local metrics = Store:GetMetrics()
local performance = Store:GetPerformanceReport()
local health = Store:GetHealth()
local shutdown = Store:GetSoftShutdownStatus()
local publish = Store:GetAutoPublishStatus()

print(metrics.ActiveSessions, metrics.DirtySessions, metrics.SaveFailed)
print(health.Version, health.CompressionVersion)
print(performance.Enabled, performance.SavesCoalesced)
print(shutdown.Status, publish.Status)

local savedConnection = Store:On("Saved", function(session, priority, releasing)
    print("Saved:", session.Key, priority, releasing)
end)

Store:Once("Opened", function(session)
    print("First session opened:", session.Key)
end)

savedConnection:Disconnect()
~~~

Event callbacks are server-side. Useful names include `Opened`, `Saved`, `Released`, `Changed`, `SessionLost`, `PlayerLoadFailed`, `PlayerReleaseFailed`, `AutoSaveFailed`, `HeartbeatFailed`, `SessionLockWait`, `OrderedSyncFailed`, `CloseFailed`, and `Closed`. Some events are emitted only when the matching optional feature is enabled. The performance report needs `ProfileOperations = true` for detailed samples.

## Ordered leaderboards

Roblox OrderedDataStores are numeric. Configure leaderboard aliases **when creating** the Store:

~~~lua
local Store = NexusDataStore.new({
    Name = "PlayerData",
    Template = PlayersData,
    OrderedDataStores = {
        MostWins = {
            Name = "PlayerWins",
            Path = {"Stats", "Wins"},
            AutoSync = true,
            Mode = "max",
            Integer = true,
            ClampMin = 0,
        },
    },
})
~~~

Use **this constructor configuration instead of**, not alongside, the first `DataService` example. `AutoSync = true` synchronizes leaderboard values from successfully persisted session data. A leaderboard can lag behind an unsaved mutation, and failed syncs need monitoring.

### All ordered-store operations

~~~lua
local leaderboard, leaderboardError = Store:GetOrderedStore("MostWins")
if not leaderboard then
    warn(leaderboardError)
    return
end

local key = tostring(player.UserId)
local got, current = leaderboard:GetAsync(key)
local setOK, stored = leaderboard:SetAsync(key, 20)
local maxOK, maximum = leaderboard:MaxAsync(key, 25)
local minOK, minimum = leaderboard:MinAsync(key, 10)
local incremented, incrementResult = leaderboard:IncrementAsync(key, 1)
local written, writeResult = leaderboard:WriteAsync(key, 30, "max")

local updated, updatedValue = leaderboard:UpdateAsync(key, function(oldValue)
    return (oldValue or 0) + 1
end)

local topOK, top = leaderboard:GetTopAsync(10)
local bottomOK, bottom = leaderboard:GetBottomAsync(10)
local pageOK, firstPage = leaderboard:GetPageAsync(false, 10)
local sortedOK, pages = leaderboard:GetSortedAsync(false, 50)
local rankOK, rankOrError = leaderboard:GetRankAsync(key, false, 10)

local syncOK, syncError = leaderboard:SyncSessionAsync(profile)
local allOK, allError = Store:SyncAllOrderedAsync("MostWins")
local singleOK, singleError = Store:SyncOrderedAsync(profile, "MostWins")

-- Destructive. Use only for intentional leaderboard data removal:
-- local removed, oldValueOrError = leaderboard:RemoveAsync(key)
~~~

Every ordered operation may fail; handle its first return value. `GetSortedAsync` returns a Roblox `DataStorePages` object when successful. `GetPageAsync` returns a table with page-local ranks; use `GetRankAsync` for a bounded search of global rank. Ordered `UpdateAsync` callbacks must be **non-yielding** and safe to run more than once.

### OrderedDataStore option reference

| Field | Meaning |
| --- | --- |
| `Name` / `Scope` | Target OrderedDataStore identity. |
| `Path` | Session value to project, e.g. `{"Stats", "Wins"}`. |
| `Mode` | `"set"`, `"max"` or `"min"`. |
| `AutoSync` | Sync saved data after a successful profile persistence. |
| `ToNumber` | Optional callback to project a value to a number. |
| `KeyFromSession` | Optional callback to choose the ordered key. |
| `Integer` | Require safe integers. |
| `Round` | `"nearest"`, `"floor"`, `"ceil"`. |
| `ClampMin` / `ClampMax` | Optional numeric bounds. |
| `RemoveWhenNil` | Remove the ordered entry when the projected source is nil. |

## Compression and record size

**Default recommendation:** `Compression = true`, `CompressionStrategy = "balanced"`, `CompressionPolicy = "adaptive"`, `CompressionTransport = "auto"`. This favors reasonable CPU use and can fall back to raw storage for data that does not compress well.

### Compare policies without changing stored data

~~~lua
local report, err = Store:GetCompressionReport(profile)
if report then
    print("Final stored bytes:", report.StorageBytes)
    print("Compressed:", report.PersistedCompressed)
    print("Codec:", report.SelectedCodec)
    print("Selection reason:", report.SelectionReason)
else
    warn(err)
end

local forecast, forecastErr = Store:GetStorageForecast(profile, 0.8)
if forecast and forecast.NearLimit then
    warn("Profile approaching its allowed stored-byte limit")
end
~~~

### Optional compact/packed/RLE codec flags

~~~lua
CompressionOptions = {
    CompactEncoding = true,
    BitPackedIntegers = true,
    RunLengthArrays = true,
    StringDictionary = true,
    DeterministicMaps = true,
},
~~~

Put these **inside** `NexusDataStore.new({...})`. Only enable flags after measuring representative player profiles and testing existing records. Compression v2.6.1 can read the library's supported codecs `230` (legacy), `231` (compact), `232` (packed integers), and `233` (run-length arrays). Enabling RLE does not guarantee smaller output.

### Always-smallest compressed mode (opt-in)

~~~lua
Compression = true,
CompressionPolicy = "always-smallest",
CompressionTransport = "auto",
ForceCompressedBuffer = false,
~~~

This tests multiple codec configurations and chooses the smallest **compressed stored representation**, but still may be larger than the uncompressed record and can cost more CPU. It is incompatible with `Compression = false` and `ForceCompressedBuffer = true`.

### Opt-in forced buffer storage

~~~lua
Compression = true,
CompressionPolicy = "adaptive",
CompressionTransport = "buffer",
ForceCompressedBuffer = true,
~~~

`ForceCompressedBuffer` forces a compressed buffer envelope, does not guarantee fewer bytes, and may reject records that would otherwise fit as raw data. Do not force this for tiny profiles merely because a buffer looks more compact. Use `GetStorageForecast` to evaluate the actual stored size.

### Supported player-data values

Supported: booleans, finite numbers, strings, dense arrays, string-keyed dictionaries, and nested combinations within configured limits.

Unsupported as saved `Data` values: Instances, functions, cyclic tables, sparse/mixed-key arrays, NaN/infinity, Roblox object types such as `Vector3`, and raw buffers. Convert nonprimitive types to ordinary numbers/strings/arrays. **Transport buffers are an implementation detail, not a permitted player-data field.**

Example of a position representation when the template includes a corresponding field:

~~~lua
local position = Vector3.new(12, 5, -9)
profile:Set("Position", {X = position.X, Y = position.Y, Z = position.Z})
local raw = profile:Get("Position")
if raw then
    local restoredPosition = Vector3.new(raw.X, raw.Y, raw.Z)
    print(restoredPosition)
end
~~~

## Schemas and migrations

Use `Schema` to validate limits and `SchemaVersion` / `Migrations` to change existing data structures safely. This is an **alternative** store constructor configuration:

~~~lua
local Store = NexusDataStore.new({
    Name = "PlayerData",
    Template = PlayersData,
    SchemaVersion = 2,
    Schema = {
        Coins = {Type = "integer", Min = 0},
        Gems = {Type = "integer", Min = 0},
        Level = {Type = "integer", Min = 1},
    },
    Migrations = {
        [2] = function(data, context)
            data.Stats = data.Stats or {Wins = 0, TotalClicks = 0}
            return data
        end,
    },
    Reconcile = true,
    ValidateOnWrite = true,
})
~~~

Migration keys are **destination** versions. A profile stored at schema v1 runs migration `[2]` to reach v2. Callbacks must not perform external writes or irreversible actions because DataStore updates may retry. Reconciliation only fills missing fields; it is not a substitute for migrating renamed fields or changing old types.

~~~lua
local preview, err = Store:PreviewMigration({
    Coins = 5,
    Gems = 0,
    Level = 1,
}, 1, "example")
if preview then
    print("Migration changed:", preview.Changed)
    print("Changed paths:", #preview.Changes)
else
    warn(err)
end
~~~

Set `Strict = true` only after confirming your existing profiles have no unknown fields. Never reset a locked, corrupt, or newer-schema profile to template defaults in an error handler.

## Restart and cross-server handoff

### Optional soft shutdown UI

Put the source of `SoftShutdownClient.client.lua` inside a **LocalScript** under `ReplicatedFirst`. Set:

~~~lua
local STORE_NAME = "PlayerData"
local REDUCED_MOTION = false
local BACKGROUND_IMAGE_ID = ""
~~~

For the companion Store, set `EnableSoftShutdown = true` and ensure lifecycle management is attached. The UI shows scheduled countdown, saving, transfer, retry, and arrival status and can restore its presentation during teleportation. Background images require an approved Roblox asset ID.

### Optional automatic publish detection

~~~lua
EnableSoftShutdown = true,
AutoRestartOnPublish = true,
AutoPublishPollInterval = 60,
AutoPublishCountdownSeconds = 45,
WaitForSessionLock = true,
~~~

This is **best-effort**: Roblox does not offer an authoritative live server-side "Studio publish completed" event. The watcher uses an asset-version heuristic, so detection can be missed or premature. Live migration uses a fresh reserved/private server and depends on successful final saves and teleport availability. For predictable targeting, use Roblox's official **Restart Servers** workflow.

### Optional detached-session handoff

~~~lua
WaitForSessionLock = true,
EnableSessionHandoff = true,
SessionHandoffCooldown = 6,
~~~

MessagingService is **best effort**. A handoff request is only advisory: the owner must still pass normal fencing and release checks, and **connected player sessions must not be force-released**. Timeouts should be handled as load failures rather than an excuse to overwrite a lock.

## Configuration reference

All fields below go inside `NexusDataStore.new({...})`. Defaults refer to the source's v8.5.0 constructor, not historical versions.

| Option | Default | Notes |
| --- | --- | --- |
| `Name` | required | DataStore name; **keep unchanged for existing profiles**. |
| `Scope` | `"Global"` | Existing scopes must be preserved. |
| `Template` | required | Serializable typed player-data template. |
| `Schema` | `nil` | Optional `SchemaRule` map. |
| `SchemaVersion` | `1` | Requires migrations for older saved records when increased. |
| `Migrations` | `{}` | Migration callbacks by destination version. |
| `Strict` | `false` | Reject unknown root keys when schema checking. |
| `Reconcile` | `true` | Restore missing template fields. |
| `EnforceTemplateTypes` | `true` | Check template-compatible types. |
| `ValidateOnWrite` | `true` | Validate controlled profile mutations. |
| `DetectDirectChanges` | `true` | Track edits to `profile.Data` made outside helpers. |
| `SkipUnchangedMutations` | `false` | Avoid unchanged mutation copies/events. |
| `ProfileOperations` | `false` | Operation timing diagnostics; enable selectively. |
| `ChangeJournalLimit` | `0` | In-memory journal limit, up to 1000. |
| `Compression` | `true` | Codec-aware raw/compressed persistence. |
| `CompressionModule` | auto | Override location of codec ModuleScript. |
| `CompressionOptions` | `{}` | Dictionary, compact, packed and RLE flags. |
| `CompressionReports` | `false` | Emit detailed compression selection events. |
| `CompressionMinBytes` | `512` | Adaptive threshold before considering compression. |
| `ForceCompressedBuffer` | `false` | Forced compressed buffer; opt-in. |
| `CompressionStrategy` | `"balanced"` | `"balanced"` / `"smallest"`. |
| `CompressionPolicy` | `"adaptive"` | `"adaptive"` / `"always-smallest"`. |
| `CompactSessionLocks` | `false` | Opt-in compact lock representation. |
| `CompressionTransport` | `"auto"` | `"auto"` / `"buffer"` / `"base64"`. |
| `AutoSave` | `true` | Autosave active dirty sessions. |
| `AutoSaveInterval` | `30` | Seconds; minimum configured value 10. |
| `MinimumSaveInterval` | `3` | Normal-priority save throttle in seconds. |
| `LockTimeout` | `120` | Lock-expiration window, seconds. |
| `HeartbeatInterval` | derived | Default around one-third of lock timeout. |
| `WaitForSessionLock` | `false` | Wait on locked profiles instead of failing immediately. |
| `SessionLockRetryInterval` | `2` | Lock retry seconds. |
| `EnableSessionHandoff` | `false` | Opt-in MessagingService handoff. |
| `SessionHandoffCooldown` | `6` | Min seconds between handoff requests. |
| `RetryAttempts` | `6` | Backend retry attempts. |
| `RetryBaseDelay` | `0.5` | Initial exponential retry delay. |
| `RetryMaxDelay` | `10` | Cap on retry backoff. |
| `BudgetAware` | `true` | Observe Roblox request budgets. |
| `BudgetWaitTimeout` | `10` | Request budget wait per attempt. |
| `LoadTimeout` | `30` | Default rises to 60 when soft shutdown is enabled. |
| `SaveTimeout` | `30` | Commit deadline in seconds. |
| `MaxDataNodes` | `50000` | Data structural limit. |
| `MaxDataBytes` | `3900000` | Approximate raw-data size limit. |
| `MaxStoredBytes` | `3900000` | Measured stored-record limit. |
| `MaxDepth` | `64` | Nested value depth. |
| `MaxSnapshots` | `10` | Max retained session restore points. |
| `KeyPrefix` | `""` | Existing key prefix must not change accidentally. |
| `PlayerKey` | `nil` | Optional function selecting player keys. |
| `AutoPlayerLifecycle` | `false` | Alternative to calling `AttachPlayerLifecycle()`. |
| `EnableSoftShutdown` | `false` | Optional restart integration. |
| `AutoRestartOnPublish` | `false` | Heuristic publish detection; requires soft shutdown. |
| `AutoPublishPollInterval` | `60` | Detection cadence in seconds. |
| `AutoPublishCountdownSeconds` | `45` | Announcement countdown. |
| `SoftShutdownPreSaveSeconds` | `20` | Pre-save window. |
| `SoftShutdownFreezeSeconds` | `6` | Final mutation freeze window. |
| `SoftShutdownCloseTimeout` | `25` | Shutdown release deadline. |
| `EnableCrossServerEvents` | `false` | General cross-server event integration. |
| `CrossServerTopic` | derived | MessagingService topic. |
| `OrderedDataStores` | `{}` | Named ordered leaderboard configurations. |
| `Debug` | `false` | Development logging. |

CompressionOptions can also include `StringDictionary`, `DictionaryMinLength`, `DictionaryMinUses`, `DictionaryMaxEntries`, `DictionaryMaxCandidates`, `CompactEncoding`, `BitPackedIntegers`, `RunLengthArrays`, `DeterministicMaps`, `AllowExpansion`, `PreallocateLimit`, `MaxDepth`, and `MaxNodes`. Use only supported option types.

## API reference

All *public* methods implemented by the v8.5.0 source are summarized below. The method examples above are copyable; this table is for quick lookup.

### Store API

| Method | Use |
| --- | --- |
| `NexusDataStore.new(config)` | Create/configure a Store. |
| `Store:OpenPlayerAsync(player)` | Open and lock a player's profile. |
| `Store:OpenAsync(key, context?)` | Open a non-player key or custom context. |
| `Store:GetSession(playerOrKey)` | Get an already-open local profile. |
| `Store:WaitForSession(playerOrKey, timeout?)` | Await local profile availability. |
| `Store:PeekAsync(key)` | Read saved data without locking. |
| `Store:SaveAsync(profile, priority?)` | Explicit backend save. |
| `Store:ReleaseAsync(profile)` | Save and release ownership. |
| `Store:FlushAsync(timeout?)` | Save all active profiles. |
| `Store:ReleaseAllAsync()` | Release all sessions, reporting per-key results. |
| `Store:CloseAsync(timeout?)` | Close the entire Store. |
| `Store:AttachPlayerLifecycle()` | Hook player join/leave lifecycle. |
| `Store:BindToClose()` | Register server shutdown work. |
| `Store:Validate(data)` | Validate current data. |
| `Store:GetTemplate()` | Get a detached template copy. |
| `Store:GetSchema()` | Get a detached schema copy, if present. |
| `Store:PreviewMigration(data, fromVersion, key?)` | Migration preview only. |
| `Store:GetStorageForecast(dataOrSession, warningRatio?)` | Stored-byte forecast. |
| `Store:GetVersion()` | Current module version. |
| `Store:EncodeCompressed(data)` | Create a codec packet. |
| `Store:DecodeCompressed(buffer)` | Decode a codec packet. |
| `Store:GetCompressionReport(dataOrSession)` | Size/mode/codec selection report. |
| `Store:GetOrderedStore(alias)` | Access an ordered leaderboard. |
| `Store:SyncOrderedAsync(profile, alias?)` | Sync one profile's leaderboards. |
| `Store:SyncAllOrderedAsync(alias?)` | Sync all open profiles' leaderboards. |
| `Store:GetMetrics()` | Read per-server counters. |
| `Store:GetPerformanceReport()` | Read opt-in timing data. |
| `Store:GetHealth()` | Version, request budgets, and health. |
| `Store:GetSoftShutdownStatus()` | Restart status. |
| `Store:GetAutoPublishStatus()` | Automatic-publish watcher status. |
| `Store:On(event, callback)` | Subscribe to an event. |
| `Store:Once(event, callback)` | Listen once to an event. |

### Profile API

| Method | Use |
| --- | --- |
| `profile:IsActive()` / `profile:IsDirty()` | Check current session state. |
| `profile:Get(path)` / `profile:TryGet(path)` | Read; TryGet is nonthrowing. |
| `profile:GetOr(path, fallback)` / `profile:Has(path)` | Default and existence reads. |
| `profile:GetDataSnapshot()` | Detached full-profile read copy. |
| `profile:SetDefault(path, value)` | Initialize absent value. |
| `profile:Set(path, value)` / `profile:Delete(path)` | Controlled field write/remove. |
| `profile:Patch(changes)` | Multi-path validated update. |
| `profile:Increment(path, amount?)` | Add/subtract a numeric value. |
| `profile:IncrementClamped(path, amount?, min?, max?)` | Bounded increment. |
| `profile:Award(path, amount)` / `profile:Spend(path, amount)` | Currency helpers. |
| `profile:Toggle(path)` | Toggle boolean. |
| `profile:Append(path, value)` / `profile:RemoveAt(path, index)` | Dense-array helpers. |
| `profile:UpdatePath(path, callback)` | Safe transform at one path. |
| `profile:Mutate(callback)` | Atomic in-memory draft update. |
| `profile:Watch(path?, callback)` | Register mutation observer. |
| `profile:Snapshot(label?)` / `profile:Restore(snapshot)` | Session-owned rollback. |
| `profile:DiffFromPersisted()` | Compare live vs last saved snapshot. |
| `profile:SaveAsync(priority?)` / `profile:ReleaseAsync()` | Persist and release. |
| `profile:GetChangeJournal(limit?)` / `profile:ClearChangeJournal()` | Bounded in-memory history. |
| `profile:GetStatus()` / `profile:GetStats()` | Session lifecycle/storage diagnostics. |

### OrderedStore API

| Method | Use |
| --- | --- |
| `ordered:GetAsync(key)` | Read numeric value. |
| `ordered:SetAsync(key, value)` | Set value. |
| `ordered:UpdateAsync(key, callback)` | Atomic numeric transform. |
| `ordered:MaxAsync(key, value)` / `ordered:MinAsync(key, value)` | Monotonic high/low. |
| `ordered:IncrementAsync(key, delta?)` | Increase ordered value. |
| `ordered:RemoveAsync(key)` | Delete an entry. |
| `ordered:WriteAsync(key, value, mode?)` | Write using set/max/min. |
| `ordered:GetSortedAsync(ascending?, pageSize?, min?, max?)` | Get Roblox DataStorePages. |
| `ordered:GetPageAsync(ascending?, pageSize?, min?, max?)` | Get first page as entries. |
| `ordered:GetTopAsync(limit?)` / `ordered:GetBottomAsync(limit?)` | Top/bottom entries. |
| `ordered:GetRankAsync(key, ascending?, maxPages?)` | Bounded rank search. |
| `ordered:SyncSessionAsync(profile)` | Sync one profile to ordered storage. |

## Testing and troubleshooting

### Checks

~~~bash
python3 tools/check_luau_style.py
python3 tools/verify_release.py
python3 tools/run_behavioral_tests.py --luau ./path/to/luau
~~~

GitHub Actions compiles the Luau modules and runs static and portable behavioral regressions. The `tests/MillionLocalBenchmark.server.lua` and `tests/MillionMockBackendBenchmark.server.lua` scripts have configurable million-operation loops for Roblox Studio; CI does not claim to have run one million calls for every API.

### Common errors

| Code or symptom | Meaning / action |
| --- | --- |
| `SESSION_LOCKED` | Another server owns the profile. Wait for release; never override ownership manually. |
| `SESSION_LOCK_WAIT_TIMEOUT` | Lock waiting exceeded the load deadline. |
| `PLAYER_LEFT` | Player departed while loading. Stop using their session. |
| `SESSION_LOST` / `REVISION_CONFLICT` | Stop writes; old session no longer safely owns data. |
| `SAVE_TIMEOUT` / `LOAD_TIMEOUT` | Backend deadline exceeded. Do not claim persistence is certain. |
| `VALIDATION_FAILED` / `SAVE_VALIDATION_FAILED` | Data types or limits are invalid. Inspect the source data. |
| `MIGRATION_MISSING` / `MIGRATION_FAILED` | Repair migration code before opening more affected profiles. |
| `INVALID_PATH` | Use nonempty keys or a dense array path, e.g. `{"Stats","Wins"}`. |
| `SNAPSHOT_NOT_OWNED` | Snapshot is foreign or no longer retained by that session. |
| `COMPRESSION_ENGINE_UNAVAILABLE` | Install the compatible Compression ModuleScript. |
| `DEFERRED` | A normal-priority save was postponed; not a confirmed write. |
| `INVALID_SESSION_KEY` | Invalid key supplied to `WaitForSession`. |

### Deployment safety

1. Back up your test data and keep the same `Name`, `Scope`, `KeyPrefix` and player-key scheme as your existing published game.
2. Deploy the entire set of compatible Lua modules together. Do not upgrade codecs on only some server versions that still need to read the same records.
3. Test join/load/save/rejoin, session-lock waiting, failure handling, migration previews, and leaderboard sync in a published **test universe**.
4. Test restart UI on portrait/landscape devices and verify real teleport/arrival against published Roblox servers.
5. Do not disable data validation, ignore failed releases, or reset profiles automatically on decoding errors.

**Code-style rule:** Every Luau local assignment puts the right-hand expression on the same line: `local a = b`, never `local a =` followed by a new line containing `b`. The CI style checker verifies every Luau file and Luau example in this README.
