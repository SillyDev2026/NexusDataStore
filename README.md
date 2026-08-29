# DataStore

![Version](https://img.shields.io/badge/version-v1.8.4-4c8bf5)
![Language](https://img.shields.io/badge/language-Luau-00A2FF)
![Platform](https://img.shields.io/badge/platform-Roblox-111111)
![Runtime](https://img.shields.io/badge/runtime-server--only-orange)
![Storage Format](https://img.shields.io/badge/storage%20format-v6-2ea44f)
![Compression](https://img.shields.io/badge/compression-v2.6.7-6f42c1)
![BufferUtil](https://img.shields.io/badge/BufferUtil-v1.1.0-8a2be2)

**DataStore v1.8.4** is a server-side Roblox persistence module with profile sessions, MemoryStore session locking, autosave, retries, budget awareness, migrations, reconciliation, validation, compact player keys, exact-size BufferUtil writers, adaptive Compression v2.6.7 storage, and the new **SchemaBuffer** codec.

The main v1.8.4 change is that a readable runtime profile such as:

```lua
{
    Rebirths = 1,
    Clicks = 2234,
}
```

does **not** need to store the strings `"Rebirths"` and `"Clicks"` for every player.

When the configured `DataTemplate` is eligible for SchemaBuffer, DataStore uses the template itself as the schema and stores only:

- the schema/data version;
- a schema fingerprint;
- a presence bitmap telling DataStore which fields differ from the template defaults;
- the changed values;
- a checksum.

On load, DataStore reconstructs the normal named table automatically.

> Current release: **v1.8.4**  
> Storage format: **6**  
> SchemaBuffer format: **1**  
> Session format: **1**  
> Required Compression: **v2.6.7**  
> Required BufferUtil: **v1.1.0**

---

# What’s New in v1.8.4

v1.8.4 focuses on reducing the amount of repeated structure written for fixed player-data templates.

Major changes:

- added the **SchemaBuffer** positional storage codec;
- removes repeated field-name strings from eligible player saves;
- removes generic per-value type tags when the template already defines the type;
- omits fields that are still equal to their template defaults;
- packs changed non-negative integers as `VarUInt`;
- packs changed signed integers as `VarInt`;
- stores changed booleans with the presence bit alone when possible;
- uses BufferUtil exact-size writers so unused working capacity is not passed forward;
- optionally runs `Compression.CompressBufferSmart()` over the SchemaBuffer candidate;
- compares SchemaBuffer against the generic SDSB and Compression table candidates;
- saves whichever candidate is actually smaller;
- automatically falls back to the generic codec for unsupported or dynamic data;
- fingerprints the schema, including defaults, to prevent an incompatible template from decoding old positional data silently;
- supports `SchemaHistory` for older SchemaBuffer template versions;
- keeps compact Base62 player keys from v1.8.2;
- keeps the compact 19-byte default MemoryStore session frame;
- keeps v1.8.x and older storage decoding paths;
- storage format is now **6**.

---

# Why SchemaBuffer Exists

A normal map stores both names and values conceptually:

```lua
{
    Rebirths = 1,
    Clicks = 2234,
}
```

The strings are useful to your game code, but they are redundant in persistent storage when every player follows the same known template.

Your game already knows:

```lua
DataTemplate = {
    Version = 1,

    Data = {
        Rebirths = 0,
        Clicks = 0,
    },
}
```

That means DataStore can compile a permanent schema from the template.

The runtime API stays readable:

```lua
profile.Data.Rebirths
profile.Data.Clicks

profile:Set("Rebirths", 1)
profile:Set("Clicks", 2234)
```

but the storage codec can operate positionally.

---

# What v1.8.4 Actually Saves

This is the most important v1.8.4 example.

## Runtime template

```lua
DataTemplate = {
    Version = 1,

    Data = {
        Rebirths = 0,
        Clicks = 0,
    },
}
```

## Runtime player data

```lua
{
    Rebirths = 1,
    Clicks = 2234,
}
```

## Compiled schema

SchemaBuffer sorts fixed map keys deterministically.

For this template the schema becomes conceptually:

```text
DataTemplate version: 1

Field 1: Clicks
    Type: unsigned integer
    Default: 0

Field 2: Rebirths
    Type: unsigned integer
    Default: 0
```

The field names belong to the **server-side schema**. They are not written as strings in every player payload.

## Difference from defaults

The player has:

```text
Clicks   = 2234   changed
Rebirths = 1      changed
```

Both fields differ from their defaults, so the two presence bits are:

```text
11
```

The values are then written in schema order:

```text
2234
1
```

`2234` fits in a two-byte VarUInt.

`1` fits in a one-byte VarUInt.

So the value portion is only:

```text
3 bytes
```

The complete raw SchemaBuffer frame also contains its small version/fingerprint/bitmap/checksum framing.

For this exact two-field example, the raw frame is approximately:

```text
Schema magic             1 B
Schema codec version     1 B
DataTemplate version     1 B
Schema fingerprint       4 B
Presence bitmap          1 B
Clicks = 2234 VarUInt    2 B
Rebirths = 1 VarUInt     1 B
Checksum                 4 B
--------------------------------
Raw SchemaBuffer        15 B
```

That is the actual idea behind v1.8.4.

It is **not** saving:

```lua
{
    "Rebirths",
    1,
    "Clicks",
    2234,
}
```

and it is not saving a Lua table containing the field-name strings.

---

# What Happens on Load

Suppose Roblox gives DataStore this positional SchemaBuffer:

```text
version = 1
bitmap  = 11
values  = [2234, 1]
```

DataStore looks up the version-1 schema and starts from a copy of the template:

```lua
{
    Rebirths = 0,
    Clicks = 0,
}
```

Then it applies the present values:

```lua
{
    Rebirths = 1,
    Clicks = 2234,
}
```

Your game receives the normal named profile:

```lua
print(profile.Data.Rebirths) -- 1
print(profile.Data.Clicks)   -- 2234
```

Your gameplay code never needs to know that the stored form was positional.

---

# Default-Value Elision

SchemaBuffer does not write a value when the value still equals the template default.

Example:

```lua
DataTemplate = {
    Version = 1,

    Data = {
        Rebirths = 0,
        Clicks = 0,
        Gems = 0,
        Prestige = 0,
    },
}
```

Player:

```lua
{
    Rebirths = 5,
    Clicks = 1000,
    Gems = 0,
    Prestige = 0,
}
```

Only the changed fields need payload bytes.

Conceptually:

```text
Rebirths changed
Clicks changed
Gems default
Prestige default
```

The defaults are rebuilt from the template on load.

This matters because a large template containing many fields that are still at their defaults can remain very small on disk.

---

# Boolean Packing

Booleans are especially cheap.

Template:

```lua
DataTemplate = {
    Version = 1,

    Data = {
        Music = true,
        SFX = true,
    },
}
```

If the player has:

```lua
{
    Music = false,
    SFX = true,
}
```

SchemaBuffer already knows:

```text
Music default = true
SFX default   = true
```

A present `Music` bit means the value differs from the default.

Because a boolean has only two states, DataStore can reconstruct:

```text
not true = false
```

without writing a separate boolean payload byte.

So changed booleans use their presence bit to carry the full value.

---

# Nested Template Example

SchemaBuffer supports fixed nested string-keyed maps.

Template:

```lua
DataTemplate = {
    Version = 1,

    Data = {
        Coins = 0,

        Settings = {
            Music = true,
            SFX = true,
        },

        Stats = {
            Rebirths = 0,
            Clicks = 0,
        },
    },
}
```

The compiled fields become deterministic paths similar to:

```text
Coins
Settings.Music
Settings.SFX
Stats.Clicks
Stats.Rebirths
```

You still use:

```lua
profile.Data.Settings.Music
profile.Data.Stats.Rebirths
```

normally.

The path strings are used by the schema compiler, not repeatedly persisted for every player.

---

# SchemaBuffer Supported Leaf Types

A fixed template leaf can currently compile as:

- non-negative safe integer → `VarUInt`;
- safe signed integer → `VarInt`;
- other finite number → `f64`;
- boolean;
- string;
- buffer;
- `Vector2`;
- `Vector3`;
- `Color3`;
- `CFrame`;
- `UDim`;
- `UDim2`.

The type is inferred from the **template default**.

Example:

```lua
DataTemplate = {
    Version = 1,

    Data = {
        Coins = 0,             -- VarUInt
        Debt = -1,             -- VarInt
        Multiplier = 1.5,      -- f64
        Music = true,          -- bool
        Title = "",            -- string
        Spawn = Vector3.zero,  -- Vector3
    },
}
```

Keep the template type stable for the lifetime of that schema version.

---

# When SchemaBuffer Falls Back

SchemaBuffer intentionally does **not** try to encode every possible table shape.

The generic Compression codec remains available for data that is not appropriate for a positional fixed schema.

Examples that cause the SchemaBuffer candidate to be unavailable include:

- non-empty array template nodes;
- empty/dynamic table template nodes;
- non-string map keys;
- unsupported template leaf types;
- an unknown runtime field not present in the template;
- a nested schema table being replaced by another type;
- a field changing to an incompatible runtime type;
- an inferred integer field receiving a value outside the supported exact integer range.

With the default:

```lua
SchemaFallbackToGeneric = true
```

DataStore does not throw away that data.

Instead:

```text
SchemaBuffer candidate
        │
        ├── compatible → compare candidate size
        │
        └── incompatible
                  ↓
        generic Compression codec
```

This is important for safety.

---

# Example: Dynamic Inventory

This template is intentionally dynamic:

```lua
DataTemplate = {
    Version = 1,

    Data = {
        Inventory = {},
    },
}
```

An empty table means its future key/value shape is not defined by the template.

SchemaBuffer will not guess an order for it.

A runtime inventory such as:

```lua
{
    Inventory = {
        Sword = 2,
        Potion = 10,
        RareItem = 1,
    },
}
```

is saved by the generic adaptive Compression path instead.

This lets one DataStore support both:

- highly compact fixed progression/settings data;
- flexible dynamic data.

---

# Candidate Selection

With `StorageMode = "Buffer"`, DataStore can compare several valid storage candidates.

```text
Named DataTemplate
        │
        ├── SchemaBuffer
        │      └── optional CompressBufferSmart
        │
        ├── generic SDSB / BufferV1-compatible candidate
        │      └── optional Compression buffer codec
        │
        └── Compression v2.6.7 native table candidate
                       │
                       ▼
                smallest valid result
                       │
                       ▼
                DataStoreService
```

SchemaBuffer is not forced just because it is enabled.

The module still selects the smallest candidate.

That means a profile can report:

```text
SchemaCandidateAvailable = true
SchemaSelected = false
```

if another codec happened to be smaller for that exact value.

---

# BufferUtil’s Job

BufferUtil and Compression solve different problems.

## BufferUtil

BufferUtil prevents unused **working capacity** from being passed to the next stage.

Example:

```text
writer backing buffer = 64 B
actually written      = 19 B
unused capacity       = 45 B
```

Before the data is handed onward, DataStore compacts it to:

```text
19 B
```

The unused 45 bytes are not part of the stored payload.

## Compression

Compression reduces the actual representation when a codec can make it smaller.

Example:

```text
exact SchemaBuffer = 40 B
Compression Smart  = 31 B
```

then DataStore can use the 31-byte candidate.

But if:

```text
exact SchemaBuffer = 19 B
compressed result  = 25 B
```

DataStore keeps the 19-byte raw SchemaBuffer.

This is why:

```text
LastBufferCompressed = false
```

can still be the best result.

---

# Compact Player Keys

v1.8.4 keeps the compact player-key system introduced in v1.8.2.

Default:

```lua
CompactPlayerKeys = true
CompactKeyPrefix = "p"
```

Instead of:

```text
Player_10800269681
```

the UserId is encoded as Base62 and can become something like:

```text
pBmupW5
```

For that example:

```text
legacy key: 18 characters
compact key: 7 characters
saved:       11 characters
```

You can inspect this:

```lua
local info = Store:GetKeyInfo(player)

print("Key:", info.Key)
print("Key bytes:", info.KeyBytes)

print("Legacy key:", info.LegacyKey)
print("Legacy key bytes:", info.LegacyKeyBytes)

print("Saved bytes:", info.SavedBytes)
print("Savings:", info.SavingsPercent)
```

---

# Compact-Key Migration

Existing saves under:

```text
Player_<UserId>
```

can still load.

Defaults:

```lua
MigrateLegacyPlayerKeys = true
DeleteLegacyPlayerKeys = true
```

Load behavior:

```text
try compact key
      │
      ├── found → load
      │
      └── missing
             ↓
       try legacy key
             ↓
           found
             ↓
       load old profile
             ↓
       successful compact-key save
             ↓
       remove legacy key
```

The old key is not deleted before the new write succeeds.

---

# Session Lock Storage

Player profile data and session ownership are separate systems.

Persistent player data is stored in:

```text
DataStoreService
```

Session locks are stored in:

```text
MemoryStoreService
```

Default session configuration:

```lua
SessionLocking = true
SessionLockTimeout = 180

SessionCompressionEnabled = true
SessionStoreDiagnostics = false
```

With diagnostics disabled and a standard Roblox GUID session ID, the active raw session frame is typically:

```text
magic      1 B
version    1 B
flags      1 B
session ID 16 B
----------------
total      19 B
```

Compression Smart may report:

```text
Session compressed: false
Session raw bytes: 19
Session stored bytes: 19
```

That is a successful result.

A 19-byte high-entropy session GUID often cannot be compressed further without expansion.

---

# Roblox Creator Hub Size vs Buffer Size

`buffer.len()` and Creator Hub storage usage are different measurements.

Example:

```text
DataStore buffer.len(value) = 25 B
Creator Hub may report      = a larger number
```

The Creator Hub number can include Roblox's own storage representation and per-entry/platform overhead.

DataForage or another editor may also display a buffer as:

```text
Array (25)
```

or Base64.

Those are viewer representations of the same buffer.

Use:

```lua
profile:GetStorageInfo()
```

to inspect the codec payload sizes produced by this module.

Then use Creator Hub to compare the final platform-level result.

---

# Requirements

DataStore v1.8.4 is **server-only**.

The DataStore ModuleScript requires two child modules:

```text
DataStore
├── Compression
└── BufferUtil
```

Required versions:

```text
Compression = 2.6.7
BufferUtil  = 1.1.0
```

Recommended server layout:

```text
ServerScriptService
└── Data
    └── DataStore
        ├── Compression
        └── BufferUtil
```

Example:

```lua
local ServerScriptService =
    game:GetService("ServerScriptService")

local DataStore = require(
    ServerScriptService.Data.DataStore
)
```

Do not require DataStore from a `LocalScript`.

---

# Quick Start

```lua
local Players =
    game:GetService("Players")

local ServerScriptService =
    game:GetService("ServerScriptService")

local DataStore = require(
    ServerScriptService.Data.DataStore
)

local Store = DataStore.new({
    Name = "PlayersData",

    DataTemplate = {
        Version = 1,

        Data = {
            Rebirths = 0,
            Clicks = 0,

            Settings = {
                Music = true,
                SFX = true,
            },
        },
    },

    StorageMode = "Buffer",

    SchemaBufferEnabled = true,
    SchemaBufferCompress = true,
    SchemaFallbackToGeneric = true,

    BufferUtilEnabled = true,

    CompressionEnabled = true,

    CompactPlayerKeys = true,

    AutoSave = true,
    AutoSaveInterval = 60,

    SessionLocking = true,
    SessionLockTimeout = 180,

    BudgetAware = true,
})

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
        "Loaded:",
        player.Name
    )

    print(
        "Rebirths:",
        profile.Data.Rebirths
    )

    print(
        "Clicks:",
        profile.Data.Clicks
    )
end)
```

`DataStore.new()` installs its own player-removal and shutdown release handling.

You normally do **not** need another `Players.PlayerRemoving` handler just to release profiles.

---

# Updating Player Data

## Get

```lua
local clicks =
    profile:Get("Clicks")
```

## Set

```lua
profile:Set(
    "Rebirths",
    10
)
```

## Increment

```lua
profile:Increment(
    "Clicks",
    100
)
```

Default amount:

```lua
profile:Increment("Clicks")
```

adds `1`.

## Update

```lua
profile:Update(
    "Clicks",
    function(current)
        return (current or 0) * 2
    end
)
```

## Overwrite

```lua
profile:Overwrite({
    Rebirths = 0,
    Clicks = 0,

    Settings = {
        Music = true,
        SFX = true,
    },
})
```

## Reconcile

```lua
profile:Reconcile()
```

Reconciliation fills missing fixed map fields from the configured template.

---

# Saving

## Manual save

```lua
local success, err =
    profile:SaveAsync()

if not success then
    warn(
        "Save failed:",
        err
    )
end
```

Store equivalent:

```lua
local success, err =
    Store:SavePlayerAsync(player)
```

## Autosave

Enabled by default:

```lua
AutoSave = true
AutoSaveInterval = 60
```

`AutoSaveInterval` must be at least `10`.

---

# Releasing Profiles

Manual release:

```lua
local success, err =
    profile:ReleaseAsync(
        "ManualRelease"
    )

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

`ReleaseAsync()` saves before releasing the MemoryStore session lock.

---

# Lock Modes

`OpenPlayerAsync()` supports:

```text
Wait
Cancel
Steal
```

## Wait

Default:

```lua
local profile, err =
    Store:OpenPlayerAsync(
        player,
        {
            Locked = "Wait",
        }
    )
```

## Cancel

```lua
local profile, err =
    Store:OpenPlayerAsync(
        player,
        {
            Locked = "Cancel",
        }
    )
```

## Steal

```lua
local profile, err =
    Store:OpenPlayerAsync(
        player,
        {
            Locked = "Steal",
        }
    )
```

Use `Steal` carefully because another live server may still believe it owns the profile.

---

# DataTemplate Versions

Recommended:

```lua
DataTemplate = {
    Version = 1,

    Data = {
        Rebirths = 0,
        Clicks = 0,
    },
}
```

The version is especially important with SchemaBuffer because a positional frame is reconstructed using the template associated with that version.

---

# Schema History

If players have already been saved with SchemaBuffer and you later change the schema/defaults, bump `DataTemplate.Version`.

Preserve the old template in `SchemaHistory`.

Example version 1:

```lua
local V1 = {
    Rebirths = 0,
    Clicks = 0,
}
```

New version 2:

```lua
local V2 = {
    Rebirths = 0,
    Clicks = 0,
    Gems = 0,
}
```

Configure:

```lua
local Store = DataStore.new({
    Name = "PlayersData",

    DataTemplate = {
        Version = 2,
        Data = V2,
    },

    SchemaHistory = {
        [1] = V1,
    },

    Migrations = {
        [2] = function(data)
            data.Gems =
                data.Gems or 0

            return data
        end,
    },
})
```

`SchemaHistory` can also contain a DataTemplate-shaped entry:

```lua
SchemaHistory = {
    [1] = {
        Version = 1,

        Data = {
            Rebirths = 0,
            Clicks = 0,
        },
    },
}
```

The version key is what identifies the old schema.

---

# Why the Schema Fingerprint Matters

SchemaBuffer includes a fingerprint made from:

- field paths;
- inferred leaf kinds;
- template defaults.

Suppose version 1 was originally:

```lua
{
    Coins = 0,
}
```

and you silently change the same version to:

```lua
{
    Coins = 100,
}
```

An old SchemaBuffer save may have omitted `Coins` because it equaled the old default `0`.

Without fingerprint validation, the same payload could incorrectly reconstruct `100`.

v1.8.4 detects that mismatch and errors instead.

Correct approach:

```text
change schema/default
        ↓
bump DataTemplate.Version
        ↓
keep old template in SchemaHistory
        ↓
run migration if needed
```

---

# Migrations

Migrations remain indexed by the target version.

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
        [2] = function(
            data,
            fromVersion,
            toVersion
        )
            data.Gems =
                data.Gems or 0

            return data
        end,

        [3] = function(
            data,
            fromVersion,
            toVersion
        )
            data.Stats =
                data.Stats or {
                    Level = 1,
                }

            return data
        end,
    },
})
```

A migration can mutate and return `nil`, or return a replacement table.

---

# Inspecting the Compiled Schema

Use:

```lua
local info =
    Store:GetSchemaInfo()

print("Enabled:", info.Enabled)
print("Eligible:", info.Eligible)
print("Reason:", info.Reason)

print(
    "Schema format:",
    info.FormatVersion
)

print(
    "Data version:",
    info.DataVersion
)

if info.Eligible then
    print(
        "Field count:",
        info.FieldCount
    )

    print(
        "Bitmap bytes:",
        info.BitmapBytes
    )

    print(
        "Fingerprint:",
        info.Fingerprint
    )

    for _, field in ipairs(info.Fields) do
        print(
            field.Index,
            field.Path,
            field.Kind
        )
    end
end
```

Example:

```text
Enabled: true
Eligible: true
Field count: 5
Bitmap bytes: 1

1 Coins uint
2 Settings.Music bool
3 Settings.SFX bool
4 Stats.Clicks uint
5 Stats.Rebirths uint
```

---

# Storage Information

After a successful save:

```lua
local info =
    profile:GetStorageInfo()
```

## Player key

```lua
print(
    "Player key:",
    info.PlayerKey
)

print(
    "Player key bytes:",
    info.PlayerKeyBytes
)

print(
    "Legacy key bytes:",
    info.LegacyPlayerKeyBytes
)

print(
    "Key bytes saved:",
    info.PlayerKeySavedBytes
)
```

## Final codec

```lua
print(
    "Generic baseline:",
    info.LastRawBufferBytes
)

print(
    "Stored payload:",
    info.LastBufferBytes
)

print(
    "Codec:",
    info.LastCompressionMode
)

print(
    "Compressed:",
    info.LastBufferCompressed
)
```

## SchemaBuffer

```lua
print(
    "Schema eligible:",
    info.SchemaEligible
)

print(
    "Schema candidate available:",
    info.SchemaCandidateAvailable
)

print(
    "Schema selected:",
    info.SchemaSelected
)

print(
    "Schema candidate bytes:",
    info.LastSchemaCandidateBytes
)

print(
    "Schema candidate mode:",
    info.LastSchemaCandidateMode
)

print(
    "Schema raw bytes:",
    info.LastSchemaRawBytes
)

print(
    "Schema field count:",
    info.SchemaFieldCount
)

print(
    "Changed fields stored:",
    info.LastSchemaPresentFields
)

print(
    "Default fields omitted:",
    info.LastSchemaDefaultFieldsOmitted
)
```

## BufferUtil exact-size stats

```lua
print(
    "Working bytes:",
    info.LastWorkingBufferBytes
)

print(
    "Compacted bytes:",
    info.LastCompactedPayloadBytes
)

print(
    "Unused working bytes removed:",
    info.LastUnusedWorkingBytesRemoved
)

print(
    "Schema working bytes:",
    info.LastSchemaWorkingBufferBytes
)

print(
    "Schema compacted bytes:",
    info.LastSchemaCompactedPayloadBytes
)

print(
    "Schema unused bytes removed:",
    info.LastSchemaUnusedWorkingBytesRemoved
)
```

## Session

```lua
print(
    "Session raw bytes:",
    info.LastSessionRawBytes
)

print(
    "Session stored bytes:",
    info.LastSessionLockBytes
)

print(
    "Session codec:",
    info.LastSessionCompressionMode
)

print(
    "Session working bytes:",
    info.LastSessionWorkingBufferBytes
)

print(
    "Session compacted bytes:",
    info.LastSessionCompactedPayloadBytes
)
```

---

# Example v1.8.4 Size Test

```lua
Players.PlayerAdded:Connect(function(player)
    local profile, err =
        Store:OpenPlayerAsync(player)

    if not profile then
        warn(err)
        player:Kick(
            "Data failed to load."
        )
        return
    end

    profile:Set(
        "Rebirths",
        1
    )

    profile:Set(
        "Clicks",
        2234
    )

    local success, saveErr =
        profile:SaveAsync()

    if not success then
        warn(saveErr)
        return
    end

    local info =
        profile:GetStorageInfo()

    print(
        "Stored codec:",
        info.LastCompressionMode
    )

    print(
        "Generic raw baseline:",
        info.LastRawBufferBytes,
        "B"
    )

    print(
        "Schema raw:",
        info.LastSchemaRawBytes,
        "B"
    )

    print(
        "Schema candidate:",
        info.LastSchemaCandidateBytes,
        "B"
    )

    print(
        "Final stored:",
        info.LastBufferBytes,
        "B"
    )

    print(
        "Defaults omitted:",
        info.LastSchemaDefaultFieldsOmitted
    )

    print(
        "Schema selected:",
        info.SchemaSelected
    )
end)
```

For the simple two-`VarUInt` example, a raw SchemaBuffer around `15 B` is expected before Roblox platform-level overhead.

Always use the actual printed result as the authoritative measurement for the current data.

---

# Compression

Compression remains enabled by default:

```lua
CompressionEnabled = true
```

Required:

```text
Compression v2.6.7
```

Primary settings:

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

Supported string strategies include:

```text
Auto
Raw
LZ
ASCII7
LowASCII5
Identifier6
Numeric4
```

Supported buffer strategies:

```text
Auto
Raw
LZ
Sparse
Nibble
```

Supported entropy strategies:

```text
Auto
Huffman
None
```

---

# BufferUtil

Required:

```text
BufferUtil v1.1.0
```

Default:

```lua
BufferUtilEnabled = true
BufferWriterInitialCapacity = 32
```

DataStore uses BufferUtil internally for exact-size working buffers.

You normally do not need to call BufferUtil yourself just to save a profile.

Public DataStore helper:

```lua
local exact =
    DataStore.CompactBufferExact(
        someBuffer,
        usedBytes
    )
```

---

# Storage Modes

## Buffer

Default and recommended for v1.8.4:

```lua
StorageMode = "Buffer"
```

This enables the candidate selection system including SchemaBuffer.

## Table

```lua
StorageMode = "Table"
```

Stores a normal copied DataTemplate table.

SchemaBuffer is a buffer-storage optimization, so use `StorageMode = "Buffer"` when you want v1.8.4's compact storage path.

---

# Viewing Data Without Opening a Session

## Full DataTemplate

```lua
local dataTemplate, source =
    Store:ViewTemplateAsync(userId)

if dataTemplate then
    print(
        dataTemplate.Version
    )

    print(
        dataTemplate.Data
    )
end
```

## Data only

```lua
local data, version, source =
    Store:ViewAsync(userId)

if data then
    print(
        "Version:",
        version
    )

    print(data)
end
```

A SchemaBuffer value is decoded back into the normal named DataTemplate before these functions return it.

---

# Inspecting the Actual Stored Value

```lua
local payload, payloadType =
    Store:GetStoredPayloadAsync(userId)

print(
    payloadType
)

if typeof(payload) == "buffer" then
    print(
        "Actual buffer bytes:",
        buffer.len(payload)
    )
end
```

This is useful when comparing what DataForage displays with the actual buffer payload.

---

# Session Lock Inspection

```lua
local lockInfo, err =
    Store:GetSessionLockInfoAsync(
        userId
    )

if not lockInfo then
    warn(err)
else
    print(
        lockInfo
    )
end
```

---

# Public Key Helpers

Encode the numeric UserId portion:

```lua
local encoded =
    DataStore.EncodeUserIdKey(
        10800269681
    )

print(encoded)
```

Decode it:

```lua
local userId =
    DataStore.DecodeUserIdKey(
        encoded
    )

print(userId)
```

`CompactKeyPrefix` is applied by the Store separately.

---

# Public Version Helpers

```lua
print(
    DataStore.Version()
)
```

Returns:

```text
1.8.4
```

Storage format:

```lua
print(
    DataStore.FormatVersion()
)
```

Returns:

```text
6
```

Compression:

```lua
print(
    DataStore.CompressionVersion()
)
```

Returns:

```text
2.6.7
```

BufferUtil:

```lua
print(
    DataStore.BufferUtilVersion()
)
```

Returns:

```text
1.1.0
```

Schema format:

```lua
print(
    DataStore.SchemaFormatVersion
)
```

Session format:

```lua
print(
    DataStore.SessionFormatVersion
)
```

---

# Legacy Compatibility

v1.8.4 keeps compatibility paths for older stored data, including:

- current SchemaBuffer format;
- Compression v2.6.7 table frames;
- generic SDSB / BufferV1 values;
- compressed legacy BufferV1 values;
- older supported DataStore records;
- normal legacy table values;
- legacy `Player_<UserId>` player keys when compact-key migration is enabled.

An old profile can load through a legacy decoder and then be rewritten using the new v1.8.4 selection path.

---

# Configuration Reference

| Option | Default | Description |
|---|---:|---|
| `Name` | required | Roblox DataStore name |
| `Scope` | `nil` | Optional DataStore scope |
| `KeyPrefix` | `"Player_"` | Legacy player key prefix |
| `CompactPlayerKeys` | `true` | Use compact Base62 player keys |
| `CompactKeyPrefix` | `"p"` | Prefix for compact player keys |
| `MigrateLegacyPlayerKeys` | `true` | Load old `Player_<UserId>` keys when compact key is missing |
| `DeleteLegacyPlayerKeys` | `true` | Remove old key after a successful compact-key save |
| `DataTemplate.Version` | `1` | Current data/schema version |
| `DataTemplate.Data` | `{}` | Default player data |
| `Template` | `{}` | Legacy separate template style |
| `DataVersion` | `1` | Legacy separate version style |
| `Migrations` | `nil` | Target-version migration callbacks |
| `RejectFutureDataVersion` | `true` | Reject newer stored data versions |
| `Reconcile` | `true` | Fill missing fixed map fields |
| `AutoSave` | `true` | Enable autosave |
| `AutoSaveInterval` | `60` | Autosave interval, minimum `10` |
| `SessionLocking` | `true` | Enable MemoryStore ownership locks |
| `SessionLockTimeout` | `180` | Lock TTL |
| `LoadTimeout` | `30` | Maximum wait for a locked profile |
| `LockRetryInterval` | `1` | Delay between lock attempts |
| `MemoryLockRetryAttempts` | `4` | MemoryStore operation retry count |
| `SessionCompressionEnabled` | `true` | Allow Smart compression of compact session frames |
| `SessionStoreDiagnostics` | `false` | Add JobId/PlaceId/timestamp diagnostics to session frame |
| `RetryAttempts` | `5` | DataStore request attempts |
| `RetryDelay` | `0.75` | Base retry delay |
| `MaxRetryDelay` | `8` | Maximum retry delay |
| `ShutdownTimeout` | `25` | Shutdown profile-release window |
| `BudgetAware` | `true` | Wait for DataStore request budget |
| `BudgetWaitTimeout` | `10` | Maximum budget wait |
| `StorageMode` | `"Buffer"` | `"Buffer"` or `"Table"` |
| `BufferUtilEnabled` | `true` | Use BufferUtil exact-size writer pipeline |
| `BufferWriterInitialCapacity` | `32` | Initial writer working capacity |
| `SchemaBufferEnabled` | `true` | Enable positional SchemaBuffer candidate |
| `SchemaBufferCompress` | `true` | Try Compression Smart on SchemaBuffer |
| `SchemaFallbackToGeneric` | `true` | Fall back instead of failing on unsupported schema data |
| `SchemaHistory` | `nil` | Older templates keyed by DataTemplate version |
| `CompressionEnabled` | `true` | Enable Compression candidates |
| `CompressionTableStrategy` | `"Auto"` | `Auto`, `Compact`, or `Dynamic` |
| `CompressionCompressStrings` | `true` | Enable string compression |
| `CompressionStringStrategy` | `"Auto"` | String codec strategy |
| `CompressionUseStringDictionary` | `true` | Repeated-string dictionary |
| `CompressionHomogeneousArrays` | `true` | Homogeneous array codecs |
| `CompressionDeltaArrays` | `true` | Delta array codecs |
| `CompressionRunLengthArrays` | `true` | RLE array codecs |
| `CompressionCompactMapKeys` | `true` | Compact map keys |
| `CompressionTableKeyMapping` | `true` | Repeated-key mapping |
| `CompressionEntropyCoding` | `true` | Entropy-coding candidates |
| `CompressionEntropyStrategy` | `"Auto"` | `Auto`, `Huffman`, `None` |
| `CompressionAllowExpansion` | `false` | Reject intentionally expanding compression |
| `CompressionCompareLegacyBuffer` | `true` | Compare legacy buffer candidate |
| `CompressionMinBufferBytes` | `16` | Minimum size before legacy buffer compression |
| `CompressionMinSavingsBytes` | `1` | Minimum accepted savings |
| `CompressionBufferStrategy` | `"Auto"` | Buffer codec strategy |
| `CompressionBufferMinLength` | `6` | Buffer match minimum |
| `CompressionBufferSearchDepth` | `32` | Buffer match search depth |
| `CompressionBufferWindowSize` | `32767` | Buffer search window |
| `CompressionBufferMaxMatch` | `66` | Maximum buffer match |
| `MaxBufferBytes` | `3800000` | Maximum encoded buffer |
| `MaxDepth` | `64` | Maximum nested table depth |
| `MaxTableEntries` | `100000` | Maximum validated table entries |
| `Debug` | `false` | Debug warnings |

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

## Schema and key inspection

```lua
Store:GetSchemaInfo()
Store:GetKeyInfo(subject)
```

## Stored data

```lua
Store:ViewTemplateAsync(subject)
Store:ViewAsync(subject)

Store:GetStoredBufferAsync(subject)
Store:GetStoredPayloadAsync(subject)

Store:GetSessionLockInfoAsync(subject)
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

# Static Utility API

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

DataStore.CompactBufferExact(
    dataBuffer,
    usedBytes?
)

DataStore.EncodeUserIdKey(userId)
DataStore.DecodeUserIdKey(encoded)

DataStore.Version()
DataStore.FormatVersion()
DataStore.CompressionVersion()
DataStore.BufferUtilVersion()
```

Also exposed:

```lua
DataStore.Profile
DataStore.Signal
DataStore.BufferEncoding
DataStore.SessionFormatVersion
DataStore.SchemaFormatVersion
```

---

# Profile Signals

Each profile exposes:

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
        key,
        oldValue,
        "->",
        newValue
    )
end)
```

## Saved

```lua
profile.Saved:Connect(function(info)
    print(
        "Stored:",
        info.LastBufferBytes,
        "B"
    )

    print(
        "Codec:",
        info.LastCompressionMode
    )
end)
```

## Released

```lua
profile.Released:Connect(function(reason)
    print(
        "Released:",
        reason
    )
end)
```

---

# Store Signals

```lua
Store.ProfileLoaded
Store.ProfileReleased
Store.Issue
```

Example:

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

Common issue conditions include:

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

# Production Safety

## Keep one owner for a profile

Do not run multiple unrelated profile systems that all believe they own the same player persistence key.

## Never trust client values

The persistence module validates storage structure, not gameplay legitimacy.

Validate server-side:

- currency rewards;
- purchases;
- inventory changes;
- progression;
- permissions;
- item IDs;
- cooldowns;
- admin operations.

## Do not replace failed loads with empty data

Bad:

```lua
local profile =
    Store:OpenPlayerAsync(player)

if not profile then
    -- Do not save fake empty data here.
end
```

A later save could overwrite valid player data.

## Keep profiles bounded

Compression and SchemaBuffer reduce representation size.

They do not make unlimited inventories, histories, logs, or cached temporary data safe.

---

# Troubleshooting

## `requires Compression v2.6.7`

Make sure:

```text
DataStore
└── Compression
```

exists and:

```lua
Compression.Version()
```

returns:

```text
2.6.7
```

## `requires BufferUtil v1.1.0`

Make sure:

```text
DataStore
└── BufferUtil
```

exists and:

```lua
BufferUtil.VERSION
```

is:

```text
1.1.0
```

## SchemaBuffer says the template is not eligible

Inspect:

```lua
local info =
    Store:GetSchemaInfo()

warn(info.Reason)
```

Common causes:

- empty dynamic table;
- array template;
- unsupported leaf type;
- non-string map key.

With:

```lua
SchemaFallbackToGeneric = true
```

the generic codec can still save the profile.

## Schema fingerprint mismatch

Do not change a released template/default while keeping the same `DataTemplate.Version`.

Instead:

1. preserve the old template in `SchemaHistory`;
2. increment `DataTemplate.Version`;
3. add a migration if needed.

## SessionLocked

Another server currently owns the MemoryStore lock.

Use `"Wait"` unless you specifically need different behavior.

## SessionLost

The server could not prove it still owns the session lock.

The profile is deactivated to avoid unsafe writes.

## Save looks larger in Creator Hub

Check:

```lua
local info =
    profile:GetStorageInfo()

print(
    "Actual payload:",
    info.LastBufferBytes
)
```

Creator Hub measures Roblox's platform-level stored entry, which can be larger than the raw Luau buffer.

A DataForage array display or Base64 representation is also not the same thing as `buffer.len()`.

---

# Recommended Player Script

```lua
local Players =
    game:GetService("Players")

local ServerScriptService =
    game:GetService("ServerScriptService")

local DataStore = require(
    ServerScriptService.Data.DataStore
)

local Store = DataStore.new({
    Name = "PlayersData",

    DataTemplate = {
        Version = 1,

        Data = {
            Rebirths = 0,
            Clicks = 0,

            Settings = {
                Music = true,
                SFX = true,
            },
        },
    },

    StorageMode = "Buffer",

    SchemaBufferEnabled = true,
    SchemaBufferCompress = true,
    SchemaFallbackToGeneric = true,

    BufferUtilEnabled = true,

    CompressionEnabled = true,
    CompressionTableStrategy = "Auto",
    CompressionStringStrategy = "Auto",
    CompressionEntropyStrategy = "Auto",

    CompactPlayerKeys = true,

    AutoSave = true,
    AutoSaveInterval = 60,

    SessionLocking = true,
    SessionLockTimeout = 180,

    SessionCompressionEnabled = true,
    SessionStoreDiagnostics = false,

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

print(
    "BufferUtil:",
    DataStore.BufferUtilVersion()
)

local schema =
    Store:GetSchemaInfo()

print(
    "Schema eligible:",
    schema.Eligible
)

if schema.Eligible then
    print(
        "Schema fields:",
        schema.FieldCount
    )

    for _, field in ipairs(schema.Fields) do
        print(
            field.Index,
            field.Path,
            field.Kind
        )
    end
end

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
        "Clicks",
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
        "Key:",
        info.PlayerKey,
        "(" .. tostring(
            info.PlayerKeyBytes
        ) .. " B)"
    )

    print(
        "Codec:",
        info.LastCompressionMode
    )

    print(
        "Generic baseline:",
        info.LastRawBufferBytes,
        "B"
    )

    print(
        "Schema candidate:",
        info.LastSchemaCandidateBytes,
        "B"
    )

    print(
        "Final stored:",
        info.LastBufferBytes,
        "B"
    )

    print(
        "Schema selected:",
        info.SchemaSelected
    )

    print(
        "Defaults omitted:",
        info.LastSchemaDefaultFieldsOmitted
    )

    print(
        "Session:",
        info.LastSessionLockBytes,
        "B"
    )
end)
```

---

# Release Summary

**DataStore v1.8.4**

- storage format **6**;
- SchemaBuffer format **1**;
- session format **1**;
- Compression **2.6.7**;
- BufferUtil **1.1.0**;
- positional schema storage for fixed templates;
- field-name removal from SchemaBuffer payloads;
- default-value omission;
- presence-bit boolean packing;
- VarUInt/VarInt integer packing;
- schema fingerprint validation;
- `SchemaHistory` support;
- adaptive fallback to generic Compression;
- exact-size working buffers;
- compact Base62 player keys;
- legacy key migration;
- compact MemoryStore session locks;
- autosave;
- profile session ownership;
- migrations;
- reconciliation;
- validation;
- budget-aware retries;
- legacy save decoding;
- detailed key/schema/compression/session storage statistics.
