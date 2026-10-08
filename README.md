# NexusDataStore

![Version](https://img.shields.io/badge/version-v7.0.3-4c8bf5)
![Language](https://img.shields.io/badge/language-Luau-00A2FF)
![Platform](https://img.shields.io/badge/platform-Roblox-111111)
![Runtime](https://img.shields.io/badge/runtime-server--only-orange)
![Record Format](https://img.shields.io/badge/record%20format-700-2ea44f)
![Compression](https://img.shields.io/badge/compression-v2.3.x%20%7C%20codec%20230-6f42c1)

**NexusDataStore v7.0.3** is a typed, session-aware Roblox persistence layer built for reliable player data, compact storage, controlled mutations, migrations, snapshots, observability, and integrated OrderedDataStore synchronization.

The current build is tied directly to a `PlayersData` ModuleScript:

```lua
local PlayersData = require(script.PlayersData)

export type Data = PlayersData.Data
```

That type flows through the public API:

```text
PlayersData.Data
      |
      v
 Store<Data>
      |
      v
Session<Data>
      |
      v
profile.Data
```

This means `profile.Data.Coins`, `profile.Data.Inventory`, and every other declared field can be understood by Luau instead of collapsing to `any`.

> **Current release:** NexusDataStore `7.0.3`  
> **Record format:** `700`  
> **Compression series:** `2.3.x`  
> **Compression codec:** `230`  
> **Recommended Compression build:** `2.3.3`

---

## Maintenance update — v7.0.3 / Compression v2.3.3

This release is a backward-compatible bug-fix update to the **GitHub v7.0.x line**. It keeps **record format 700** and **binary codec 230** unchanged; the Compression v2.3.x API remains supported.

- **Fixed large map save failures:** the default codec node allowance now accounts for both values and string map keys. The persistence validator and binary encoder use different node-counting rules.
- **Reduced unnecessary allocations:** profile snapshots used exclusively for direct-change detection are no longer cloned when `DetectDirectChanges = false`. Existing copy-on-write API behavior is unchanged.
- **Faster no-listener mutations:** changed-event argument cloning is skipped when no session watcher or global `Changed` listener exists.
- **Hardened packet decoding:** noncanonical variable-length integers and nil map values now fail explicitly instead of being accepted or silently discarded.
- **Regression scripts:** `tests/CompressionRegression.server.lua` checks round-trips, corrupted checksums, and malformed packets. `tests/NexusDataStoreRegression.server.lua` checks a 2,200-key map and the revised node allowance.

### Compatibility and testing

Use `DataStore.lua` as a server-side ModuleScript containing the `PlayersData` child module described below; place the `Compression` ModuleScript next to it or pass `CompressionModule`. Existing v2.3.x codec-230 saved payloads remain readable; this update does **not** migrate or rewrite DataStore keys until they are naturally saved.

**Studio tests are supplied but must be executed in Roblox Studio** before deployment to a live experience. Put each `.server.lua` test Script beside the required ModuleScripts in `ServerScriptService`, run it, and check the Output panel. The DataStore regression exercises module construction and local encode/decode only; it does not write player data.

Roblox already compresses persisted DataStore values. Benchmark `Compression = true` against `Compression = false` on representative player saves rather than assuming extra application-side compression is always beneficial. Each per-key value must remain within Roblox's current 4,194,304-character limit; the library keeps its stricter `MaxStoredBytes` safety margin.

---

## Contents

- [Core Features](#core-features)
- [Project Structure](#project-structure)
- [PlayersData and Strict Typing](#playersdata-and-strict-typing)
- [Quick Start](#quick-start)
- [Loading Players](#loading-players)
- [Working With Profile Data](#working-with-profile-data)
- [Nested Paths](#nested-paths)
- [Atomic Mutations](#atomic-mutations)
- [Snapshots and Rollback](#snapshots-and-rollback)
- [Watching Data](#watching-data)
- [Saving and Releasing](#saving-and-releasing)
- [Autosave and Session Ownership](#autosave-and-session-ownership)
- [Schema Validation](#schema-validation)
- [Schema Migrations](#schema-migrations)
- [Compression](#compression)
  - [Supported Compression Types](#supported-compression-types)
  - [Compression Quick Start](#compression-quick-start)
  - [Compression Examples for Every Supported Type](#compression-examples-for-every-supported-type)
  - [Compression Reports](#compression-reports)
  - [Compression Options](#compression-options)
  - [DataStore Compression Transport](#datastore-compression-transport)
  - [Corruption Protection](#corruption-protection)
- [OrderedDataStore](#ordereddatastore)
  - [Leaderboard Configuration](#leaderboard-configuration)
  - [Set Max and Min Modes](#set-max-and-min-modes)
  - [Manual Ordered Writes](#manual-ordered-writes)
  - [Incrementing](#incrementing)
  - [Reading Leaderboards](#reading-leaderboards)
  - [Getting a Player Rank](#getting-a-player-rank)
  - [Automatic Session Sync](#automatic-session-sync)
  - [Projected Ordered Values](#projected-ordered-values)
  - [Custom Ordered Keys](#custom-ordered-keys)
- [Events](#events)
- [Health and Metrics](#health-and-metrics)
- [Configuration Reference](#configuration-reference)
- [API Reference](#api-reference)
- [Production Patterns](#production-patterns)
- [Testing](#testing)
- [FAQ](#faq)

---

# Core Features

NexusDataStore provides:

- typed `PlayersData.Data` integration;
- `Store<Data>` and `Session<Data>` inference;
- `profile.Data` autocomplete in strict Luau;
- `UpdateAsync`-based persistence;
- server/session ownership locks;
- revision conflict protection;
- retry-stable commits;
- DataStore budget awareness;
- bounded load/save deadlines;
- autosave and lock heartbeats;
- direct-change detection;
- template reconciliation;
- optional runtime schema validation;
- schema migrations;
- snapshots and restore;
- path-based mutation helpers;
- mutation watchers;
- compression with checksum validation;
- automatic compressed/raw persistence selection;
- buffer/Base64 compression transports;
- built-in OrderedDataStore support;
- leaderboard synchronization;
- cross-server events through `MessagingService`;
- health and metrics reporting.

---

# Project Structure

The simplest supported layout is:

```text
ServerScriptService
└── Data
    ├── NexusDataStore            ModuleScript
    │   ├── PlayersData           ModuleScript
    │   └── Compression           ModuleScript
    │
    └── DataBootstrap             Script
```

`PlayersData` must be a child of `NexusDataStore` in the current build because the module loads it with:

```lua
local PlayersData = require(script.PlayersData)
```

`Compression` can also be supplied explicitly with `CompressionModule`, but keeping it as a child of `NexusDataStore` is the cleanest default.

---

# PlayersData and Strict Typing

Create `PlayersData` under `NexusDataStore`:

```lua
--!strict

local PlayersData = {
    Coins = 0,
    Rebirths = 0,
    Gems = 0,

    Settings = {
        Music = true,
        SFX = true,
    },

    Inventory = {} :: {string},
}

export type Data = typeof(PlayersData)

return PlayersData
```

NexusDataStore imports that exported type:

```lua
export type Data = PlayersData.Data
```

The public aliases include:

```lua
export type Profile = Session<Data>
export type PlayerProfile = Session<Data>
export type PlayerStore = Store<Data>
export type PlayerStoreConfig = StoreConfig<Data>
export type PlayerSnapshot = Snapshot<Data>
```

You can also reuse the exported aliases from another strict server module:

```lua
local NexusDataStore = require(path.To.NexusDataStore)

type Data = NexusDataStore.Data
type Profile = NexusDataStore.Profile
type PlayerStore = NexusDataStore.PlayerStore
```

So a loaded profile resolves to the real player-data shape:

```lua
local profile, err = Store:OpenPlayerAsync(player)

if not profile then
    warn(err)
    return
end

profile.Data.Coins += 100
profile.Data.Rebirths += 1
profile.Data.Settings.Music = false
```

With `--!strict`, Luau can reject invalid assignments:

```lua
profile.Data.Coins = "100"
-- Type error: string is not a number
```

and invalid fields:

```lua
print(profile.Data.Coinss)
-- Type error: field 'Coinss' does not exist
```

---

# Quick Start

```lua
--!strict

local ServerScriptService = game:GetService("ServerScriptService")

local DataFolder = ServerScriptService.Data
local NexusDataStore = require(DataFolder.NexusDataStore)

local Store = NexusDataStore.new({
    Name = "PlayerData",

    Template = require(DataFolder.NexusDataStore.PlayersData),

    Compression = true,
    CompressionTransport = "auto",

    AutoSave = true,
    AutoSaveInterval = 30,

    BudgetAware = true,
    Reconcile = true,
    EnforceTemplateTypes = true,
    ValidateOnWrite = true,
    DetectDirectChanges = true,
})
```

The minimum configuration is:

```lua
local Store = NexusDataStore.new({
    Name = "PlayerData",
    Template = require(script.Parent.NexusDataStore.PlayersData),
})
```

Important defaults include:

```text
Scope                  = "Global"
SchemaVersion          = 1
Reconcile              = true
EnforceTemplateTypes   = true
ValidateOnWrite        = true
DetectDirectChanges    = true
Compression            = true
CompressionTransport   = "auto"
AutoSave               = true
AutoSaveInterval       = 30
LockTimeout            = 120
RetryAttempts          = 6
BudgetAware            = true
LoadTimeout            = 30
SaveTimeout            = 30
```

---

# Loading Players

```lua
local Players = game:GetService("Players")

local function onPlayerAdded(player: Player)
    local profile, err = Store:OpenPlayerAsync(player)

    if not profile then
        warn("[NexusDataStore] Load failed:", player, err)
        player:Kick("Your data could not be loaded. Please rejoin.")
        return
    end

    print("Loaded", player.Name)
    print("Coins:", profile.Data.Coins)
end

Players.PlayerAdded:Connect(onPlayerAdded)

for _, player in Players:GetPlayers() do
    task.spawn(onPlayerAdded, player)
end
```

Do not continue player initialization after a failed load.

A failed or corrupt stored record should not silently be replaced with blank progression.

---

# Working With Profile Data

## Direct typed access

```lua
profile.Data.Coins += 10
```

Direct edits are supported when `DetectDirectChanges = true`. The store detects that the live table changed before persistence.

For explicit mutation tracking, prefer the mutation API.

## Get

```lua
local coins = profile:Get("Coins")
```

## GetOr

```lua
local value = profile:GetOr("Coins", 0)
```

## Has

```lua
if profile:Has("Settings") then
    print("Settings exist")
end
```

## Set

```lua
local ok, err = profile:Set("Coins", 500)

if not ok then
    warn(err)
end
```

## Increment

```lua
local ok, newCoins = profile:Increment("Coins", 25)

if ok then
    print("Coins:", newCoins)
end
```

Default increment:

```lua
profile:Increment("Coins")
```

## IncrementClamped

```lua
local ok, stamina = profile:IncrementClamped(
    "Stamina",
    -10,
    0,
    100
)
```

## Toggle

```lua
profile:Toggle({"Settings", "Music"})
```

## Append

```lua
profile:Append("Inventory", "WoodenSword")
```

## RemoveAt

```lua
profile:RemoveAt("Inventory", 1)
```

## Award

`Award()` accepts a non-negative finite amount:

```lua
local ok, coins = profile:Award("Coins", 100)
```

## Spend

`Spend()` refuses the mutation when the balance is too low:

```lua
local ok, balanceOrError = profile:Spend("Coins", 250)

if not ok then
    warn(balanceOrError)
end
```

## UpdatePath

```lua
profile:UpdatePath("Coins", function(oldCoins)
    return (oldCoins or 0) * 2
end)
```

## Patch

Apply multiple path writes as one validated draft:

```lua
local ok, err = profile:Patch({
    {
        Path = "Coins",
        Value = 1000,
    },
    {
        Path = "Rebirths",
        Value = 10,
    },
    {
        Path = {"Settings", "Music"},
        Value = false,
    },
})

if not ok then
    warn(err)
end
```

---

# Nested Paths

A path can be:

```lua
"Coins"
```

a numeric array index:

```lua
1
```

or a path array:

```lua
{"Settings", "Music"}
```

Example:

```lua
local music = profile:Get({"Settings", "Music"})

profile:Set({"Settings", "Music"}, false)
```

For arrays:

```lua
local firstItem = profile:Get({"Inventory", 1})
```

Path arrays must be non-empty.

Numeric path keys must be positive safe integers.

---

# Atomic Mutations

Use `Mutate()` when several fields must change together:

```lua
if profile.Data.Coins < 1000 then
    warn("NOT_ENOUGH_COINS")
    return
end

local ok, result = profile:Mutate(function(data, session)
    data.Coins -= 1000
    data.Rebirths += 1

    return "REBIRTH_COMPLETE"
end)

if not ok then
    warn(result)
else
    print(result)
end
```

The callback receives:

```lua
data: PlayersData.Data
session: Session<PlayersData.Data>
```

The mutation flow is conceptually:

```text
clone profile.Data
       |
       v
run callback on draft
       |
       v
validate draft
       |
   +---+---+
   |       |
 valid   invalid
   |       |
   v       v
commit    reject
```

This is useful for:

- purchases;
- rebirths;
- prestige resets;
- crafting;
- reward claims;
- multi-stat upgrades;
- inventory transactions.

---

# Snapshots and Rollback

Create a snapshot:

```lua
local snapshot = profile:Snapshot("before-rebirth")
```

The returned object is typed as:

```lua
Snapshot<Data>
```

Restore it:

```lua
local ok, err = profile:Restore(snapshot)

if not ok then
    warn(err)
end
```

Inspect differences from the last successfully persisted state:

```lua
local changes = profile:DiffFromPersisted()

for _, change in changes do
    print(change.Path, change.Before, change.After)
end
```

The number of retained runtime snapshots is controlled by:

```lua
MaxSnapshots = 10
```

Snapshots are runtime objects. They are not a second permanent DataStore history system.

---

# Watching Data

Watch a specific path:

```lua
local connection = profile:Watch("Coins", function(newValue, oldValue, session, path)
    print("Coins:", oldValue, "->", newValue)
end)
```

Watch every controlled mutation:

```lua
local connection = profile:Watch(nil, function(newValue, oldValue, session, path)
    print("Changed path:", path)
end)
```

Disconnect:

```lua
connection:Disconnect()
```

---

# Saving and Releasing

## Manual save

```lua
local ok, err = profile:SaveAsync()

if not ok then
    warn("Save failed:", err)
end
```

Optional priority:

```lua
profile:SaveAsync("normal")
profile:SaveAsync("high")
profile:SaveAsync("critical")
```

When omitted, the current implementation uses `"high"`.

`"normal"` saves can return:

```text
DEFERRED
```

when `MinimumSaveInterval` has not elapsed. `"high"` and `"critical"` bypass that normal-save spacing check.

The current priority type is:

```lua
"normal" | "high" | "critical"
```

## Release

```lua
local ok, err = profile:ReleaseAsync()

if not ok then
    warn("Release failed:", err)
end
```

A release performs the final ownership-safe commit and removes the active session when successful.

## Flush the store

```lua
local ok, err = Store:FlushAsync(20)

if not ok then
    warn(err)
end
```

## Release every active session

```lua
local results = Store:ReleaseAllAsync()

for key, result in pairs(results) do
    print(key, result.Success, result.Error)
end
```

## Close

```lua
local ok, err = Store:CloseAsync(25)

if not ok then
    warn(err)
end
```

---

# Autosave and Session Ownership

NexusDataStore uses a lock inside the stored record.

A stored record contains metadata conceptually similar to:

```lua
{
    Format = 700,
    SchemaVersion = 1,
    Revision = 12,
    CreatedAt = 0,
    UpdatedAt = 0,

    Data = {
        -- PlayersData
    },

    Lock = {
        JobId = "...",
        SessionId = "...",
        HeartbeatAt = 0,
        ExpiresAt = 0,
    },

    LastCommitId = "...",
}
```

The lock is renewed independently through heartbeat commits.

Defaults:

```text
LockTimeout       = 120 seconds
HeartbeatInterval = floor(LockTimeout / 3), capped to <= LockTimeout / 2
AutoSaveInterval  = 30 seconds
```

The store also protects against stale overwrites with a revision check.

If the stored revision no longer matches the active session revision, the commit fails with:

```text
REVISION_CONFLICT
```

The session is not allowed to blindly overwrite the newer record.

---

# Schema Validation

Template-type enforcement is enabled by default:

```lua
EnforceTemplateTypes = true
```

For:

```lua
local PlayersData = {
    Coins = 0,
    Name = "",
    Settings = {
        Music = true,
    },
}
```

the store rejects incompatible shapes such as:

```lua
{
    Coins = "not a number",
    Name = 123,
}
```

You can also provide an explicit schema:

```lua
local Store = NexusDataStore.new({
    Name = "PlayerData",
    Template = PlayersData,

    Schema = {
        Coins = {
            Type = "number",
            Required = true,
            Min = 0,
        },

        Rebirths = {
            Type = "integer",
            Required = true,
            Min = 0,
        },

        Inventory = {
            Type = "array",
            ArrayOf = {
                Type = "string",
            },
        },

        Settings = {
            Type = "table",
            Children = {
                Music = {
                    Type = "boolean",
                    Required = true,
                },
            },
            AllowUnknown = false,
        },
    },
})
```

Supported schema type names are:

```text
any
boolean
number
integer
string
table
array
```

A custom validator can return `true`, `false`, or an error string:

```lua
Schema = {
    Coins = {
        Type = "number",

        Validate = function(value, path)
            if value % 1 ~= 0 then
                return path .. " must be a whole number"
            end

            return true
        end,
    },
}
```

---

# Schema Migrations

Increase `SchemaVersion` when your persistent layout needs a migration.

Example old data:

```lua
local PlayersDataV1 = {
    Coins = 0,
}
```

New data:

```lua
local PlayersData = {
    Coins = 0,
    Gems = 0,
}
```

Configure:

```lua
local Store = NexusDataStore.new({
    Name = "PlayerData",
    Template = PlayersData,

    SchemaVersion = 2,

    Migrations = {
        [2] = function(data, context)
            data.Gems = data.Gems or 0

            print(
                "Migrating",
                context.Key,
                context.FromVersion,
                "->",
                context.ToVersion
            )

            return data
        end,
    },
})
```

Migration entries are keyed by the **target version**.

For a profile moving from version `1` to version `2`, the function is:

```lua
Migrations[2]
```

For multiple upgrades:

```lua
Migrations = {
    [2] = function(data)
        data.Gems = data.Gems or 0
        return data
    end,

    [3] = function(data)
        data.Rebirths = data.Rebirths or 0
        return data
    end,
}
```

NexusDataStore applies every missing migration in order.

---

# Compression

NexusDataStore v7.0.3 is compatible with the **Compression v2.3.x** series using codec:

```text
230
```

The recommended module build is:

```text
Compression v2.3.3
```

The packet format has a fixed 11-byte header containing the codec identity, flags, and checksum metadata.

The direct compression API is:

```lua
Compression.CompressTablePacket(value, options?)
Compression.DecompressTable(buffer, options?)
Compression.Measure(value, options?)
Compression.TableMode(value, options?)
Compression.Version()
```

---

## Supported Compression Types

Compression v2.3.3 directly supports these Luau value types:

| Luau value | Supported | Encoding behavior |
|---|---:|---|
| `nil` | Yes | dedicated tag |
| `boolean` | Yes | dedicated `true` / `false` tags |
| safe integer `number` | Yes | signed variable-length integer |
| non-integer finite `number` | Yes | `f64` |
| `string` | Yes | raw string or dictionary reference |
| dense array `table` | Yes | array tag + count + values |
| map `table` | Yes | map tag + count + key/value pairs |
| nested tables | Yes | recursive |
| circular tables | No | rejected |
| `NaN` / `math.huge` | No | rejected |
| `buffer` | No | rejected by Compression v2.3.3 |
| `Vector2` | No | rejected |
| `Vector3` | No | rejected |
| `CFrame` | No | rejected |
| `Color3` | No | rejected |
| `Instance` | No | rejected |
| functions / threads | No | rejected |

The DataStore persistence validator is intentionally narrower than the standalone codec:

- the root player data must be a table;
- arrays must be dense;
- dictionary keys must be strings;
- mixed/sparse tables are rejected;
- circular references are rejected;
- non-finite numbers are rejected;
- Roblox datatypes such as `Vector3`, `CFrame`, and `buffer` are not persistent values in this v7.0.3 codec path.

---

## Compression Quick Start

```lua
local Compression = require(script.Parent.Compression)

local value = {
    Coins = 150000,
    Rebirths = 25,
    Title = "Legendary",
}

local packet, report = Compression.CompressTablePacket(value)

print("Raw bytes:", report.RawBytes)
print("Encoded bytes:", report.EncodedBytes)
print("Saved bytes:", report.SavedBytes)
print("Savings:", report.SavingsPercent)
print("Dictionary entries:", report.DictionaryEntries)

local decoded = Compression.DecompressTable(packet)

print(decoded.Coins)
print(decoded.Rebirths)
print(decoded.Title)
```

Always test the round trip:

```lua
assert(decoded.Coins == value.Coins)
assert(decoded.Rebirths == value.Rebirths)
assert(decoded.Title == value.Title)
```

---

## Compression Examples for Every Supported Type

### Nil

The direct codec can encode a root `nil`:

```lua
local packet = Compression.CompressTablePacket(nil)
local decoded = Compression.DecompressTable(packet)

assert(decoded == nil)
```

A NexusDataStore player record itself cannot use `nil` as its root data because persistent player data must be a table.

### Boolean

```lua
local packet = Compression.CompressTablePacket(true)
local decoded = Compression.DecompressTable(packet)

assert(decoded == true)
```

False:

```lua
local packet = Compression.CompressTablePacket(false)
local decoded = Compression.DecompressTable(packet)

assert(decoded == false)
```

### Small integer

Integers use the signed variable-length path when they are within the codec's supported integer range:

```lua
local packet, report = Compression.CompressTablePacket(30)

print(report.EncodedBytes)

local decoded = Compression.DecompressTable(packet)

assert(decoded == 30)
```

### Negative integer

```lua
local packet = Compression.CompressTablePacket(-250)
local decoded = Compression.DecompressTable(packet)

assert(decoded == -250)
```

### Large integer

```lua
local value = 1_000_000_000

local packet = Compression.CompressTablePacket(value)
local decoded = Compression.DecompressTable(packet)

assert(decoded == value)
```

### Floating-point number

Non-integer finite numbers use `f64`:

```lua
local value = 123.456

local packet = Compression.CompressTablePacket(value)
local decoded = Compression.DecompressTable(packet)

assert(decoded == value)
```

Invalid numbers are rejected:

```lua
-- Compression.CompressTablePacket(0 / 0)
-- NON_FINITE_NUMBER

-- Compression.CompressTablePacket(math.huge)
-- NON_FINITE_NUMBER
```

### String

```lua
local value = "NexusDataStore"

local packet = Compression.CompressTablePacket(value)
local decoded = Compression.DecompressTable(packet)

assert(decoded == value)
```

For a single short string, packet framing can be larger than the original value. Compression becomes more useful when strings repeat inside larger structures.

### Dense numeric array

```lua
local value = {1, 30, 3490}

local packet, report = Compression.CompressTablePacket(value)
local decoded = Compression.DecompressTable(packet)

assert(decoded[1] == 1)
assert(decoded[2] == 30)
assert(decoded[3] == 3490)

print("Encoded:", report.EncodedBytes)
```

### String array

```lua
local value = {
    "Common",
    "Common",
    "Common",
    "Rare",
    "Legendary",
}

local packet, report = Compression.CompressTablePacket(value)
local decoded = Compression.DecompressTable(packet)

assert(decoded[5] == "Legendary")

print("Dictionary entries:", report.DictionaryEntries)
```

Repeated strings can be replaced with dictionary references when that is profitable.

### String-keyed map

```lua
local value = {
    Coins = 5000,
    Rebirths = 12,
    Rank = "Elite",
}

local packet = Compression.CompressTablePacket(value)
local decoded = Compression.DecompressTable(packet)

assert(decoded.Coins == 5000)
assert(decoded.Rebirths == 12)
assert(decoded.Rank == "Elite")
```

### Nested table

```lua
local value = {
    Coins = 5000,

    Settings = {
        Music = true,
        SFX = false,
    },

    Inventory = {
        "Sword",
        "Potion",
        "Potion",
    },
}

local packet = Compression.CompressTablePacket(value)
local decoded = Compression.DecompressTable(packet)

assert(decoded.Settings.Music == true)
assert(decoded.Inventory[1] == "Sword")
```

### Repeated map keys and values

This is where the string dictionary is useful:

```lua
local value = {
    Inventory = {
        {
            Id = "CommonRune",
            Type = "CommonRune",
            Name = "CommonRune",
        },
        {
            Id = "CommonRune",
            Type = "CommonRune",
            Name = "CommonRune",
        },
        {
            Id = "CommonRune",
            Type = "CommonRune",
            Name = "CommonRune",
        },
    },
}

local packet, report = Compression.CompressTablePacket(value)

print("Dictionary entries:", report.DictionaryEntries)
print("Dictionary bytes:", report.DictionaryBytes)
print("Savings:", report.SavingsPercent)
```

### Deterministic maps

Enable deterministic key ordering when stable packet ordering is important:

```lua
local options = {
    DeterministicMaps = true,
}

local packetA = Compression.CompressTablePacket({
    Coins = 10,
    Gems = 20,
}, options)

local packetB = Compression.CompressTablePacket({
    Gems = 20,
    Coins = 10,
}, options)

assert(buffer.tostring(packetA) == buffer.tostring(packetB))
```

In deterministic mode, map keys must be:

```text
string
number
boolean
```

For persistent NexusDataStore dictionaries, use string keys.

---

## Complete Compression Type Smoke Test

This test exercises every value category supported by Compression v2.3.3:

```lua
local Compression = require(script.Parent.Compression)

local cases = {
    {
        Name = "nil",
        Value = nil,
    },
    {
        Name = "false",
        Value = false,
    },
    {
        Name = "true",
        Value = true,
    },
    {
        Name = "positive integer",
        Value = 3490,
    },
    {
        Name = "negative integer",
        Value = -3490,
    },
    {
        Name = "float",
        Value = 123.456,
    },
    {
        Name = "string",
        Value = "NexusDataStore",
    },
    {
        Name = "array",
        Value = {1, 30, 3490},
    },
    {
        Name = "map",
        Value = {
            Coins = 5000,
            Rebirths = 12,
        },
    },
    {
        Name = "nested",
        Value = {
            Stats = {
                Coins = 5000,
            },

            Runes = {
                "Common",
                "Common",
                "Legendary",
            },
        },
    },
}

for _, case in cases do
    local packet, report =
        Compression.CompressTablePacket(case.Value)

    local decoded =
        Compression.DecompressTable(packet)

    print(
        case.Name,
        "bytes =", report.EncodedBytes,
        "savings =", report.SavingsPercent
    )

    if case.Value == nil then
        assert(decoded == nil)
    elseif typeof(case.Value) ~= "table" then
        assert(decoded == case.Value)
    end
end
```

For table cases, verify the fields that matter to your schema, or use your own deep-equality helper.

Do not include unsupported values such as:

```lua
Vector3.new(1, 2, 3)
CFrame.new()
buffer.create(8)
workspace.Part
function() end
```

Compression v2.3.3 rejects them with `UNSUPPORTED_TYPE:<type>`.

---

## Compression Reports

Measure without manually handling the packet:

```lua
local report = Compression.Measure({
    Coins = 1000000,
    Rebirths = 100,
    Inventory = {
        "Common",
        "Common",
        "Rare",
    },
})

print("RawBytes:", report.RawBytes)
print("RawBits:", report.RawBits)

print("EncodedBytes:", report.EncodedBytes)
print("EncodedBits:", report.EncodedBits)

print("PayloadBytes:", report.PayloadBytes)
print("HeaderBytes:", report.HeaderBytes)

print("SavedBytes:", report.SavedBytes)
print("SavedBits:", report.SavedBits)

print("Ratio:", report.Ratio)
print("SavingsPercent:", report.SavingsPercent)

print("DictionaryEntries:", report.DictionaryEntries)
print("DictionaryBytes:", report.DictionaryBytes)

print("Codec:", report.Codec)
print("EngineVersion:", report.EngineVersion)
```

The key formulas are:

```text
Ratio = EncodedBytes / RawBytes

SavingsPercent =
    (1 - Ratio) * 100
```

A negative savings percentage means the compressed packet is larger than the codec's raw-size estimate.

That is normal for very small values because the packet has fixed framing overhead.

---

## Compression Options

```lua
local options = {
    StringDictionary = true,

    DictionaryMinLength = 4,
    DictionaryMinUses = 2,
    DictionaryMaxEntries = 16384,
    DictionaryMaxCandidates = 100000,

    MaxDepth = 128,
    MaxNodes = 2000000,

    DeterministicMaps = false,

    PreallocateLimit = 4194304,

    AllowExpansion = false,
}
```

### `StringDictionary`

Default:

```lua
true
```

Allows profitable repeated strings to be stored once and referenced by index.

### `DictionaryMinLength`

Default:

```lua
4
```

Strings shorter than this are not dictionary candidates.

### `DictionaryMinUses`

Default:

```lua
2
```

A candidate must occur at least this many times.

### `DictionaryMaxEntries`

Default:

```lua
16384
```

Bounds the final dictionary size.

### `DictionaryMaxCandidates`

Default:

```lua
100000
```

Bounds candidate collection work.

### `MaxDepth`

Default:

```lua
128
```

Rejects excessively deep values.

### `MaxNodes`

Default:

```lua
2000000
```

Bounds encode/decode traversal.

### `DeterministicMaps`

Default:

```lua
false
```

When enabled, supported map keys are sorted before encoding.

### `PreallocateLimit`

Default:

```lua
4194304
```

Caps the writer's initial preallocation estimate.

### `AllowExpansion`

This option is important to NexusDataStore persistence selection.

The direct `Compression.CompressTablePacket()` API still returns a packet.

NexusDataStore uses `AllowExpansion = false` to avoid persisting the compressed representation when the final stored representation is not smaller than the raw record.

---

## DataStore Compression Transport

NexusDataStore can persist compression with:

```lua
CompressionTransport = "auto"
```

Available modes:

```text
auto
buffer
base64
```

### Auto

Recommended:

```lua
CompressionTransport = "auto"
```

The store evaluates the actual serialized size of the candidates and keeps the better persistence representation.

Conceptually:

```text
raw record
    |
    +--> Compression packet
             |
             +--> buffer envelope
             |
             `--> Base64 envelope
    |
    v
compare stored sizes
    |
    v
smallest allowed representation
```

If compression is larger and expansion is disabled, NexusDataStore stores the raw record instead.

### Buffer

```lua
CompressionTransport = "buffer"
```

Forces the compressed envelope to use a Roblox `buffer` payload.

### Base64

```lua
CompressionTransport = "base64"
```

Uses a Base64 string payload.

This mode exists as a compatibility/fallback transport.

---

## Compression Through the Store

Use the exact options configured on the store:

```lua
local packet, report = Store:EncodeCompressed({
    Coins = 1000,
    Rebirths = 10,
})

if not packet then
    warn(report)
    return
end

print("Packet bytes:", buffer.len(packet))
print("Savings:", report.SavingsPercent)
```

Decode:

```lua
local decoded, err = Store:DecodeCompressed(packet)

if not decoded then
    warn(err)
    return
end

print(decoded.Coins)
```

Inspect what persistence would actually choose:

```lua
local report, err = Store:GetCompressionReport(profile)

if not report then
    warn(err)
    return
end

print("RawStorageEstimate:", report.RawStorageEstimate)
print("StorageBytes:", report.StorageBytes)
print("Transport:", report.Transport)
print("PersistedCompressed:", report.PersistedCompressed)
```

This report follows the same persistence selection path used by saves.

---

## Corruption Protection

Compression v2.3.3 validates:

- packet magic;
- codec version;
- packet flags;
- Adler-32 payload checksum;
- dictionary counts;
- duplicate dictionary entries;
- node limits;
- depth limits;
- array counts;
- map counts;
- duplicate map keys;
- finite numbers;
- trailing bytes.

Examples of decode failures include:

```text
COMPRESSION_TRUNCATED
COMPRESSION_MAGIC_MISMATCH
UNSUPPORTED_COMPRESSION_VERSION
COMPRESSION_CHECKSUM_MISMATCH
INVALID_DICTIONARY_COUNT
DUPLICATE_DICTIONARY_ENTRY
INVALID_ARRAY_COUNT
INVALID_MAP_COUNT
DUPLICATE_MAP_KEY
COMPRESSION_TRAILING_BYTES
```

NexusDataStore treats decode failure as a load failure.

It does not intentionally replace a corrupt profile with defaults and then overwrite the stored progression.

---

# OrderedDataStore

NexusDataStore has a built-in wrapper around Roblox OrderedDataStore.

It can be used independently or synchronized from a profile path.

Ordered values are numeric.

Each ordered store is configured under:

```lua
OrderedDataStores = {
    Alias = {
        -- config
    },
}
```

Retrieve it with:

```lua
local leaderboard, err = Store:GetOrderedStore("Coins")

if not leaderboard then
    error(err)
end
```

---

## Leaderboard Configuration

Example:

```lua
local Store = NexusDataStore.new({
    Name = "PlayerData",
    Template = PlayersData,

    OrderedDataStores = {
        Coins = {
            Name = "CoinsLeaderboard",
            Scope = "Global",

            Path = "Coins",

            Mode = "max",
            AutoSync = true,

            Integer = true,
            ClampMin = 0,
        },

        Rebirths = {
            Name = "RebirthLeaderboard",
            Path = "Rebirths",

            Mode = "max",
            AutoSync = true,

            Integer = true,
            ClampMin = 0,
        },
    },
})
```

When `Name` is omitted, the default is:

```text
<MainStoreName>_<Alias>
```

Example:

```text
PlayerData_Coins
```

When `Scope` is omitted, the parent store scope is used.

---

## Set Max and Min Modes

Three write modes are available.

### Set

Always replace the current value:

```lua
Mode = "set"
```

Equivalent manual call:

```lua
ordered:SetAsync(userId, 500)
```

### Max

Only replace when the new value is greater:

```lua
Mode = "max"
```

Useful for:

- highest score;
- best wave;
- most rebirths;
- fastest progression value where larger is better.

```lua
ordered:MaxAsync(userId, 500)
```

If the existing value is `700`, writing `500` becomes a no-op.

### Min

Only replace when the new value is lower:

```lua
Mode = "min"
```

Useful for:

- fastest completion time;
- fewest moves;
- best low-score metric.

```lua
ordered:MinAsync(userId, 42)
```

If the existing value is `30`, writing `42` becomes a no-op.

---

## Manual Ordered Writes

### SetAsync

```lua
local ok, value = ordered:SetAsync(player.UserId, 1000)

if not ok then
    warn(value)
end
```

### WriteAsync

Uses the store's configured mode:

```lua
local ok, value = ordered:WriteAsync(player.UserId, 1000)
```

Override the mode for one call:

```lua
ordered:WriteAsync(player.UserId, 1000, "set")
ordered:WriteAsync(player.UserId, 1000, "max")
ordered:WriteAsync(player.UserId, 1000, "min")
```

### UpdateAsync

```lua
local ok, value, state = ordered:UpdateAsync(
    player.UserId,

    function(oldValue)
        oldValue = oldValue or 0

        if oldValue >= 1_000_000 then
            return nil
        end

        return oldValue + 100
    end
)

if not ok then
    warn(value)
elseif state == "CANCELLED" then
    print("No write was needed")
else
    print("New value:", value)
end
```

The transform must be:

- non-yielding;
- deterministic enough to be retried;
- safe to execute more than once by the underlying `UpdateAsync` process.

### RemoveAsync

```lua
local ok, err = ordered:RemoveAsync(player.UserId)

if not ok then
    warn(err)
end
```

---

## Incrementing

Default delta:

```lua
ordered:IncrementAsync(player.UserId)
```

Custom delta:

```lua
ordered:IncrementAsync(player.UserId, 25)
```

For an integer store without clamping or rounding, NexusDataStore can use Roblox's native OrderedDataStore increment path.

When the ordered store uses floating-point values, clamps, or rounding, NexusDataStore routes the increment through `UpdateAsync` so normalization is still applied correctly.

---

## Reading Leaderboards

### Get one value

```lua
local ok, value = ordered:GetAsync(player.UserId)

if ok then
    print("Ordered value:", value)
else
    warn(value)
end
```

### Top entries

```lua
local ok, entries = ordered:GetTopAsync(10)

if not ok then
    warn(entries)
    return
end

for _, entry in entries do
    print(
        "#" .. entry.Rank,
        entry.Key,
        entry.Value
    )
end
```

### Bottom entries

```lua
local ok, entries = ordered:GetBottomAsync(10)

if not ok then
    warn(entries)
    return
end

for _, entry in entries do
    print(entry.Rank, entry.Key, entry.Value)
end
```

### Filtered top page

```lua
local ok, entries = ordered:GetTopAsync(
    25,
    1000,
    1_000_000
)
```

The minimum/maximum filters used by the current wrapper must be safe integers.

### Raw sorted pages

```lua
local ok, pages = ordered:GetSortedAsync(
    false, -- descending
    100
)

if not ok then
    warn(pages)
    return
end

for _, entry in pages:GetCurrentPage() do
    print(entry.key, entry.value)
end
```

---

## Getting a Player Rank

```lua
local ok, rankInfo = ordered:GetRankAsync(
    player.UserId,
    false, -- descending
    10     -- maximum pages to scan
)

if not ok then
    warn(rankInfo)
    return
end

print("Rank:", rankInfo.Rank)
print("Key:", rankInfo.Key)
print("Value:", rankInfo.Value)
```

`GetRankAsync()` scans pages until:

- the key is found;
- the OrderedDataStore is exhausted; or
- `maxPages` is reached.

Possible non-success results include:

```text
ORDERED_KEY_NOT_FOUND
RANK_SCAN_LIMIT
```

---

## Automatic Session Sync

Configure:

```lua
OrderedDataStores = {
    Coins = {
        Path = "Coins",
        Mode = "max",
        AutoSync = true,
        Integer = true,
    },
}
```

`AutoSync = true` requires `Path`.

After a successful persistent profile save, NexusDataStore synchronizes configured ordered stores when the saved snapshot is stable.

Manual sync:

```lua
local ok, err = Store:SyncOrderedAsync(profile, "Coins")

if not ok then
    warn(err)
end
```

Sync every ordered store configured for one profile:

```lua
Store:SyncOrderedAsync(profile)
```

Sync an alias across every active profile:

```lua
Store:SyncAllOrderedAsync("Coins")
```

Sync every ordered store across every active profile:

```lua
Store:SyncAllOrderedAsync()
```

---

## Projected Ordered Values

`ToNumber` can convert a stored profile value into the numeric value required by OrderedDataStore.

Example data:

```lua
local PlayersData = {
    BestRun = {
        Round = 0,
        Time = 0,
    },
}
```

Configuration:

```lua
OrderedDataStores = {
    BestRound = {
        Path = {"BestRun"},

        Mode = "max",
        AutoSync = true,
        Integer = true,

        ToNumber = function(bestRun, session)
            return bestRun.Round
        end,
    },
}
```

Another example:

```lua
ToNumber = function(value)
    return math.floor(value * 1000)
end
```

This is useful when the profile representation is not already a single numeric value.

---

## Custom Ordered Keys

By default, synchronized ordered stores use:

1. `session.UserId`, when available;
2. otherwise `session.Key`.

Override that behavior:

```lua
OrderedDataStores = {
    Coins = {
        Path = "Coins",
        AutoSync = true,

        KeyFromSession = function(session)
            return "Season1_" .. tostring(session.UserId)
        end,
    },
}
```

Ordered keys must normalize to a string between 1 and 50 bytes.

---

## Ordered Value Normalization

Available options:

```lua
{
    ClampMin = 0,
    ClampMax = 1_000_000,

    Integer = true,

    Round = "nearest",
}
```

Rounding modes:

```text
nearest
floor
ceil
```

Example:

```lua
OrderedDataStores = {
    Rating = {
        Path = "Rating",

        Mode = "set",
        AutoSync = true,

        ClampMin = 0,
        ClampMax = 5000,

        Integer = true,
        Round = "nearest",
    },
}
```

---

# Events

Subscribe with:

```lua
local connection = Store:On("Saved", function(profile, reason, release)
    print(
        "Saved",
        profile.Key,
        reason,
        release
    )
end)
```

One-shot listener:

```lua
Store:Once("Opened", function(profile)
    print("First opened profile:", profile.Key)
end)
```

Events emitted by the current implementation include:

```text
Opened
Saved
Released
Changed
SessionLost
CompressionReport
OrderedSyncCompleted
OrderedSyncFailed
DirectChangeInvalid
AutoSaveFailed
HeartbeatFailed
PlayerLoadFailed
PlayerReleaseFailed
PlayerKeyFailed
CrossServerEvent
CrossServerError
Closed
```

Example compression diagnostics:

```lua
Store:On("CompressionReport", function(report)
    print(
        report.StorageBytes,
        report.Transport,
        report.PersistedCompressed
    )
end)
```

Enable these reports with:

```lua
CompressionReports = true
```

---

# Health and Metrics

## Metrics

```lua
local metrics = Store:GetMetrics()

print("Opened:", metrics.Opened)
print("Saved:", metrics.Saved)
print("SaveFailed:", metrics.SaveFailed)
print("Retries:", metrics.Retries)

print("Heartbeats:", metrics.Heartbeats)
print("SessionLost:", metrics.SessionLost)

print("BytesEncoded:", metrics.BytesEncoded)

print("OrderedReads:", metrics.OrderedReads)
print("OrderedWrites:", metrics.OrderedWrites)
print("OrderedUpdates:", metrics.OrderedUpdates)
print("OrderedSyncs:", metrics.OrderedSyncs)
print("OrderedSyncFailed:", metrics.OrderedSyncFailed)
```

## Health

```lua
local health = Store:GetHealth()

print("Version:", health.Version)
print("RecordFormat:", health.RecordFormat)
print("CompressionVersion:", health.CompressionVersion)

print("Closed:", health.Closed)
print("Closing:", health.Closing)

for requestName, budget in pairs(health.Budgets) do
    print(requestName, budget)
end
```

---

# Configuration Reference

## Store configuration

| Option | Default | Description |
|---|---:|---|
| `Name` | required | Standard DataStore name |
| `Scope` | `"Global"` | Standard DataStore scope |
| `Template` | required | `PlayersData.Data` template |
| `Schema` | `nil` | Optional runtime validation schema |
| `SchemaVersion` | `1` | Persistent schema version |
| `Migrations` | `{}` | Migration functions keyed by target version |
| `Strict` | `false` | Reject unknown template/schema keys |
| `Reconcile` | `true` | Fill missing template fields |
| `EnforceTemplateTypes` | `true` | Require loaded/written values to match template types |
| `ValidateOnWrite` | `true` | Validate controlled mutations before commit |
| `DetectDirectChanges` | `true` | Detect direct edits to `profile.Data` |
| `Compression` | `true` | Enable persistence compression selection |
| `CompressionModule` | auto | Explicit Compression ModuleScript override |
| `CompressionOptions` | `{}` | Compression v2.3.x options |
| `CompressionReports` | `false` | Emit `CompressionReport` events |
| `CompressionTransport` | `"auto"` | `"auto"`, `"buffer"`, or `"base64"` |
| `AutoSave` | `true` | Enable periodic saves |
| `AutoSaveInterval` | `30` | Seconds between target autosaves |
| `LockTimeout` | `120` | Session-lock lifetime |
| `HeartbeatInterval` | derived | Session-lock refresh interval |
| `RetryAttempts` | `6` | Backend retry attempts |
| `RetryBaseDelay` | `0.5` | Initial retry backoff |
| `RetryMaxDelay` | `10` | Maximum retry backoff |
| `BudgetAware` | `true` | Wait for Roblox request budget |
| `BudgetWaitTimeout` | `10` | Maximum budget wait per attempt |
| `MinimumSaveInterval` | `3` | Minimum normal-save spacing |
| `LoadTimeout` | `30` | Overall load deadline |
| `SaveTimeout` | `30` | Overall save deadline |
| `MaxDataNodes` | `50000` | Maximum validated data nodes |
| `MaxDataBytes` | `3900000` | Maximum estimated raw data size |
| `MaxStoredBytes` | `3900000` | Maximum final stored representation |
| `MaxDepth` | `64` | Maximum persistent table depth |
| `MaxSnapshots` | `10` | Runtime snapshots retained |
| `KeyPrefix` | `""` | Prefix added to normal DataStore keys |
| `PlayerKey` | `nil` | Custom player key function |
| `AutoPlayerLifecycle` | `false` | Automatically open/release players |
| `EnableCrossServerEvents` | `false` | Enable MessagingService events |
| `CrossServerTopic` | generated | Cross-server MessagingService topic |
| `OrderedDataStores` | `{}` | OrderedDataStore definitions |
| `Debug` | `false` | Debug logging |

## Compression options

| Option | Default |
|---|---:|
| `StringDictionary` | `true` |
| `DictionaryMinLength` | `4` |
| `DictionaryMinUses` | `2` |
| `DictionaryMaxEntries` | `16384` |
| `DictionaryMaxCandidates` | `100000` |
| `MaxDepth` | `128` |
| `MaxNodes` | `2000000` |
| `DeterministicMaps` | `false` |
| `PreallocateLimit` | `4194304` |
| `AllowExpansion` | `false` |

## OrderedDataStore configuration

| Option | Default | Description |
|---|---:|---|
| `Name` | `<Store>_<Alias>` | OrderedDataStore name |
| `Scope` | parent scope | OrderedDataStore scope |
| `Path` | `nil` | Profile path to synchronize |
| `Mode` | `"max"` | `"set"`, `"max"`, or `"min"` |
| `AutoSync` | `false` | Sync after successful profile saves |
| `ToNumber` | `nil` | Convert profile value to a number |
| `KeyFromSession` | UserId/key | Custom ordered key |
| `ClampMin` | `nil` | Minimum output value |
| `ClampMax` | `nil` | Maximum output value |
| `Integer` | `false` | Require a safe integer |
| `Round` | `nil` | `"nearest"`, `"floor"`, or `"ceil"` |
| `RemoveWhenNil` | `false` | Remove ordered entry when synced path is nil |

---

# API Reference

## NexusDataStore

```lua
NexusDataStore.new(config)
```

Public metadata:

```lua
NexusDataStore.Version
NexusDataStore.RecordFormat
NexusDataStore.RequiredCompressionVersion
NexusDataStore.Errors
NexusDataStore.OrderedDataStore
NexusDataStore.Compression
```

## Store

```lua
Store:OpenAsync(key, context?)
Store:OpenPlayerAsync(player)

Store:PeekAsync(key)

Store:GetSession(keyOrPlayer)
Store:WaitForSession(keyOrPlayer, timeout?)

Store:SaveAsync(session, priority?)
Store:ReleaseAsync(session)

Store:FlushAsync(timeout?)
Store:ReleaseAllAsync()
Store:CloseAsync(timeout?)

Store:Validate(data)

Store:GetTemplate()
Store:GetSchema()
Store:GetVersion()

Store:EncodeCompressed(data)
Store:DecodeCompressed(buffer)
Store:GetCompressionReport(dataOrSession)

Store:GetOrderedStore(alias)
Store:SyncOrderedAsync(session, alias?)
Store:SyncAllOrderedAsync(alias?)

Store:GetMetrics()
Store:GetHealth()

Store:AttachPlayerLifecycle()
Store:BindToClose()

Store:On(eventName, callback)
Store:Once(eventName, callback)
```

## Session / Profile

```lua
profile:IsActive()
profile:IsDirty()

profile:Get(path)
profile:GetOr(path, fallback)
profile:Has(path)

profile:Set(path, value)
profile:Delete(path)

profile:Increment(path, amount?)
profile:IncrementClamped(path, amount?, min?, max?)

profile:Toggle(path)

profile:Append(path, value)
profile:RemoveAt(path, index)

profile:Award(path, amount)
profile:Spend(path, amount)

profile:UpdatePath(path, callback)
profile:Mutate(callback)
profile:Patch(changes)

profile:Watch(path?, callback)

profile:Snapshot(label?)
profile:Restore(snapshot)
profile:DiffFromPersisted()

profile:SaveAsync(priority?)
profile:ReleaseAsync()

profile:GetStatus()
profile:GetStats()
```

## OrderedStore

```lua
ordered:GetAsync(key)

ordered:SetAsync(key, value)
ordered:UpdateAsync(key, transform)

ordered:MaxAsync(key, value)
ordered:MinAsync(key, value)

ordered:IncrementAsync(key, delta?)
ordered:RemoveAsync(key)

ordered:WriteAsync(key, value, mode?)

ordered:GetSortedAsync(ascending?, pageSize?, minimum?, maximum?)
ordered:GetPageAsync(ascending?, pageSize?, minimum?, maximum?)

ordered:GetTopAsync(limit?, minimum?, maximum?)
ordered:GetBottomAsync(limit?, minimum?, maximum?)

ordered:GetRankAsync(key, ascending?, maxPages?)

ordered:SyncSessionAsync(profile)
```

## Compression

```lua
Compression.Version()
Compression.TableMode(value, options?)

Compression.CompressTablePacket(value, options?)
Compression.DecompressTable(packet, options?)

Compression.Measure(value, options?)
```

---

# Production Patterns

## Use server authority

Do not trust a client-supplied balance:

```lua
RemoteEvent.OnServerEvent:Connect(function(player, requestedCoins)
    local profile = Store:GetSession(player)

    if not profile then
        return
    end

    profile:Set("Coins", requestedCoins)
end)
```

Prefer server-defined progression:

```lua
RemoteEvent.OnServerEvent:Connect(function(player)
    local profile = Store:GetSession(player)

    if not profile then
        return
    end

    profile:Award("Coins", 1)
end)
```

## Keep progression bounded

Compression does not remove Roblox platform limits.

Put deliberate limits on:

- inventory length;
- string length;
- nested table depth;
- generated keys;
- leaderboard scan depth;
- snapshot count.

## Do not overwrite decode failures

If:

```lua
OpenPlayerAsync()
```

returns a decode or validation error, stop initialization.

Do not create a fresh profile and immediately save it over the failed record.

## Prefer controlled mutations

This:

```lua
profile:Award("Coins", 100)
```

gives the store an immediate mutation boundary.

Direct writes:

```lua
profile.Data.Coins += 100
```

can still be detected when `DetectDirectChanges = true`, but controlled APIs avoid waiting for a scan to discover the edit.

## Use max mode for high-score leaderboards

```lua
Mode = "max"
```

prevents a lower later value from replacing a player's best score.

## Use min mode for completion times

```lua
Mode = "min"
```

preserves the player's fastest time when lower is better.

---

# Testing

Before production, test all of the following.

## Persistence

- first join;
- manual save;
- leave/rejoin;
- server shutdown;
- autosave;
- release;
- direct mutation detection;
- controlled mutations;
- invalid data rejection;
- schema reconciliation;
- migrations.

## Concurrency

- two servers attempting the same profile;
- lock expiration;
- heartbeat renewal;
- revision conflict;
- save during mutation;
- release during mutation.

## Compression

Use representative player data, not only tiny values.

```lua
local test = {
    Coins = 10_000_000,
    Rebirths = 250,

    Inventory = {
        "CommonRune",
        "CommonRune",
        "CommonRune",
        "LegendaryRune",
    },

    Upgrades = {
        Click = 100,
        Luck = 50,
        Speed = 25,
    },
}

local packet, report = Compression.CompressTablePacket(test)
local decoded = Compression.DecompressTable(packet)

print("Raw:", report.RawBytes)
print("Encoded:", report.EncodedBytes)
print("Saved:", report.SavedBytes)
print("Savings:", report.SavingsPercent)
print("Dictionary:", report.DictionaryEntries)

assert(decoded.Coins == test.Coins)
assert(decoded.Upgrades.Click == test.Upgrades.Click)
assert(decoded.Inventory[4] == test.Inventory[4])
```

Also test:

- corrupted checksum;
- truncated packets;
- repeated strings;
- deep tables;
- large arrays;
- all-default player state;
- heavily changed player state;
- `CompressionTransport = "auto"`;
- buffer transport;
- Base64 transport.

## OrderedDataStore

Test:

- `set`;
- `max`;
- `min`;
- positive increment;
- negative increment;
- clamp min/max;
- integer mode;
- rounding;
- top 10;
- bottom 10;
- rank lookup;
- auto sync after save;
- manual sync;
- remove on nil;
- budget pressure.

---

# FAQ

## Is `profile.Data` really typed?

Yes.

The current module uses:

```lua
export type Data = PlayersData.Data
```

and exposes the player store as:

```lua
Store<Data>
```

which returns:

```lua
Session<Data>
```

therefore:

```lua
profile.Data
```

is `PlayersData.Data`.

## Does Compression support every Roblox datatype?

No.

Compression v2.3.3 supports:

```text
nil
boolean
finite number
string
array table
map table
nested table
```

It does not currently encode Roblox datatypes such as `Vector3`, `CFrame`, or `buffer`.

## Why can a tiny value become larger?

Every packet has framing/checksum overhead.

Compression is primarily useful for structured values large enough for compact integers and repeated-string dictionaries to outweigh the fixed header.

## Does `AllowExpansion = false` make direct compression return the raw value?

No.

`Compression.CompressTablePacket()` always returns a compression packet.

NexusDataStore uses `AllowExpansion = false` while choosing the final persistence representation, so it can keep the raw record when the compressed envelope would be larger.

## What does `CompressionTransport = "auto"` do?

It compares the available persisted representations and chooses the smaller allowed representation.

That can be:

```text
raw table
compressed buffer envelope
compressed Base64 envelope
```

## Is compression checked for corruption?

Yes.

The packet contains an Adler-32 checksum and the decoder also validates its header, codec, counts, dictionary references, limits, and trailing bytes.

## Are session locks stored in MemoryStore?

Not in this v7 architecture.

The current record owns a `Lock` structure containing the job/session identity and expiration information.

## Does OrderedDataStore store tables?

No.

Roblox OrderedDataStore values are numeric. `ToNumber` exists to project profile data into a numeric leaderboard value.

## What OrderedDataStore mode should I use?

Use:

```text
set -> latest/current value
max -> highest/best large value
min -> lowest/best small value
```

## Does AutoSync require a path?

Yes.

```lua
AutoSync = true
```

requires:

```lua
Path = ...
```

## Does OrderedDataStore sync before or after the main save?

Automatic ordered synchronization runs after a successful stable persistent profile commit.

That keeps the ordered value aligned with successfully persisted profile data.

## Should I use direct writes or `profile:Set()`?

Both can work.

For most gameplay systems, controlled methods such as:

```lua
Set
Increment
Award
Spend
Mutate
Patch
```

are easier to validate and track immediately.

---

# Release Summary

NexusDataStore v7.0.3 uses a deliberately defensive save flow:

```text
PlayersData.Data
      |
      v
Session<Data>
      |
      v
validate / reconcile / mutate
      |
      v
revision-safe UpdateAsync
      |
      +--> raw record
      |
      `--> Compression v2.3.x
              |
              +--> buffer transport
              |
              `--> Base64 transport
      |
      v
smallest allowed persistent representation
      |
      v
Roblox DataStore
```

Ordered data is synchronized separately:

```text
successful profile save
        |
        v
LastPersistedSnapshot
        |
        v
configured OrderedDataStore Path
        |
        v
ToNumber / clamp / round
        |
        v
set / max / min
        |
        v
Roblox OrderedDataStore
```

The design priorities are:

1. preserve player progression;
2. reject malformed or corrupt data rather than silently overwrite it;
3. keep one authoritative typed `PlayersData.Data` shape;
4. make retried saves deterministic;
5. prevent stale-session overwrites;
6. compress when it actually helps storage;
7. keep leaderboard writes aligned with successful profile saves.
