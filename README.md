# DataStore

![Version](https://img.shields.io/badge/version-v4.1.1-4c8bf5)
![Language](https://img.shields.io/badge/language-Luau-00A2FF)
![Platform](https://img.shields.io/badge/platform-Roblox-111111)
![Runtime](https://img.shields.io/badge/runtime-server--only-orange)
![Storage Format](https://img.shields.io/badge/storage%20format-v12-2ea44f)
![Session Format](https://img.shields.io/badge/session%20format-v5-2ea44f)
![Compression](https://img.shields.io/badge/compression-v3.1.0-6f42c1)

**DataStore v4.1.1** is a server-side Roblox persistence module built around a small permanent-storage contract:

> **The permanent Roblox DataStore value is the player's `Data = PlayersData` encoded as a Compression v3.1.0 `IndexedLayout` / `IndexedSchema` buffer.**

The current build adds strict Luau typing, historical schema routing, automatic reconciliation, compact Base85 UserId keys, MemoryStore session locking, dirty-only autosaves, and the new **Sparse Defaults** schema path.

Sparse Defaults is especially useful for simulator-style templates with hundreds of fields whose default values are `0`, `false`, `1`, `""`, or other known defaults.

> Current DataStore release: **v4.1.1**  
> Storage format: **12**  
> Session format: **5**  
> Compression release: **v3.1.0**  
> Compression build: **Sparse Defaults + SchemaPacketVersion**

---

# Contents

- [What Changed](#what-changed)
- [Storage Contract](#storage-contract)
- [Sparse Defaults](#sparse-defaults)
- [400-Key Stress Test](#400-key-stress-test)
- [Requirements](#requirements)
- [Project Structure](#project-structure)
- [PlayersData](#playersdata)
- [Quick Start](#quick-start)
- [Strict Luau Types](#strict-luau-types)
- [Loading Players](#loading-players)
- [Reading and Updating Data](#reading-and-updating-data)
- [Atomic Mutations](#atomic-mutations)
- [Dirty Tracking](#dirty-tracking)
- [Saving](#saving)
- [Autosave](#autosave)
- [Session Locking](#session-locking)
- [Lock Modes](#lock-modes)
- [Updating PlayersData](#updating-playersdata)
- [DataTemplateHistory](#datatemplatehistory)
- [Schema Version Routing](#schema-version-routing)
- [Reconciliation](#reconciliation)
- [Persistent Validation](#persistent-validation)
- [Compact Player Keys](#compact-player-keys)
- [Diagnostics](#diagnostics)
- [Read-Only Inspection](#read-only-inspection)
- [Signals](#signals)
- [Configuration Reference](#configuration-reference)
- [Store API](#store-api)
- [Profile API](#profile-api)
- [Static API](#static-api)
- [Testing](#testing)
- [Production Safety](#production-safety)
- [FAQ](#faq)
- [Release Summary](#release-summary)

---

# What Changed

## v4.1.1

v4.1.1 focuses on making schema upgrades safe.

Older `IndexedSchema` saves are no longer blindly decoded using the newest template.

The load flow is now conceptually:

```text
stored player buffer
        |
        v
Compression.SchemaPacketVersion()
        |
        v
schema version
        |
        v
DataTemplate version = schema version - 1
        |
        +--> current version
        |
        `--> DataTemplateHistory[oldVersion]
                    |
                    v
               decode old data
                    |
                    v
                 reconcile
                    |
                    v
            mark profile dirty
                    |
                    v
            save using newest schema
```

This prevents errors such as:

```text
Compression: unexpected end of payload
Compression: schema version mismatch
```

when a game expands an older template.

## Sparse Defaults

Compression v3.1.0 now has an additional internal schema frame that stores only fields that differ from their defaults.

The old bitmap schema remains readable.

The encoder compares the normal bitmap representation with the sparse representation and keeps the smaller physical payload.

## Strict type surface

The DataStore is tied directly to the exported type of `PlayersData`:

```lua
local Data = require(script.Parent.PlayersData)

export type DataTable = Data.Data
export type DataKey = keyof<DataTable>
export type DataValue = index<DataTable, DataKey>
```

That keeps the profile's persistent shape synchronized with the actual `PlayersData` module.

---

# Storage Contract

Given:

```lua
local PlayersData = {
    Coins = 0,
    Rebirths = 0,
    Gems = 0,
    Level = 1,
    MusicEnabled = true,
}
```

and:

```lua
local Store = DataStore.new({
    Name = "ClickStore5",

    DataTemplate = {
        Version = 2,
        Data = PlayersData,
    },
})
```

the permanent value is conceptually:

```text
DataStoreService
`-- ClickStore5
    `-- <Base85 UserId key>
        `-- <Compression IndexedSchema buffer>
```

The permanent player value is **not**:

```lua
{
    Data = PlayersData,
    SessionId = "...",
    Dirty = false,
    Revision = 12,
    LastSaveClock = 100.5,
    StorageInfo = {},
}
```

Only the encoded player data buffer is written.

---

# What Is Not Stored in the Permanent Player Value

These values are runtime state or diagnostics:

```text
SessionId
Released
Dirty
Revision
LastSavedRevision
LastSaveClock
StoredBytes
RawBytes
SavedBytes
SavingsPercent
UsefulBits
PhysicalBits
PaddingBits
RuntimeStats
Signal listeners
Compression configuration
DataStore configuration
```

Session ownership is stored separately in `MemoryStoreService`.

---

# Sparse Defaults

The normal default-eliding schema already avoids writing full numeric values for fields equal to their defaults.

However, the old format still writes a state bit for every field.

For example, with 100 defaulted fields:

```text
schema header
0
0
0
0
0
...
100 default-state bits
```

Those bits eventually become physical zero bytes.

That is why an all-default profile could look like:

```text
[
    209,
    5,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0
]
```

The zeros are not 12 separate saved numeric values.

They are mostly packed default-state bits.

## New sparse representation

For schemas where every root field has a default and is not optional, Compression can instead write:

```text
SparseSchemaMagic
SchemaVersion
ChangedFieldCount

for each changed field:
    FieldIndexDelta
    EncodedValue
```

If no fields differ from defaults:

```text
SparseSchemaMagic
SchemaVersion
ChangedFieldCount = 0
```

No per-field default bitmap is needed.

## Automatic selection

The encoder still creates the normal bitmap candidate.

It also creates a sparse candidate when the schema is eligible.

Then:

```text
bitmap candidate
        |
        +--> compare physical bytes
        |
sparse candidate
        |
        v
smallest payload wins
```

If sparse would be worse, the old representation is used instead.

This means Sparse Defaults is an optimization, not a requirement for every schema.

## Backward compatibility

Existing `0xD1` schema frames still decode through the original bitmap decoder.

The sparse frame uses a separate marker.

Old DataStore saves therefore do not need to be deleted just because Sparse Defaults was added.

---

# 100-Key Example

Assume 100 root fields and every field equals its template default.

The old bitmap path needs roughly:

```text
8 bits   schema marker
~5 bits  schema version
100 bits default states
----------------------
~113 useful bits
```

That occupies about:

```text
15 physical bytes
```

The sparse all-default representation for schema version 3 needs roughly:

```text
8 bits   sparse marker
5 bits   schema version
1 bit    changed count = 0
------------------------
14 useful bits
```

That fits in:

```text
2 physical bytes
```

The exact bytes are an implementation detail.

The important part is that the payload no longer grows by one default bit per field when nothing changed.

---

# 400-Key Stress Test

The release includes a 400-key test template.

Example shape:

```lua
local PlayersData400 = {
    Stat001 = 0,
    Stat002 = 0,
    Stat003 = 0,
    -- ...
    Stat399 = 0,
    Stat400 = 0,
}
```

The test covers:

```text
0 / 400 changed
1 / 400 changed
10 / 400 changed
100 / 400 changed
400 / 400 changed
```

It also verifies encode/decode round trips and benchmarks repeated encoding and decoding.

## All 400 fields at default

The old bitmap representation requires approximately:

```text
8 + 5 + 400 = 413 useful bits
```

or about:

```text
52 physical bytes
```

The sparse representation still only needs the sparse header, schema version, and changed count.

For schema version 3 with zero changed fields, the bit layout fits in:

```text
2 physical bytes
```

So increasing a flat template from 100 default keys to 400 default keys does **not** automatically increase an all-default sparse payload from 2 bytes to 50+ bytes.

## Changed fields still cost bytes

Sparse Defaults does not make changed values free.

For example:

```lua
data.Stat001 = 123456
data.Stat220 = 42
```

must store:

```text
changed count
field positions
123456
42
```

The savings come from not paying for hundreds of fields that still equal their defaults.

## Dense data

When many or all fields differ from defaults, the regular bitmap representation may become smaller.

The encoder compares both representations and chooses the smaller one.

---

# Requirements

DataStore v4.1.1 is server-only.

Use it from a `Script` or server ModuleScript.

Do not require it directly from a `LocalScript`.

Required structure:

```text
DataStore
`-- Compression
```

The current DataStore is designed for:

```text
Compression v3.1.0
```

The Sparse Defaults build also exposes:

```lua
Compression.SchemaPacketVersion(packet)
```

which the DataStore uses to route old payloads to the correct historical template.

---

# Project Structure

Recommended:

```text
ServerScriptService
`-- Data
    |-- DataStore
    |   `-- Compression
    |
    |-- PlayersData
    |-- PlayersDataV1
    `-- Loader
```

`PlayersDataV1` is only needed while old version-1 `IndexedSchema` saves still exist and must be migrated.

For more versions:

```text
PlayersData
PlayersDataV1
PlayersDataV2
PlayersDataV3
```

You do not need to save those historical templates inside each player entry.

They only exist in server code so the old positional schema can be reconstructed.

---

# PlayersData

Example:

```lua
--!strict

local PlayersData = {
    Coins = 0,
    Rebirths = 0,
    Gems = 0,
    Diamonds = 0,

    Level = 1,
    XP = 0,

    AutoClickUnlocked = false,
    MusicEnabled = true,

    SelectedPet = "",
}

export type Data = typeof(PlayersData)

return PlayersData
```

The exported `Data` type is consumed by DataStore.

---

# Quick Start

```lua
--!strict

local DataStore = require(script.DataStore)
local PlayersData = require(script.PlayersData)

local Store = DataStore.new({
    Name = "ClickStore5",

    DataTemplate = {
        Version = 1,
        Data = PlayersData,
    },
})
```

The defaults already enable:

```text
Reconcile
AutoSave
SaveOnlyDirty
SaveOnRelease
SessionLocking
BudgetAware
Compression
Entropy coding
```

A more explicit setup:

```lua
local Store = DataStore.new({
    Name = "ClickStore5",

    DataTemplate = {
        Version = 1,
        Data = PlayersData,
    },

    Reconcile = true,

    AutoSave = true,
    AutoSaveInterval = 60,
    SaveOnlyDirty = true,
    SaveOnRelease = true,

    SessionLocking = true,
    SessionLockTimeout = 180,
    SessionRefreshInterval = 60,

    RetryAttempts = 5,
    RetryDelay = 0.75,
    MaxRetryDelay = 8,

    BudgetAware = true,
    BudgetWaitTimeout = 10,

    CompressionTableStrategy = "Auto",
    CompressionCompressStrings = true,
    CompressionStringStrategy = "Auto",
    CompressionUseStringDictionary = true,

    CompressionHomogeneousArrays = true,
    CompressionDeltaArrays = true,
    CompressionRunLengthArrays = true,

    CompressionCompactMapKeys = true,
    CompressionTableKeyMapping = true,

    CompressionEntropyCoding = true,
    CompressionEntropyStrategy = "Auto",
    CompressionAllowExpansion = false,

    CompressionBufferStrategy = "Auto",
})
```

---

# Strict Luau Types

The profile exposes:

```lua
profile.Data
```

as the exact exported `PlayersData` type.

For:

```lua
local PlayersData = {
    Coins = 0,
    MusicEnabled = true,
}
```

Luau knows:

```lua
profile.Data.Coins
```

is a number and:

```lua
profile.Data.MusicEnabled
```

is a boolean.

A typo such as:

```lua
profile.Data.Coinss
```

can be caught by strict type checking.

The public key API is based on:

```lua
keyof<DataTable>
```

so top-level keys must come from the declared `PlayersData` shape.

---

# Loading Players

```lua
local Players = game:GetService("Players")

local function playerAdded(player: Player)
    local profile, loadError = Store:OpenPlayerAsync(player)

    if profile == nil then
        warn("[DataStore] Failed to load", player.Name, loadError)
        player:Kick("Your data could not be loaded.")
        return
    end

    print("Loaded:", player.Name)
    print("Coins:", profile.Data.Coins)
end

Players.PlayerAdded:Connect(playerAdded)

for _, player in Players:GetPlayers() do
    task.spawn(playerAdded, player)
end
```

Always stop initialization after a failed load.

Do not silently replace a failed profile with blank data.

---

# Reading and Updating Data

## Direct read

```lua
print(profile.Data.Coins)
print(profile.Data.Rebirths)
```

## Get

```lua
local value = profile:Get("Coins")
```

## Set

```lua
profile:Set("Coins", 100)
```

`Set()` validates the profile and marks it dirty.

## Increment

```lua
profile:Increment("Coins")
profile:Increment("Coins", 25)
```

## Update

```lua
profile:Update("Coins", function(value)
    return value + 100
end)
```

## Get a copy

```lua
local copy = profile:GetDataCopy()
```

Changing the returned copy does not directly mutate the active profile.

## Overwrite

```lua
profile:Overwrite({
    Coins = 100,
    Rebirths = 2,
    Gems = 0,
    Diamonds = 0,
    Level = 1,
    XP = 0,
    AutoClickUnlocked = false,
    MusicEnabled = true,
    SelectedPet = "",
})
```

The replacement must remain compatible with the declared template.

---

# Atomic Mutations

Use `Profile:Mutate()` for a transaction that changes several fields.

```lua
profile:Mutate(function(data)
    data.Coins -= 1000
    data.Rebirths += 1
end)
```

The operation is transactional at the profile-table level:

```text
copy old data
    |
    v
run callback
    |
    v
validate
    |
    +--> success -> commit + dirty
    |
    `--> failure -> restore backup
```

This is useful for:

- rebirths;
- prestige resets;
- crafting;
- purchases;
- reward claims;
- multi-stat upgrades.

---

# Dirty Tracking

```lua
print(profile:IsDirty())
```

Mutating APIs mark the profile dirty.

With:

```lua
SaveOnlyDirty = true
```

unchanged profiles are skipped by autosave.

Runtime diagnostics do not make a profile dirty.

Historical schema migration does mark a migrated profile dirty so it can be rewritten using the newest schema.

---

# Saving

## Manual save

```lua
local success, saveError = profile:SaveAsync()

if not success then
    warn(saveError)
end
```

## Store-level save

```lua
local success, saveError = Store:SavePlayerAsync(player)
```

## Flush

```lua
local success, failures = Store:FlushAsync()

print(success, failures)
```

## Get current encoded buffer

```lua
local bufferValue = profile:GetBuffer()

print(buffer.len(bufferValue))
```

---

# Autosave

Defaults:

```lua
AutoSave = true
AutoSaveInterval = 60
SaveOnlyDirty = true
```

The autosave loop spreads work across loaded profiles.

It does not intentionally save every active profile at the same instant.

---

# Save on Release

Default:

```lua
SaveOnRelease = true
```

When a profile is released, dirty persistent data is saved before the session lock is released.

The module installs its own `Players.PlayerRemoving` handler.

It also installs its own `BindToClose` handler.

Application code normally should not create duplicate release handlers for the same Store.

---

# Session Locking

Session ownership is separate from permanent player progression.

The current session payload is approximately:

```lua
{
    Id = <16-byte GUID buffer>,
    Released = false,
}
```

It is stored in `MemoryStoreService`.

Default settings:

```lua
SessionLocking = true
SessionLockTimeout = 180
SessionRefreshInterval = 60
LoadTimeout = 30
LockRetryInterval = 1
MemoryLockRetryAttempts = 4
```

The session heartbeat runs independently from permanent DataStore autosaves.

An unchanged profile can skip permanent writes while still refreshing its MemoryStore lock.

---

# Lock Modes

`OpenPlayerAsync()` supports:

```lua
type LockMode = "Wait" | "Cancel" | "Steal"
```

## Wait

Default:

```lua
local profile, err = Store:OpenPlayerAsync(player)
```

or:

```lua
local profile, err = Store:OpenPlayerAsync(player, {
    Locked = "Wait",
})
```

## Cancel

```lua
local profile, err = Store:OpenPlayerAsync(player, {
    Locked = "Cancel",
})
```

If another session owns the profile, loading stops.

## Steal

```lua
local profile, err = Store:OpenPlayerAsync(player, {
    Locked = "Steal",
})
```

Use `"Steal"` only when replacing another server's ownership is intentional.

---

# Updating PlayersData

If the persistent schema changes, increase `DataTemplate.Version`.

Old:

```lua
local PlayersDataV1 = {
    Coins = 0,
    Rebirths = 0,
}
```

New:

```lua
local PlayersData = {
    Coins = 0,
    Rebirths = 0,

    Gems = 0,
    Diamonds = 0,
    Level = 1,
}
```

Update:

```lua
DataTemplate = {
    Version = 2,
    Data = PlayersData,
}
```

Then provide the old template:

```lua
DataTemplateHistory = {
    [1] = PlayersDataV1,
}
```

Do **not** keep using the same DataTemplate version after changing an IndexedSchema layout.

---

# DataTemplateHistory

`IndexedSchema` intentionally does not transmit root field names and descriptors with every player save.

That is one reason it is compact.

The tradeoff is that an old layout must be available when decoding an old save.

Example:

```lua
local PlayersDataV1 = {
    Coins = 0,
    Rebirths = 0,
}

local Store = DataStore.new({
    Name = "ClickStore5",

    DataTemplate = {
        Version = 2,
        Data = PlayersData,
    },

    DataTemplateHistory = {
        [1] = PlayersDataV1,
    },
})
```

The historical template is server-side code.

It is not copied into every player's persistent buffer.

## Why it is required

Suppose version 1 saved:

```lua
{
    Coins = 5000,
    Rebirths = 12,
}
```

and version 2 contains 100 fields.

Without the old layout, the decoder knows the saved schema version but does not know which positional fields the old bits represented.

With:

```lua
DataTemplateHistory[1]
```

the DataStore can reconstruct the old layout exactly.

---

# Schema Version Routing

DataStore maps its versions to Compression schema versions as:

```text
Compression schema version = DataTemplate.Version + 1
```

Examples:

```text
DataTemplate version 0 -> Compression schema 1
DataTemplate version 1 -> Compression schema 2
DataTemplate version 2 -> Compression schema 3
DataTemplate version 3 -> Compression schema 4
```

The Compression build exposes:

```lua
Compression.SchemaPacketVersion(buffer)
```

The DataStore uses the embedded schema version before performing a full decode.

Example:

```text
stored schema version = 2
        |
        v
DataTemplate version = 1
        |
        v
DataTemplateHistory[1]
        |
        v
decode old data
```

This avoids decoding an old bitstream with a newer 100-field layout.

---

# Reconciliation

Default:

```lua
Reconcile = true
```

Reconciliation only fills missing fields.

Given the new template:

```lua
{
    Coins = 0,
    Rebirths = 0,
    Gems = 0,
}
```

and old decoded data:

```lua
{
    Coins = 5000,
    Rebirths = 12,
}
```

the reconciled profile becomes:

```lua
{
    Coins = 5000,
    Rebirths = 12,
    Gems = 0,
}
```

Existing values are preserved.

Defaults are copied only for missing keys.

When reconciliation changes the loaded profile, the profile is considered migrated/dirty and can be rewritten with the newest schema.

---

# Persistent Validation

The module validates data before saving.

It rejects or limits:

- circular tables;
- NaN and infinity;
- unsupported Roblox/Luau values;
- unsupported table-key types;
- keyed/numeric table shape conflicts;
- sparse numeric arrays;
- excessive table depth;
- excessive entry counts;
- keyed fields not declared by the template;
- fields whose runtime type changed from the template type.

Supported scalar values include:

- booleans;
- finite numbers;
- strings;
- buffers;
- `Vector2`;
- `Vector3`;
- `Color3`;
- `CFrame`;
- `UDim`;
- `UDim2`;
- `Rect`;
- `NumberRange`;
- `BrickColor`;
- `DateTime`.

Tables must remain compatible with the declared persistent shape.

---

# Compact Player Keys

Player keys use a compact Base85 unsigned-integer representation.

The alphabet contains 85 characters.

The permanent key is generated from the numeric UserId.

There is no need to store:

```text
Player_10800269681
```

as the actual key string.

Inspect a key with:

```lua
local info = Store:GetKeyInfo(player)

print("UserId:", info.UserId)
print("Key:", info.Key)
print("Key bytes:", info.KeyBytes)
print("Plain bytes:", info.PlainKeyBytes)
print("Saved bytes:", info.SavedBytes)
print("Savings:", info.SavingsPercent)
print("Codec:", info.Codec)
```

Current codec label:

```text
Base85UInt
```

The player key is separate from the player-data buffer.

---

# Diagnostics

## Profile storage info

```lua
local info = profile:GetStorageInfo()

print("Version:", info.Version)
print("Player key:", info.PlayerKey)
print("Stored bytes:", info.StoredBytes)
print("Raw bytes:", info.RawBytes)
print("Saved bytes:", info.SavedBytes)
print("Savings:", info.SavingsPercent)
print("Codec:", info.Codec)
print("Useful bits:", info.UsefulBits)
print("Physical bits:", info.PhysicalBits)
print("Padding bits:", info.PaddingBits)
print("Dirty:", info.Dirty)
print("Revision:", info.Revision)
```

These values are diagnostics.

They are not inserted into the permanent player buffer.

## Runtime statistics

```lua
local stats = Store:GetRuntimeStats()

print("Loads:", stats.Loads)
print("LoadFailures:", stats.LoadFailures)
print("Saves:", stats.Saves)
print("SaveFailures:", stats.SaveFailures)
print("Autosaves:", stats.Autosaves)
print("SessionRefreshes:", stats.SessionRefreshes)
print("SessionRefreshFailures:", stats.SessionRefreshFailures)
print("SessionLosses:", stats.SessionLosses)
print("BytesWritten:", stats.BytesWritten)
```

## Compression layout info

```lua
local info = Store:GetCompressionLayoutInfo()

print("Available:", info.Available)
print("DataVersion:", info.DataVersion)
print("LayoutVersion:", info.LayoutVersion)
print("Mode:", info.Mode)
print("FieldCount:", info.FieldCount)

for _, version in info.HistoricalVersions do
    print("Historical version:", version)
end
```

---

# Exact Stored Buffer

To inspect the literal value returned from Roblox DataStore:

```lua
local storedBuffer, errorMessage =
    Store:GetStoredBufferAsync(player)

if storedBuffer ~= nil then
    print("Payload bytes:", buffer.len(storedBuffer))
else
    warn(errorMessage)
end
```

This is the closest module-level value to compare with a storage inspector that reports `buffer.len()`.

Roblox Creator Hub accounting can include platform-side representation costs that are not the same thing as the raw Luau buffer length.

---

# Read-Only Inspection

## View template

```lua
local dataTemplate, errorMessage =
    Store:ViewTemplateAsync(player.UserId)

if dataTemplate ~= nil then
    print(dataTemplate.Version)
    print(dataTemplate.Data.Coins)
else
    warn(errorMessage)
end
```

## View data only

```lua
local playerData, version, errorMessage =
    Store:ViewAsync(player.UserId)

if playerData ~= nil then
    print(version)
    print(playerData.Coins)
else
    warn(errorMessage)
end
```

These methods do not create an active profile.

---

# Session Inspection

```lua
local session, errorMessage =
    Store:GetSessionLockInfoAsync(player)

if session ~= nil then
    print("Id:", session.Id)
    print("Released:", session.Released)
    print("Bytes:", session.Bytes)
    print("Codec:", session.Codec)
else
    warn(errorMessage)
end
```

This describes MemoryStore session ownership, not permanent player progression.

---

# Signals

## Profile Changed

```lua
profile.Changed:Connect(function(key, newValue, oldValue)
    print("Changed:", key, oldValue, "->", newValue)
end)
```

Multi-field operations may use `key == nil`.

## Profile Saved

```lua
profile.Saved:Connect(function(storageInfo)
    print("Saved:", storageInfo.StoredBytes)
end)
```

## Profile Released

```lua
profile.Released:Connect(function(reason)
    print("Released:", reason)
end)
```

## Store ProfileLoaded

```lua
Store.ProfileLoaded:Connect(function(profile)
    print("Loaded:", profile.UserId)
end)
```

## Store ProfileReleased

```lua
Store.ProfileReleased:Connect(function(profile, reason)
    print("Released:", profile.UserId, reason)
end)
```

## Store Issue

```lua
Store.Issue:Connect(function(kind, ...)
    warn("[DataStore Issue]", kind, ...)
end)
```

---

# Configuration Reference

| Option | Default | Description |
|---|---:|---|
| `Name` | required | Roblox DataStore name |
| `Scope` | `nil` | Optional DataStore scope |
| `DataTemplate` | required | Current `{Version, Data}` template |
| `DataTemplateHistory` | `{}` | Old templates keyed by old DataTemplate version |
| `Reconcile` | `true` | Fill missing fields after decode |
| `AutoSave` | `true` | Enable automatic saving |
| `AutoSaveInterval` | `60` | Target autosave interval |
| `SaveOnlyDirty` | `true` | Skip unchanged profiles |
| `SaveOnRelease` | `true` | Save dirty data before releasing |
| `SessionLocking` | `true` | Enable MemoryStore session ownership |
| `SessionLockTimeout` | `180` | Session lock TTL |
| `SessionRefreshInterval` | `60` | MemoryStore heartbeat interval |
| `LoadTimeout` | `30` | Maximum load/session wait |
| `LockRetryInterval` | `1` | Wait-mode retry interval |
| `MemoryLockRetryAttempts` | `4` | MemoryStore retry count |
| `RetryAttempts` | `5` | DataStore retry count |
| `RetryDelay` | `0.75` | Initial DataStore retry delay |
| `MaxRetryDelay` | `8` | Maximum retry delay |
| `ShutdownTimeout` | `25` | Maximum shutdown wait |
| `BudgetAware` | `true` | Respect DataStore request budget |
| `BudgetWaitTimeout` | `10` | Maximum budget wait |
| `CompressionCompressStrings` | `true` | Enable string compression |
| `CompressionStringStrategy` | `"Auto"` | String codec strategy |
| `CompressionUseStringDictionary` | `true` | Enable string dictionary |
| `CompressionHomogeneousArrays` | `true` | Optimize homogeneous arrays |
| `CompressionDeltaArrays` | `true` | Enable delta arrays |
| `CompressionRunLengthArrays` | `true` | Enable run-length arrays |
| `CompressionCompactMapKeys` | `true` | Compact map keys |
| `CompressionTableKeyMapping` | `true` | Enable mapped table keys |
| `CompressionTableStrategy` | `"Auto"` | Table codec strategy |
| `CompressionEntropyCoding` | `true` | Enable entropy coding |
| `CompressionEntropyStrategy` | `"Auto"` | Entropy strategy |
| `CompressionAllowExpansion` | `false` | Avoid selecting expanding compression |
| `CompressionBufferStrategy` | `"Auto"` | Buffer codec strategy |
| `CompressionBufferMinLength` | `6` | Minimum buffer length considered |
| `CompressionBufferSearchDepth` | `32` | Buffer search depth |
| `CompressionBufferWindowSize` | `32767` | Buffer search window |
| `CompressionBufferMaxMatch` | `66` | Maximum match length |
| `MaxBufferBytes` | `3800000` | Maximum encoded player buffer |
| `MaxDepth` | `64` | Maximum persistent table depth |
| `MaxTableEntries` | `100000` | Maximum validated entries |
| `Debug` | `false` | Enable debug warnings |

---

# Store API

## Construction

```lua
DataStore.new(config)
```

## Active profiles

```lua
Store:GetProfile(subject)
Store:OpenPlayerAsync(subject, options?)
Store:GetLoadedProfiles()
```

## Read-only stored data

```lua
Store:ViewTemplateAsync(subject)
Store:ViewAsync(subject)
Store:GetStoredBufferAsync(subject)
Store:GetStoredPayloadAsync(subject)
```

## Session ownership

```lua
Store:GetSessionLockInfoAsync(subject)
```

## Save and release

```lua
Store:SavePlayerAsync(subject)
Store:ReleasePlayerAsync(subject, reason?)
Store:FlushAsync()
Store:CloseAsync()
```

## Diagnostics

```lua
Store:IsClosed()
Store:GetRuntimeStats()
Store:GetKeyInfo(subject)
Store:GetCompressionLayoutInfo()
```

---

# Profile API

```lua
profile:IsActive()
profile:IsDirty()

profile:Get(key)
profile:GetDataCopy()
profile:GetDataTemplate()
profile:GetBuffer()
profile:GetStorageInfo()

profile:MarkDirty()
profile:Set(key, value)
profile:Update(key, callback)
profile:Increment(key, amount?)
profile:Overwrite(data)
profile:Reconcile()
profile:Mutate(callback)

profile:SaveAsync()
profile:ReleaseAsync(reason?)
```

---

# Static API

## DataTemplate compression

```lua
local packet = DataStore.CompressDataTemplate({
    Version = 2,
    Data = PlayersData,
})

print(buffer.len(packet.Data))
```

To decode:

```lua
local decoded = DataStore.DecompressDataTemplate(
    packet.Data,
    {
        DataTemplate = {
            Version = 2,
            Data = PlayersData,
        },

        DataTemplateHistory = {
            [1] = PlayersDataV1,
        },
    }
)
```

## Generic encoding

```lua
local encoded = DataStore.Encode(value)
local decoded = DataStore.Decode(encoded)
```

These generic helpers are not the same as the persistent `IndexedLayout` profile path.

## UserId key codec

```lua
local key = DataStore.EncodeUserIdKey(userId)
local userIdAgain = DataStore.DecodeUserIdKey(key)
```

## Version helpers

```lua
print(DataStore.Version())
print(DataStore.FormatVersion())
print(DataStore.CompressionVersion())
print(DataStore.SessionFormatVersion)
```

Expected for this release:

```text
DataStore.Version()       = 4.1.1
DataStore.FormatVersion() = 12
CompressionVersion()      = 3.1.0
SessionFormatVersion      = 5
```

---

# Compression SchemaPacketVersion

The Sparse Defaults Compression build exposes:

```lua
local schemaVersion =
    Compression.SchemaPacketVersion(packetOrBuffer)
```

It reads only the schema/delta header.

It does not need to decode all fields just to discover which DataTemplate layout produced the payload.

For DataStore persistence:

```text
schema 2 -> DataTemplate 1
schema 3 -> DataTemplate 2
schema 4 -> DataTemplate 3
```

This API is important for migration routing.

---

# Testing

## 400-key test

Use:

```text
PlayersData400.luau
SparseDefaults_400Keys_Test.server.luau
```

The script checks:

```text
400 keys - all defaults
400 keys - 1 changed
400 keys - 10 changed
400 keys - 100 changed
400 keys - all 400 changed
```

It prints:

```text
Keys
Changed Keys
Codec
Bytes
buffer.len
Bits
Useful Bits
Physical Bits
Padding Bits
Raw Bytes
Saved Bytes
Savings
Schema Version
Buffer bytes
Round Trip
```

It also benchmarks repeated encode/decode operations.

## What to verify

Every case should print:

```text
Round Trip: true
```

For the all-default flat 400-field schema, the Sparse Defaults frame is designed to fit in about:

```text
2 bytes
```

for schema version 3 before any Roblox platform-side accounting.

## Migration test

A migration test should:

1. save using version 1;
2. stop the server;
3. change to version 2;
4. keep `DataTemplateHistory[1]`;
5. rejoin;
6. verify old values remain;
7. verify new fields receive defaults;
8. save;
9. rejoin again;
10. verify the player now loads directly through version 2.

## Production test matrix

Before deploying a live game, test:

- first join;
- normal save;
- leave/rejoin;
- server shutdown;
- dirty-only autosave;
- session lock contention;
- killed-server lock expiry;
- historical template migration;
- 100-key default profile;
- 400-key default profile;
- several changed fields;
- all fields changed;
- malformed/corrupt buffer handling;
- DataStore budget pressure;
- long-running servers.

---

# Production Safety

## Never trust client-provided progression

Bad:

```lua
RemoteEvent.OnServerEvent:Connect(function(player, coins)
    profile:Set("Coins", coins)
end)
```

Better:

```lua
RemoteEvent.OnServerEvent:Connect(function(player)
    local profile = Store:GetProfile(player)

    if profile == nil then
        return
    end

    profile:Increment("Coins", 1)
end)
```

The server should decide what persistent changes are valid.

## Do not replace decode failures with blank profiles

If a real stored profile cannot be decoded, stop player initialization.

Silently replacing it with defaults can destroy progression on the next save.

## Keep DataTemplateHistory while it is needed

Do not delete:

```lua
DataTemplateHistory[1]
```

while version-1 IndexedSchema saves still exist.

Once every live player entry has been migrated and rewritten, old historical templates can be retired deliberately.

## Keep data bounded

Compression does not remove Roblox's DataStore limits.

Inventories, strings, arrays, and nested tables should still have intentional caps.

---

# FAQ

## Why did I see lots of zero bytes?

Because the previous default-eliding bitmap wrote one state bit for every defaulted field.

Hundreds of `0` state bits become physical zero bytes after bit packing.

Sparse Defaults removes that per-field cost when few fields differ from defaults.

## Does a stored `0` always cost one byte?

No.

For a schema-known default, the value itself may consume no value payload at all.

Sparse Defaults can also remove the old per-field state bit.

## Can an all-default 400-key profile really stay around 2 bytes?

For the current flat defaulted schema and schema version 3, the sparse bit layout fits into 2 physical bytes.

That is the raw Compression payload.

Creator Hub may report a different storage/accounting number.

## Does Sparse Defaults remove changed values?

No.

Only unchanged default fields are omitted.

Changed values still have to be encoded.

## Is Sparse always used?

No.

Compression compares sparse and bitmap candidates and chooses the smaller physical representation.

## Can the payload be zero bytes?

Not safely for this versioned schema design.

The decoder still needs enough information to identify the frame and schema version.

## Are old bitmap saves still readable?

Yes.

The original `0xD1` schema frame remains supported.

Sparse Defaults uses a different frame marker.

## Why do I need DataTemplateHistory?

Because IndexedSchema intentionally avoids writing field names/types into every player payload.

The schema version can identify **which** historical layout is needed, but the exact old layout still has to exist in server code.

## Does reconciliation reset Coins or Rebirths?

No.

Reconciliation fills only missing fields.

Existing decoded values are preserved.

## What causes `schema version mismatch`?

Usually a payload is being decoded with a layout compiled for a different DataTemplate version.

v4.1.1 avoids this by reading the stored schema version first and routing to the matching current or historical template.

## Is the DataTemplate version stored as a wrapper field?

No.

The player value is still a raw Compression buffer.

The Compression schema header contains the schema version used for routing.

## Is the session lock stored inside player data?

No.

Session ownership lives in MemoryStore.

## Are `Dirty`, `Revision`, and `LastSaveClock` persisted?

No.

They are runtime profile state.

## Is the player key stored inside the player buffer?

No.

Roblox receives the key and value separately.

## Does the DataStore use Base62 keys?

No.

The current v4.1.1 build uses `Base85UInt`.

## Should I bump DataTemplate.Version when adding keys?

Yes.

For an IndexedSchema persistence format, changing the persistent layout should use a new DataTemplate version.

Keep the previous layout in `DataTemplateHistory` until old saves are migrated.

---

# Release Summary

DataStore v4.1.1 keeps a narrow permanent persistence contract:

```text
PlayersData
    |
    v
Compression.IndexedLayout
    |
    +--> Bitmap IndexedSchema
    |
    `--> Sparse Defaults IndexedSchema
             |
             v
       smaller candidate
             |
             v
      Roblox DataStore
```

Historical loads use:

```text
stored schema version
        |
        v
DataTemplate version
        |
        v
current template
or DataTemplateHistory
        |
        v
decode
        |
        v
reconcile
        |
        v
rewrite newest schema
```

The result is designed for large simulator-style templates where most fields remain at known defaults.

A 400-key profile does not need to spend hundreds of bits simply proving that hundreds of values are still `0`.

Changed progression is encoded.

Unchanged defaults are reconstructed from the schema.

Session ownership stays in MemoryStore.

Runtime diagnostics stay in memory.

The permanent player value remains only the compact player-data buffer.
