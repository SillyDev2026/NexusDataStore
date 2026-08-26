# DataStore

![Version](https://img.shields.io/badge/version-v1.7.1-4c8bf5)
![Language](https://img.shields.io/badge/language-Luau-00A2FF)
![Platform](https://img.shields.io/badge/platform-Roblox-111111)
![Runtime](https://img.shields.io/badge/runtime-server--only-orange)
![Storage Format](https://img.shields.io/badge/storage%20format-v5-2ea44f)
![Compression](https://img.shields.io/badge/compression-v2.6.4-6f42c1)

**DataStore v1.7.1** is a server-side Roblox persistence module with player profile sessions, MemoryStore session locking, autosave, retries, budget awareness, migrations, reconciliation, validation, and adaptive compressed buffer storage.

The v1.7 storage pipeline integrates **Compression v2.6.4** directly with the player `DataTemplate`. Instead of always serializing a table into the older DataStore buffer format first, v1.7 can let Compression inspect the original table structure and choose a better representation.

> Current release: **v1.7.1**  
> Storage format: **5**  
> Required Compression version: **2.6.4**

---

# What's New in v1.7.1

v1.7.1 is a correctness and organization update on top of the v1.7 compression upgrade.

- fixed local helper ordering so compression helpers are declared before they are used;
- keeps the v1.7 adaptive table-first compression path;
- requires Compression v2.6.4;
- keeps legacy BufferV1/SDSB decoding for older stored data;
- compares native table compression against the older BufferV1 path when configured;
- exposes compression version and storage-format information through the public API;
- keeps profile storage statistics available through `Profile:GetStorageInfo()`.

---

# How Storage Works

With the default `StorageMode = "Buffer"`, v1.7.1 evaluates the profile as a versioned `DataTemplate`:

```text
{
    Version = <data version>,
    Data = <player data>
}
```

The save path can evaluate multiple candidates:

```text
DataTemplate
    │
    ├── Legacy raw BufferV1 / SDSB
    │
    ├── Legacy BufferV1 + Compression v2.6.4 buffer compression
    │
    └── Compression v2.6.4 native adaptive table compression
                    │
                    ▼
              smallest result
                    │
                    ▼
             DataStoreService
```

With the default:

```lua
CompressionCompareLegacyBuffer = true
```

the module keeps the old encoded-buffer path as a size safety net while also testing the newer table-aware Compression path.

This is useful because Compression can see table keys, integers, strings, arrays, nested values, and supported Roblox datatypes before the DataStore's legacy serializer turns everything into generic bytes.

---

# Requirements

DataStore v1.7.1 is **server-only**.

It requires a child ModuleScript named:

```text
Compression
```

and that module must report:

```text
2.6.4
```

Recommended layout:

```text
ServerScriptService
└── Data
    └── DataStore
        └── Compression
```

Example:

```lua
local ServerScriptService = game:GetService("ServerScriptService")

local DataStore = require(
    ServerScriptService.Data.DataStore
)
```

Do not require the module from a `LocalScript`.

---

# Quick Start

## Create a store

```lua
local ServerScriptService = game:GetService("ServerScriptService")
local Players = game:GetService("Players")

local DataStore = require(
    ServerScriptService.Data.DataStore
)

local Store = DataStore.new({
    Name = "PlayersData",

    DataTemplate = {
        Version = 1,

        Data = {
            Coins = 0,
            Level = 10,
            Xp = 400,
            Rebirths = 13,
        },
    },

    StorageMode = "Buffer",
    CompressionEnabled = true,

    AutoSave = true,
    AutoSaveInterval = 60,

    SessionLocking = true,
    SessionLockTimeout = 180,

    BudgetAware = true,
})
```

## Open player profiles

```lua
Players.PlayerAdded:Connect(function(player)
    local profile, err = Store:OpenPlayerAsync(player)

    if not profile then
        warn(
            "[DataStore] load failed:",
            player.Name,
            err
        )

        player:Kick(
            "Your data could not be loaded. Please rejoin."
        )

        return
    end

    print(
        "[DataStore] loaded:",
        player.Name
    )

    print("Coins:", profile.Data.Coins)
end)
```

`DataStore.new()` already installs internal `Players.PlayerRemoving` and `game:BindToClose()` handling.

You normally do **not** need to create a second `PlayerRemoving` or `BindToClose` handler just to release profiles.

---

# Reading and Updating Data

A loaded profile exposes its live data through:

```lua
profile.Data
```

For tracked mutations, prefer the profile methods.

## Get

```lua
local coins = profile:Get("Coins")
```

## Set

```lua
profile:Set("Coins", 500)
```

## Increment

```lua
profile:Increment("Coins", 100)
```

Default increment:

```lua
profile:Increment("Coins")
```

is equivalent to adding `1`.

## Update

```lua
profile:Update("Coins", function(current)
    return (current or 0) * 2
end)
```

## Overwrite the entire data table

```lua
profile:Overwrite({
    Coins = 0,
    Level = 1,
    Xp = 0,
    Rebirths = 0,
})
```

## Reconcile against the template

```lua
profile:Reconcile()
```

Reconciliation fills missing map fields from the configured template.

---

# Saving

## Manual save

```lua
local success, err = profile:SaveAsync()

if not success then
    warn("Save failed:", err)
end
```

Store equivalent:

```lua
local success, err = Store:SavePlayerAsync(player)
```

## Autosave

Autosave is enabled by default:

```lua
AutoSave = true
AutoSaveInterval = 60
```

`AutoSaveInterval` must be at least `10` seconds.

The autosave loop spreads profile saves over the configured interval instead of attempting to save every loaded profile at exactly the same moment.

---

# Releasing Profiles

Release a profile manually when necessary:

```lua
local success, err = profile:ReleaseAsync("ManualRelease")

if not success then
    warn(err)
end
```

Store equivalent:

```lua
Store:ReleasePlayerAsync(
    player,
    "ManualRelease"
)
```

`ReleaseAsync()` saves the profile before releasing its MemoryStore session lock.

The store also performs release handling automatically when a player leaves.

---

# Session Locking

Session locking is enabled by default:

```lua
SessionLocking = true
SessionLockTimeout = 180
```

Locks are stored in `MemoryStoreService`.

The lock identifies the current session and is refreshed during saves.

`SessionLockTimeout` must be at least:

```text
2 × AutoSaveInterval
```

For the default autosave interval of `60`, the default timeout of `180` satisfies this requirement.

---

# Lock Modes

`OpenPlayerAsync()` supports a lock behavior through `options.Locked`.

## Wait

Default:

```lua
local profile, err = Store:OpenPlayerAsync(player, {
    Locked = "Wait",
})
```

The loader retries until the profile becomes available or `LoadTimeout` is reached.

## Cancel

```lua
local profile, err = Store:OpenPlayerAsync(player, {
    Locked = "Cancel",
})
```

Returns immediately when another session owns the lock.

## Steal

```lua
local profile, err = Store:OpenPlayerAsync(player, {
    Locked = "Steal",
})
```

Attempts to replace the existing lock.

Use lock stealing carefully. It can invalidate another live server's ownership.

---

# Loading an Existing Profile

```lua
local profile, err = Store:OpenPlayerAsync(player)
```

Alias:

```lua
local profile, err = Store:LoadPlayerAsync(player)
```

If the profile is already active in this store, the existing profile object is returned.

A failed load returns `nil` and an error value.

Do not replace a failed load with empty player data and continue saving under the same key.

---

# Getting an Active Profile

```lua
local profile = Store:GetProfile(player)

if profile and profile:IsActive() then
    print(profile.Data)
end
```

A numeric positive integer UserId can also be used where the module accepts a player subject.

---

# DataTemplate and Versions

Recommended configuration:

```lua
DataTemplate = {
    Version = 1,

    Data = {
        Coins = 0,
        Level = 1,
    },
}
```

The module internally stores the version together with the data.

You can also use the older separate style:

```lua
local Store = DataStore.new({
    Name = "PlayersData",

    Template = {
        Coins = 0,
        Level = 1,
    },

    DataVersion = 1,
})
```

`DataTemplate` is recommended because the version and default data remain together.

---

# Migrations

Use `Migrations` to upgrade older player data.

The migration table is indexed by the **target version**.

```lua
local Store = DataStore.new({
    Name = "PlayersData",

    DataTemplate = {
        Version = 3,

        Data = {
            Coins = 0,
            Gems = 0,

            Stats = {
                Level = 1,
            },
        },
    },

    Migrations = {
        [2] = function(data, fromVersion, toVersion)
            data.Gems = data.Gems or 0
            return data
        end,

        [3] = function(data, fromVersion, toVersion)
            data.Stats = data.Stats or {
                Level = 1,
            }

            return data
        end,
    },
})
```

A migration may mutate the supplied table and return `nil`, or return a replacement table.

If stored data has a newer version than the configured version and:

```lua
RejectFutureDataVersion = true
```

loading is rejected.

---

# Reconciliation

Enabled by default:

```lua
Reconcile = true
```

After loading and migrations, missing fields are copied from the configured template.

Example template:

```lua
{
    Coins = 0,

    Settings = {
        Music = true,
        SFX = true,
    },
}
```

If an older save does not contain `Settings.SFX`, reconciliation adds it.

Dense array templates are not recursively reconciled as map templates.

---

# Compression

Compression is enabled by default:

```lua
CompressionEnabled = true
```

v1.7.1 requires **Compression v2.6.4**.

The primary table settings are:

```lua
CompressionTableStrategy = "Auto"

CompressionCompressStrings = true
CompressionStringStrategy = "Auto"
CompressionUseStringDictionary = true

CompressionHomogeneousArrays = true
CompressionDeltaArrays = true
CompressionRunLengthArrays = true

CompressionCompactMapKeys = true
CompressionTableKeyMapping = true

CompressionEntropyCoding = true
CompressionEntropyStrategy = "Auto"

CompressionAllowExpansion = false

CompressionCompareLegacyBuffer = true
```

For normal DataStore usage, the recommended strategy is:

```lua
"Auto"
```

This lets Compression choose the representation appropriate for the current profile instead of forcing one codec on every player's data.

---

# Table Compression Strategies

```lua
CompressionTableStrategy = "Auto"
```

Supported values:

```text
Auto
Compact
Dynamic
```

### Auto

Lets Compression compare supported table representations and choose automatically.

### Compact

Prefers the compact table encoder when possible.

### Dynamic

Uses the dynamic typed table encoding path.

For general player profiles, `Auto` is recommended.

---

# String Compression Strategies

```lua
CompressionStringStrategy = "Auto"
```

Supported values:

```text
Auto
Raw
LZ
ASCII7
Identifier6
Numeric4
```

Unless your stored strings have a very predictable format, keep this set to `Auto`.

---

# Buffer Compression Strategies

```lua
CompressionBufferStrategy = "Auto"
```

Supported values:

```text
Auto
Raw
LZ
Sparse
Nibble
```

These settings are used for nested buffers and for the legacy BufferV1 comparison path.

Default buffer tuning:

```lua
CompressionMinBufferBytes = 16
CompressionMinSavingsBytes = 1

CompressionBufferMinLength = 6
CompressionBufferSearchDepth = 32
CompressionBufferWindowSize = 32767
CompressionBufferMaxMatch = 66
```

---

# Entropy Coding

Default:

```lua
CompressionEntropyCoding = true
CompressionEntropyStrategy = "Auto"
```

Supported strategies:

```text
Auto
Huffman
None
```

`Auto` is recommended because entropy coding is only useful when its total encoded form is actually beneficial.

---

# Legacy Storage Compatibility

v1.7.1 keeps decoding support for older DataStore formats.

The loader can handle:

- v1.7 native Compression v2.6.4 table buffers;
- legacy raw BufferV1/SDSB buffers;
- legacy BufferV1 data wrapped in Compression buffer compression;
- legacy table records supported by the module;
- raw legacy table values.

This allows existing data to be loaded and then written back using the current v1.7 storage selection path.

Do not remove the legacy decoder until you are certain no production keys still depend on it.

---

# Storage Modes

## Buffer

Default and recommended:

```lua
StorageMode = "Buffer"
```

Supports compressed DataTemplate storage and the supported Roblox datatypes listed below.

## Table

```lua
StorageMode = "Table"
```

Stores a normal copied DataTemplate table instead of the compressed buffer path.

Some Roblox datatypes require `Buffer` storage.

---

# Supported Persistent Values

The v1.7.1 validator supports:

- `nil`;
- booleans;
- finite numbers;
- strings;
- buffers;
- dense arrays;
- string-keyed map tables;
- `Vector2`;
- `Vector3`;
- `Color3`;
- `CFrame`;
- `UDim`;
- `UDim2`.

Tables cannot be circular.

A table cannot mix string keys and numeric array keys.

Numeric arrays must be dense and use positive integer indexes starting from `1`.

When `StorageMode = "Table"`, strings and string table keys must be valid UTF-8.

---

# Storage Limits

Defaults:

```lua
MaxBufferBytes = 3800000
MaxDepth = 64
MaxTableEntries = 100000
```

`MaxBufferBytes` protects the encoded buffer path from exceeding the configured storage limit.

`MaxDepth` limits nested tables.

`MaxTableEntries` limits the total number of validated table entries.

Keep player profiles intentionally bounded even when compression is effective.

---

# Storage Information

After a successful save:

```lua
local info = profile:GetStorageInfo()

print("Mode:", info.Mode)
print("Version:", info.Version)

print("Raw bytes:", info.LastRawBufferBytes)
print("Stored bytes:", info.LastBufferBytes)

print(
    "Saved bytes:",
    info.LastCompressionSavedBytes
)

print(
    "Savings:",
    info.LastCompressionSavingsPercent
)

print(
    "Compressed:",
    info.LastBufferCompressed
)

print(
    "Codec:",
    info.LastCompressionMode
)

print(
    "Compression version:",
    info.CompressionVersion
)

print(
    "Storage format:",
    info.StorageFormatVersion
)
```

Important:

`LastRawBufferBytes` is the size of the module's legacy raw BufferV1/SDSB baseline used for comparison. It is **not** a measurement of Luau heap memory.

---

# Example Compression Result Test

```lua
Players.PlayerAdded:Connect(function(player)
    local profile, err = Store:OpenPlayerAsync(player)

    if not profile then
        warn(
            "[DataStore] load failed:",
            player.Name,
            err
        )

        player:Kick(
            "Your data could not be loaded. Please rejoin."
        )

        return
    end

    profile:Set(
        "Coins",
        profile.Data.Coins + 100
    )

    local success, saveErr =
        profile:SaveAsync()

    if not success then
        warn(
            "[DataStore] save failed:",
            saveErr
        )

        return
    end

    local info =
        profile:GetStorageInfo()

    print(
        "Raw Bytes:",
        info.LastRawBufferBytes
    )

    print(
        "Stored Bytes:",
        info.LastBufferBytes
    )

    print(
        "Saved Bytes:",
        info.LastCompressionSavedBytes
    )

    print(
        "Savings:",
        string.format(
            "%.2f%%",
            info.LastCompressionSavingsPercent
        )
    )

    print(
        "Codec:",
        info.LastCompressionMode
    )
end)
```

---

# Profile Signals

Each loaded profile contains:

```lua
profile.Changed
profile.Saved
profile.Released
```

## Changed

```lua
profile.Changed:Connect(function(
    key,
    newValue,
    oldValue
)
    print(
        "Changed:",
        key,
        oldValue,
        "->",
        newValue
    )
end)
```

For whole-table operations such as `Overwrite()` and `Reconcile()`, the key is `nil`.

## Saved

```lua
profile.Saved:Connect(function(storageInfo)
    print(
        "Stored bytes:",
        storageInfo.LastBufferBytes
    )
end)
```

## Released

```lua
profile.Released:Connect(function(reason)
    print("Released:", reason)
end)
```

---

# Store Signals

A store exposes:

```lua
Store.ProfileLoaded
Store.ProfileReleased
Store.Issue
```

## ProfileLoaded

```lua
Store.ProfileLoaded:Connect(function(profile)
    print("Loaded:", profile.UserId)
end)
```

## ProfileReleased

```lua
Store.ProfileReleased:Connect(function(
    profile,
    reason
)
    print(
        "Released:",
        profile.UserId,
        reason
    )
end)
```

## Issue

`Issue` reports operational problems.

```lua
Store.Issue:Connect(function(
    issueType,
    ...
)
    warn(
        "[DataStore Issue]",
        issueType,
        ...
    )
end)
```

Issue names used by the module include conditions such as:

```text
LoadFailed
DecodeFailed
MigrationFailed
InvalidLoadedData
SessionLost
SaveFailed
AutoSaveFailed
ViewDecodeFailed
```

---

# Viewing Data Without Opening a Session

## View the full DataTemplate

```lua
local dataTemplate, source =
    Store:ViewTemplateAsync(userId)

if dataTemplate then
    print(dataTemplate.Version)
    print(dataTemplate.Data)
end
```

## View only player data

```lua
local data, version, source =
    Store:ViewAsync(userId)

if data then
    print("Version:", version)
    print(data)
end
```

These functions read stored data without creating an active profile session.

Use them for diagnostics or tooling, not as a replacement for normal session ownership during gameplay.

---

# Inspecting Stored Values

## Exact stored payload

```lua
local payload, payloadType =
    Store:GetStoredPayloadAsync(userId)

print(payloadType)
```

This returns a copy of the value currently stored under the player key when possible.

## Buffer-oriented inspection

```lua
local value, err =
    Store:GetStoredBufferAsync(userId)
```

Use `GetStoredPayloadAsync()` when you specifically need to know whether the actual stored value is a `buffer`, `table`, or another legacy value.

---

# Manual Compression Helpers

These helpers are useful for testing and tooling.

## Compress a DataTemplate

```lua
local packet =
    DataStore.CompressDataTemplate({
        Version = 1,

        Data = {
            Coins = 0,
            Level = 10,
            Xp = 400,
            Rebirths = 13,
        },
    })

print(packet.Bytes)
print(packet.Codec)
```

The function returns the Compression packet.

Its encoded buffer is:

```lua
packet.Data
```

## Decompress a DataTemplate

```lua
local decoded =
    DataStore.DecompressDataTemplate(
        packet.Data
    )

print(decoded.Version)
print(decoded.Data.Coins)
```

---

# Legacy Buffer Helpers

## Encode using the DataStore BufferV1 codec

```lua
local rawBuffer =
    DataStore.Encode(data)
```

## Decode BufferV1

```lua
local decoded =
    DataStore.Decode(rawBuffer)
```

## Compress a raw buffer

```lua
local packed, compressed, stats =
    DataStore.CompressStorageBuffer(
        rawBuffer
    )
```

## Decompress a storage buffer

```lua
local raw =
    DataStore.DecompressStorageBuffer(
        packed
    )
```

These helpers exist primarily for compatibility, testing, and storage analysis.

Normal player saving already chooses the storage path internally.

---

# Public Version Helpers

```lua
print(
    DataStore.Version()
)
```

Returns:

```text
1.7.1
```

Storage format:

```lua
print(
    DataStore.FormatVersion()
)
```

Returns:

```text
5
```

Compression:

```lua
print(
    DataStore.CompressionVersion()
)
```

Returns:

```text
2.6.4
```

---

# Configuration Reference

| Option | Default | Description |
|---|---:|---|
| `Name` | required | Roblox DataStore name |
| `Scope` | `nil` | Optional DataStore scope |
| `KeyPrefix` | `"Player_"` | Prefix placed before UserIds |
| `DataTemplate.Version` | `1` | Current data version |
| `DataTemplate.Data` | `{}` | Default profile data |
| `Template` | `{}` | Legacy/separate template style |
| `DataVersion` | `1` | Legacy/separate version style |
| `Migrations` | `nil` | Target-version migration callbacks |
| `RejectFutureDataVersion` | `true` | Reject data newer than the configured version |
| `Reconcile` | `true` | Fill missing template fields after load |
| `AutoSave` | `true` | Enable autosaving |
| `AutoSaveInterval` | `60` | Autosave interval; minimum `10` |
| `SessionLocking` | `true` | Use MemoryStore profile locks |
| `SessionLockTimeout` | `180` | Lock TTL; must be at least 2× autosave interval |
| `LoadTimeout` | `30` | Maximum wait for a locked profile in Wait mode |
| `LockRetryInterval` | `1` | Delay between lock attempts |
| `MemoryLockRetryAttempts` | `4` | MemoryStore lock operation attempts |
| `RetryAttempts` | `5` | DataStore request attempts |
| `RetryDelay` | `0.75` | Base request retry delay |
| `MaxRetryDelay` | `8` | Maximum retry delay |
| `ShutdownTimeout` | `25` | Maximum shutdown release window |
| `BudgetAware` | `true` | Wait for Roblox request budget |
| `BudgetWaitTimeout` | `10` | Maximum budget wait per request attempt |
| `StorageMode` | `"Buffer"` | `"Buffer"` or `"Table"` |
| `CompressionEnabled` | `true` | Enable compressed buffer candidate selection |
| `CompressionTableStrategy` | `"Auto"` | `Auto`, `Compact`, or `Dynamic` |
| `CompressionCompressStrings` | `true` | Enable string compression |
| `CompressionStringStrategy` | `"Auto"` | String codec strategy |
| `CompressionUseStringDictionary` | `true` | Allow repeated-string dictionaries |
| `CompressionHomogeneousArrays` | `true` | Allow homogeneous array encodings |
| `CompressionDeltaArrays` | `true` | Allow delta array encodings |
| `CompressionRunLengthArrays` | `true` | Allow run-length array encodings |
| `CompressionCompactMapKeys` | `true` | Allow compact map keys |
| `CompressionTableKeyMapping` | `true` | Allow repeated key mapping |
| `CompressionEntropyCoding` | `true` | Enable entropy coding |
| `CompressionEntropyStrategy` | `"Auto"` | `Auto`, `Huffman`, or `None` |
| `CompressionAllowExpansion` | `false` | Do not intentionally choose expanding compression forms |
| `CompressionCompareLegacyBuffer` | `true` | Compare native table result with legacy buffer candidates |
| `CompressionMinBufferBytes` | `16` | Minimum raw buffer size before legacy buffer compression |
| `CompressionMinSavingsBytes` | `1` | Required savings before accepting a compressed candidate |
| `CompressionBufferStrategy` | `"Auto"` | `Auto`, `Raw`, `LZ`, `Sparse`, or `Nibble` |
| `CompressionBufferMinLength` | `6` | Buffer compression minimum length |
| `CompressionBufferSearchDepth` | `32` | Buffer match-search depth |
| `CompressionBufferWindowSize` | `32767` | Buffer search window |
| `CompressionBufferMaxMatch` | `66` | Maximum buffer match length |
| `MaxBufferBytes` | `3800000` | Maximum encoded buffer size |
| `MaxDepth` | `64` | Maximum nested table depth |
| `MaxTableEntries` | `100000` | Maximum total table entries |
| `Debug` | `false` | Enable debug warnings |

---

# Store API Reference

## Construction

```lua
DataStore.new(config)
```

## Profiles

```lua
Store:OpenPlayerAsync(subject, options?)
Store:LoadPlayerAsync(subject, options?)

Store:GetProfile(subject)

Store:SavePlayerAsync(subject)
Store:ReleasePlayerAsync(subject, reason?)
```

`subject` can be a `Player` or positive integer UserId where supported.

## Read-only stored-data inspection

```lua
Store:ViewTemplateAsync(subject)
Store:ViewAsync(subject)

Store:GetStoredBufferAsync(subject)
Store:GetStoredPayloadAsync(subject)
```

## Shutdown

```lua
Store:CloseAsync()
```

---

# Profile API Reference

```lua
profile:IsActive()
profile:IsDirty()

profile:Get(key)
profile:GetDataCopy()
profile:GetDataTemplate()

profile:Set(key, value)
profile:Update(key, callback)
profile:Increment(key, amount?)

profile:Overwrite(data)
profile:Reconcile()

profile:MarkDirty()

profile:SaveAsync()
profile:ReleaseAsync(reason?)

profile:GetBuffer()
profile:ToBuffer()

profile:GetStorageInfo()
```

---

# Static Utility API Reference

```lua
DataStore.CompressDataTemplate(
    dataTemplate,
    options?
)

DataStore.DecompressDataTemplate(
    dataBuffer,
    options?
)

DataStore.Encode(
    data,
    options?
)

DataStore.Decode(
    dataBuffer,
    options?
)

DataStore.CompressStorageBuffer(
    dataBuffer,
    options?
)

DataStore.DecompressStorageBuffer(
    dataBuffer,
    options?
)

DataStore.Version()
DataStore.FormatVersion()
DataStore.CompressionVersion()
```

The module also exposes:

```lua
DataStore.Profile
DataStore.Signal
DataStore.BufferEncoding
```

---

# Production Safety

## Keep one active profile per player

Use the store as the central owner of a player's persistent data.

Do not create independent DataStore systems for currency, inventory, progression, and settings that all attempt to own the same persistence key.

## Never trust the client

The module validates persistence structure, not gameplay intent.

The server must still validate:

- purchases;
- currency rewards;
- inventory operations;
- progression;
- permissions;
- item IDs;
- cooldowns;
- admin actions.

## Do not replace failed loads with empty data

Bad:

```lua
local profile = Store:OpenPlayerAsync(player)

if not profile then
    -- continue with fake empty data
end
```

A later save could overwrite valid existing data.

Prefer kicking the player or disabling persistent gameplay until a valid profile is loaded.

## Keep data bounded

Avoid giant histories, unlimited arrays, cached temporary state, or objects that can be rebuilt.

Compression reduces storage size. It does not make unbounded profile growth safe.

---

# Troubleshooting

## `DataStore v1.7 requires a child ModuleScript named Compression v2.6.4`

Make sure the DataStore ModuleScript contains:

```text
DataStore
└── Compression
```

and:

```lua
Compression.Version()
```

returns:

```text
2.6.4
```

## `SessionLocked`

Another session currently owns the player's MemoryStore lock.

Use the default `"Wait"` mode unless you have a specific reason to cancel or steal ownership.

## `SessionLost`

The profile could no longer refresh its lock.

The module deactivates the profile because saving under uncertain ownership is unsafe.

## Migration failure

Check the migration registered for the target version.

A migration should return a table or `nil`.

## Invalid loaded data

The decoded profile violated one of the DataStore validation rules such as:

- unsupported value type;
- circular table;
- mixed numeric/string keys;
- sparse numeric array;
- excessive depth;
- excessive entry count;
- non-finite number.

## Save is larger than expected

Inspect:

```lua
local info =
    profile:GetStorageInfo()

print(info.LastRawBufferBytes)
print(info.LastBufferBytes)
print(info.LastCompressionMode)
```

Remember that very small profiles have fixed framing/metadata overhead, so compression percentage becomes more meaningful as the profile grows.

---

# Recommended Simple Player Script

```lua
local ServerScriptService =
    game:GetService("ServerScriptService")

local Players =
    game:GetService("Players")

local DataStore = require(
    ServerScriptService.Data.DataStore
)

local Store = DataStore.new({
    Name = "PlayersData",

    DataTemplate = {
        Version = 1,

        Data = {
            Coins = 0,
            Level = 10,
            Xp = 400,
            Rebirths = 13,
        },
    },

    StorageMode = "Buffer",

    CompressionEnabled = true,
    CompressionTableStrategy = "Auto",
    CompressionEntropyStrategy = "Auto",
    CompressionCompareLegacyBuffer = true,

    AutoSave = true,
    AutoSaveInterval = 60,

    SessionLocking = true,
    SessionLockTimeout = 180,

    BudgetAware = true,
})

print(
    "DataStore:",
    DataStore.Version()
)

print(
    "Compression:",
    DataStore.CompressionVersion()
)

Players.PlayerAdded:Connect(function(player)
    local profile, err =
        Store:OpenPlayerAsync(player)

    if not profile then
        warn(
            "[DataStore] load failed:",
            player.Name,
            err
        )

        player:Kick(
            "Your data could not be loaded. Please rejoin."
        )

        return
    end

    print(
        "[DataStore] loaded:",
        player.Name
    )

    profile:Increment(
        "Coins",
        100
    )

    local success, saveErr =
        profile:SaveAsync()

    if not success then
        warn(
            "[DataStore] save failed:",
            player.Name,
            saveErr
        )

        return
    end

    local info =
        profile:GetStorageInfo()

    print(
        "Codec:",
        info.LastCompressionMode
    )

    print(
        "Raw:",
        info.LastRawBufferBytes,
        "Stored:",
        info.LastBufferBytes
    )

    print(
        "Savings:",
        string.format(
            "%.2f%%",
            info.LastCompressionSavingsPercent
        )
    )
end)
```

The store itself handles player removal and server shutdown release behavior.

---

# Release Summary

**DataStore v1.7.1**

- Storage format **5**
- Compression **2.6.4**
- adaptive table-first compression
- legacy BufferV1 comparison
- legacy save decoding
- MemoryStore session locking
- autosave
- migrations
- reconciliation
- request retries
- budget awareness
- profile mutation tracking
- storage statistics
- fixed helper declaration ordering

