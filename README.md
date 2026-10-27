# NexusDataStore

**Typed, session-aware persistence for Roblox experiences.**

![Version](https://img.shields.io/badge/version-7.0.6-2563eb)
![Luau](https://img.shields.io/badge/language-Luau-2563eb)
![Roblox](https://img.shields.io/badge/platform-Roblox-18181b)

NexusDataStore provides player-data persistence with session ownership, validation, schema migrations, autosaving, optional compression, and OrderedDataStore integration. Designed for **server-side Luau**.

| Current release | Compatibility |
| --- | --- |
| **NexusDataStore 7.0.6** | Record format `700` |
| **Compression 2.3.4** | Codec `230` |

## Features

- **Session-safe persistence** — `UpdateAsync` writes, session ownership, retry handling, and conflict protection.
- **Typed profiles** — `PlayersData` templates and Luau type inference.
- **Data integrity** — reconciliation, optional schema validation, migrations, and controlled mutations.
- **Lifecycle management** — automatic player loading/releasing, autosaves, lock heartbeats, and shutdown handling.
- **Adaptive compression** — compare raw, buffer, and Base64 representations; optional size-first encoding.
- **Integrated leaderboards** — numeric OrderedDataStore operations and optional profile synchronization.
- **Diagnostics** — metrics, events, compression reports, and health information.

## Installation

Add the modules to `ServerScriptService`. Rename the GitHub source files to the ModuleScript names shown below:

~~~text
ServerScriptService
└── Data
    ├── NexusDataStore      [ModuleScript — DataStore.lua]
    │   ├── PlayersData     [ModuleScript — your typed template]
    │   └── Compression     [ModuleScript — Compression.lua]
    └── DataBootstrap       [Script]
~~~

`PlayersData` must be a **direct child** of `NexusDataStore`. `Compression` may be a child or an adjacent ModuleScript, or passed with `CompressionModule`. Enable Studio API access when running tests against a test universe; never test migrations or persistence using production data.

### 1. Define player data

`NexusDataStore/PlayersData`:

~~~lua
--!strict
local PlayersData = {
    Coins = 0,
    Level = 1,
    Inventory = {} :: {string},
    Settings = {Music = true},
}

export type Data = typeof(PlayersData)
return PlayersData
~~~

The template defines your persisted fields and is used for reconciliation and type checking. Use supported scalar values, dense arrays, and string-keyed tables; convert `Vector3`, `CFrame`, `Color3`, and other Roblox datatypes to serializable components.

### 2. Initialize the store

`Data/DataBootstrap`:

~~~lua
--!strict
local Players = game:GetService("Players")
local Folder = script.Parent
local NexusDataStore = require(Folder.NexusDataStore)
local PlayersData = require(Folder.NexusDataStore.PlayersData)

local Store = NexusDataStore.new({
    Name = "PlayerData",
    Template = PlayersData,
    Compression = true,
    CompressionStrategy = "balanced",
    CompressionTransport = "auto",
    CompactSessionLocks = false,
    AutoSave = true,
    BudgetAware = true,
})

Store:On("PlayerLoadFailed", function(player, err)
    warn("[NexusDataStore] Load failed:", player.UserId, err)
    if player.Parent == Players then
        player:Kick("Your data could not be loaded. Please rejoin.")
    end
end)

Store:AttachPlayerLifecycle()
Store:BindToClose()
~~~

`AttachPlayerLifecycle()` handles joins and departures. Do **not** install duplicate player lifecycle handlers for the same store. Initialize the store once and share the instance with other server scripts through your own server-side module.

### 3. Work with an active profile

~~~lua
local profile = Store:GetSession(player)
if not profile then return end

local ok, coinsOrError = profile:Award("Coins", 100)
if not ok then warn(coinsOrError) end

profile:Set({"Settings", "Music"}, false)
profile:Append("Inventory", "Sword")

local coins = profile:Get("Coins")
local level = profile:GetOr("Level", 1)

-- Apply multiple changes as one validated in-memory mutation.
local changed, result, status = profile:Mutate(function(data)
    if data.Coins < 50 then return false end
    data.Coins -= 50
    table.insert(data.Inventory, "Potion")
    return true
end)
if not changed then warn(result) end
if status == "CANCELLED" then print("Not enough coins") end

local saved, saveError = profile:SaveAsync("critical")
if not saved then warn("Save failed:", saveError) end
~~~

Wait until loading has completed before accessing a player's session. A canceled `Mutate` returns `true, nil, "CANCELLED"`; changes to separate DataStore keys are not transactional.

## Configuration

| Setting | Default | Purpose |
| --- | --- | --- |
| `Compression` | `true` | Enable adaptive player-record compression. |
| `CompressionStrategy` | `"balanced"` | `"smallest"` also tries dictionary-enabled and disabled encodings. |
| `CompressionMinBytes` | `512` | Skip custom compression below this measured raw size; use `0` to evaluate all records. |
| `CompressionTransport` | `"auto"` | Choose between buffer and Base64; can be forced to either. |
| `CompactSessionLocks` | `false` | Optional compact persisted lock representation. |
| `AutoSave` | `true` | Periodic persistence. |
| `AutoSaveInterval` | `30` | Autosave target interval in seconds. |
| `LockTimeout` | `120` | Session lock lifetime in seconds. |
| `BudgetAware` | `true` | Consider Roblox DataStore request budgets. |
| `Reconcile` | `true` | Restore missing template fields. |
| `DetectDirectChanges` | `true` | Detect modifications made directly to `profile.Data`. |
| `SchemaVersion` | `1` | Version used by optional schema migrations. |

`"balanced"` is the recommended starting point. `"smallest"` chooses the smallest **measured serialized** representation, but uses additional CPU and does not guarantee a smaller Roblox compressed-at-rest size.

To inspect the estimated storage for a loaded player:

~~~lua
local report, err = Store:GetCompressionReport(profile)
if report then
    print(report.StorageBytes, report.Transport, report.PersistedCompressed)
else
    warn(err)
end
~~~

### Session-lock compatibility

**Keep `CompactSessionLocks = false` until all servers using the same DataStore run v7.0.6 or newer.** Earlier releases cannot decode compact locks. Drain older servers before enabling the option, and rewrite compact locks to the legacy format before rolling back. Player records continue to use format `700` and compression codec `230`.

## OrderedDataStore

OrderedDataStores store **numeric leaderboard values** and are not affected by player-record compression.

~~~lua
local Store = NexusDataStore.new({
    Name = "PlayerData",
    Template = PlayersData,
    OrderedDataStores = {
        Coins = {
            Name = "CoinsLeaderboard",
            Path = "Coins",
            Mode = "max",
            AutoSync = true,
            Integer = true,
            ClampMin = 0,
        },
    },
})

local leaderboard = Store:GetOrderedStore("Coins")
local ok, entriesOrError = leaderboard:GetTopAsync(10)
if not ok then warn(entriesOrError) end
~~~

`Mode = "max"` retains highest scores; `"min"` retains lowest values; `"set"` overwrites. The example is an **alternative store configuration**, not a second concurrent instance for the same player keys.

## API overview

| Store | Profile |
| --- | --- |
| `OpenAsync` / `OpenPlayerAsync` | `Get` / `GetOr` / `Has` |
| `GetSession` / `WaitForSession` | `Set` / `Delete` / `Patch` |
| `PeekAsync` | `Award` / `Spend` / `Increment` |
| `SaveAsync` / `ReleaseAsync` | `IncrementClamped` / `Toggle` |
| `FlushAsync` / `CloseAsync` | `Append` / `RemoveAt` |
| `GetCompressionReport` | `UpdatePath` / `Mutate` |
| `GetOrderedStore` / `SyncOrderedAsync` | `Watch` / `Snapshot` / `Restore` |
| `On` / `Once` | `SaveAsync` / `ReleaseAsync` |
| `GetMetrics` / `GetHealth` | `GetStatus` / `GetStats` |

All writes should be performed on the server. Validate results and never replace a profile with default data following a load, decode, ownership, or validation error. Roblox DataStore quotas and limits still apply.

## Testing

Regression scripts are available in [`tests/`](./tests). They cover codec round trips, malformed inputs, compact locks, ambiguous write acknowledgements, load/shutdown races, and close recovery.

**Runtime verification is still required:** run the scripts in Roblox Studio against a separate test environment, then test cross-server session ownership, save failures, and rejoining before deploying to production.

For platform-specific guidance, see [Roblox DataStore documentation](https://create.roblox.com/docs/cloud-services/data-stores) and [error codes and limits](https://create.roblox.com/docs/cloud-services/data-stores/error-codes-and-limits).
