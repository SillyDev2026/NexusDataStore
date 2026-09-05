# DataStore

![Version](https://img.shields.io/badge/version-v2.1.0-4c8bf5)
![Language](https://img.shields.io/badge/language-Luau-00A2FF)
![Typechecking](https://img.shields.io/badge/typechecking-strict-2ea44f)
![Platform](https://img.shields.io/badge/platform-Roblox-111111)
![Runtime](https://img.shields.io/badge/runtime-server--only-orange)
![Storage Format](https://img.shields.io/badge/storage%20format-v8-2ea44f)
![Compression](https://img.shields.io/badge/compression-v3.0.0-6f42c1)
![BufferUtil](https://img.shields.io/badge/BufferUtil-removed-red)

**DataStore v2.1.0** is a strict-typed, server-side Roblox persistence module built around **Compression v3.0.0**.

The current storage path no longer uses DataStore-owned SchemaBuffer/BufferUtil bit packing for new saves. Instead, Compression owns the compact representation:

- reusable `Compression.IndexedLayout()` for fixed player templates;
- adaptive `Compression.CompressTablePacket()` for dynamic/fallback data;
- automatic candidate comparison;
- compressed MemoryStore session locks;
- compact Base62 player keys;
- autosave;
- profile/session ownership;
- migrations and reconciliation;
- budget-aware retries;
- legacy save decoding;
- strict Luau type definitions across the public and internal APIs.

> Current release: **v2.1.0**  
> Storage format: **8**  
> Session format: **2**  
> Required Compression: **v3.0.0**  
> BufferUtil: **removed from the active dependency tree**  
> Luau mode: **`--!strict`**

---

# What’s New in v2.1.0

v2.1.0 is primarily a **type-safety and API-contract update** over the Compression-native v2.0.0 storage system.

Major changes:

- enabled `--!strict`;
- added exported public types;
- typed DataStore construction and configuration;
- typed profile objects;
- typed store objects;
- typed session-lock information;
- typed storage statistics;
- typed signal objects;
- typed compression interfaces;
- typed reader/writer helpers;
- typed migrations;
- typed public utility functions;
- fixed strict-mode nilability assumptions;
- preserved storage format **8**;
- preserved session format **2**;
- preserved Compression v3 save compatibility.

There is **no v2.0 → v2.1 save migration** required.

---

# Architecture

The new write path is intentionally simple:

```text
profile.Data
    │
    ▼
Compression v3
    │
    ├── IndexedLayout candidate
    │      └── best for fixed DataTemplates
    │
    └── Adaptive table candidate
           └── safe for dynamic/unknown structures
    │
    ▼
smallest valid candidate
    │
    ▼
tiny DataStore v8 frame
    │
    ▼
DataStoreService
```

DataStore itself no longer owns the main bit-packing algorithm.

Compression v3 owns:

- schema/default elision;
- bit-first integer representation;
- compact strings;
- table encoding;
- homogeneous arrays;
- delta arrays;
- RLE arrays;
- key mapping;
- buffer compression;
- optional entropy coding.

---

# Requirements

DataStore v2.1.0 is **server-only**.

Required layout:

```text
DataStore
└── Compression
```

Required Compression version:

```text
3.0.0
```

The DataStore checks this when the module is initialized.

Example:

```lua
local DataStore = require(script.DataStore)

print(DataStore.Version())
print(DataStore.CompressionVersion())
```

Expected:

```text
2.1.0
3.0.0
```

Do not require this DataStore from a `LocalScript`.

---

# BufferUtil Is No Longer Required

Older DataStore versions used:

```text
DataStore
├── Compression
└── BufferUtil
```

v2.1.0 uses:

```text
DataStore
└── Compression
```

`BufferUtil` is not required for new writes.

The compatibility helper:

```lua
DataStore.BufferUtilVersion()
```

returns:

```text
Removed
```

Legacy SchemaBuffer/BufferV1 decode code remains internally so older profiles can still migrate forward.

---

# Recommended Clicker Simulator Template

A fixed simulator template is a strong fit for `IndexedLayout`.

## `PlayersData` ModuleScript

```lua
--!strict

export type RunesData = {
	Common: number,
	Uncommon: number,
	Epic: number,
	Legendary: number,
}

export type PlayerData = {
	Clicks: number,
	Rebirths: number,
	Ultra: number,
	Prestiges: number,

	Runes: RunesData,

	PlayTime: number,
	ClickPlus: number,
}

local PlayersData: PlayerData = {
	Clicks = 0,
	Rebirths = 0,
	Ultra = 0,
	Prestiges = 0,

	Runes = {
		Common = 0,
		Uncommon = 0,
		Epic = 0,
		Legendary = 0,
	},

	PlayTime = 0,
	ClickPlus = 1,
}

return PlayersData
```

---

# Creating the Store

```lua
--!strict

local DataStore = require(script.DataStore)
local PlayersData = require(script.PlayersData)

local Data = DataStore.new({
	Name = "ClickStore",

	DataTemplate = {
		Version = 1,
		Data = PlayersData,
	},

	StorageMode = "Buffer",

	CompressionEnabled = true,

	CompressionIndexedLayout = true,
	CompressionCompareAdaptiveTable = true,

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

	SessionCompressionEnabled = true,
	SessionStoreDiagnostics = false,
})
```

Most of those Compression settings are already the defaults.

A shorter production setup is therefore also valid:

```lua
local Data = DataStore.new({
	Name = "ClickStore",

	DataTemplate = {
		Version = 1,
		Data = PlayersData,
	},

	StorageMode = "Buffer",
})
```

---

# Player Joining

Use `OpenPlayerAsync()` when the player joins.

```lua
local Players = game:GetService("Players")

local function playerAdded(player: Player)
	local profile, loadError = Data:OpenPlayerAsync(player)

	if profile == nil then
		warn(
			"[DataStore] Failed to load",
			player.Name,
			loadError
		)

		player:Kick(
			"Data failed to load. Please rejoin."
		)

		return
	end

	print(
		"[DataStore] Loaded",
		player.Name
	)

	print(
		"Clicks:",
		profile.Data.Clicks
	)
end

Players.PlayerAdded:Connect(playerAdded)

for _, player in Players:GetPlayers() do
	task.spawn(playerAdded, player)
end
```

Always `return` after a failed load.

Bad:

```lua
if not profile then
	player:Kick("Failed")
end

print(profile.Data.Clicks)
```

Good:

```lua
if not profile then
	player:Kick("Failed")
	return
end

print(profile.Data.Clicks)
```

---

# Player Removing and BindToClose

## Important

`DataStore.new()` already installs:

- a `Players.PlayerRemoving` handler;
- a `game:BindToClose()` handler.

The built-in player-removal handler calls:

```lua
profile:ReleaseAsync("PlayerRemoving")
```

The built-in shutdown handler calls:

```lua
Store:CloseAsync()
```

Therefore, you normally **do not need** this:

```lua
Players.PlayerRemoving:Connect(function(player)
	Data:ReleasePlayerAsync(player)
end)

game:BindToClose(function()
	Data:CloseAsync()
end)
```

It is redundant for normal persistence lifecycle handling.

Your game script normally only needs:

```lua
Players.PlayerAdded:Connect(playerAdded)
```

plus the existing-player loop if the script can start after players already exist.

`CloseAsync()` is still public for manual lifecycle control or testing.

---

# Full Recommended Player Loader

```lua
--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DataStore = require(script.DataStore)
local PlayersData = require(script.PlayersData)
local NanoNum = require(ReplicatedStorage.NanoNum)

local Data = DataStore.new({
	Name = "ClickStore",

	DataTemplate = {
		Version = 1,
		Data = PlayersData,
	},

	StorageMode = "Buffer",

	CompressionEnabled = true,
	CompressionIndexedLayout = true,
	CompressionCompareAdaptiveTable = true,

	SessionCompressionEnabled = true,
	SessionStoreDiagnostics = false,
})

local function playerAdded(player: Player)
	local profile, loadError = Data:OpenPlayerAsync(player)

	if profile == nil then
		warn(
			"[DataStore] Failed to load",
			player.Name,
			loadError
		)

		player:Kick(
			"Data failed to load. Please rejoin."
		)

		return
	end

	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	leaderstats.Parent = player

	local playTime = Instance.new("StringValue")
	playTime.Name = "PlayTime"
	playTime.Value = NanoNum.formatTime(profile.Data.PlayTime)
	playTime.Parent = leaderstats
end

Players.PlayerAdded:Connect(playerAdded)

for _, player in Players:GetPlayers() do
	task.spawn(playerAdded, player)
end
```

The DataStore handles profile release and shutdown internally.

---

# Strict Typechecking

v2.1.0 exports strict types for the public API.

Important exported types include:

```lua
DataStore.DataTable
DataStore.DataTemplate
DataStore.LockMode
DataStore.StorageMode
DataStore.OpenOptions
DataStore.CompressionOptions
DataStore.Migration
DataStore.DataStoreConfig
DataStore.StorageStats
DataStore.PreparedStorage
DataStore.SessionLock
DataStore.SessionStats
DataStore.KeyInfo
DataStore.ProfileObject
DataStore.StoreObject
DataStore.SignalObject
```

Example:

```lua
local DataStore = require(script.DataStore)

type StoreObject = DataStore.StoreObject
type ProfileObject = DataStore.ProfileObject
type DataStoreConfig = DataStore.DataStoreConfig
```

---

# Game-Specific Player Type

The DataStore is generic and must support arbitrary game schemas.

For full autocomplete on your clicker-specific fields, define your own type:

```lua
type PlayerData = {
	Clicks: number,
	Rebirths: number,
	Ultra: number,
	Prestiges: number,

	Runes: {
		Common: number,
		Uncommon: number,
		Epic: number,
		Legendary: number,
	},

	PlayTime: number,
	ClickPlus: number,
}
```

Then:

```lua
local profile = Data:GetProfile(player)

if profile then
	local playerData = profile.Data :: PlayerData

	playerData.Clicks += playerData.ClickPlus
	playerData.Runes.Common += 1

	profile:MarkDirty()
end
```

Studio can now catch mistakes such as:

```lua
playerData.Clikcs += 1
```

because `Clikcs` is not part of `PlayerData`.

---

# Getting a Loaded Profile

```lua
local profile = Data:GetProfile(player)

if profile then
	print(profile.Data)
end
```

`GetProfile()` returns:

```text
ProfileObject?
```

so strict code should check it before use.

---

# Updating Data

## Get

```lua
local clicks = profile:Get("Clicks")
```

## Set

```lua
profile:Set("Clicks", 100)
```

`Set()`:

- validates the resulting profile;
- marks the profile dirty;
- fires `profile.Changed`.

## Increment

```lua
profile:Increment("Clicks", 1)
```

Default amount:

```lua
profile:Increment("Clicks")
```

adds `1`.

Using `ClickPlus`:

```lua
local clickPlus = profile:Get("ClickPlus")

profile:Increment(
	"Clicks",
	clickPlus
)
```

## Update

```lua
profile:Update(
	"Clicks",
	function(current)
		return (current or 0) * 2
	end
)
```

## Direct data editing

Direct mutation is allowed:

```lua
profile.Data.Clicks += 10
```

but DataStore cannot automatically observe arbitrary nested table assignments.

Call:

```lua
profile:MarkDirty()
```

after direct edits.

Example:

```lua
local data = profile.Data :: PlayerData

data.Clicks += data.ClickPlus
data.Runes.Legendary += 1

profile:MarkDirty()
```

---

# Nested Data

Your rune table remains normal at runtime:

```lua
profile.Data.Runes.Common
profile.Data.Runes.Uncommon
profile.Data.Runes.Epic
profile.Data.Runes.Legendary
```

A fixed nested map can still be represented by Compression's indexed/schema path.

You do not need to convert your runtime data into arrays manually.

---

# IndexedLayout

`Compression.IndexedLayout()` is the preferred candidate for fixed DataTemplates.

Conceptually:

```lua
{
	Clicks = 100,
	Rebirths = 2,
	Ultra = 0,
}
```

can be represented using a reusable field layout instead of writing:

```text
"Clicks"
"Rebirths"
"Ultra"
```

for every player.

The DataStore compiles layouts once per configured data version.

The layout is **not transmitted with every save**.

This is why historical layouts matter when the template changes.

---

# Adaptive Table Fallback

DataStore also creates an adaptive table candidate using:

```lua
Compression.CompressTablePacket(data)
```

This candidate is self-describing and is the safe fallback when IndexedLayout cannot represent the runtime structure.

Examples:

- dynamic inventory maps;
- new runtime fields not in the fixed layout;
- shapes that cannot be inferred from the template;
- data whose adaptive representation is simply smaller.

The DataStore compares candidate sizes and stores the winner.

---

# Candidate Selection

Default behavior:

```text
player data
   │
   ├── IndexedLayout
   │
   └── adaptive Compression table
   │
   ▼
compare
   │
   ▼
smallest valid candidate
```

Configuration:

```lua
CompressionIndexedLayout = true
CompressionCompareAdaptiveTable = true
```

If IndexedLayout is unavailable or rejects the current value, the adaptive table candidate is retained.

No data is intentionally dropped just to force indexed compression.

---

# Storage Frame v8

The DataStore stores a small outer frame around the Compression payload.

Conceptually:

```text
DataStore magic
storage format
codec kind
DataTemplate version
Compression payload
```

The outer frame tells DataStore:

- which DataStore storage format is in use;
- whether the payload used IndexedLayout or adaptive table encoding;
- which `DataTemplate.Version` should be used.

The actual player field data belongs to Compression.

The persisted Compression payload does **not** need to store the named wrapper:

```lua
{
	Version = 1,
	Data = ...
}
```

inside the table itself.

---

# Why Binary Mode Is Used

The persistence path intentionally uses:

```lua
Mode = "Binary"
```

Compression v3 can expose packet metadata such as hashes outside `Packet.Data`.

DataStore persists the actual buffer, so persistence does not pretend that out-of-band packet metadata is stored when it is not.

---

# DataTemplate Versions

Start with:

```lua
DataTemplate = {
	Version = 1,
	Data = PlayersData,
}
```

When the fixed template changes after players have already been saved with IndexedLayout:

1. preserve the old layout template;
2. increment `DataTemplate.Version`;
3. add a migration if the runtime data structure needs conversion.

---

# Compression Layout History

Example v1:

```lua
local V1 = {
	Clicks = 0,
	Rebirths = 0,
}
```

New v2:

```lua
local V2 = {
	Clicks = 0,
	Rebirths = 0,
	Gems = 0,
}
```

Configure:

```lua
local Data = DataStore.new({
	Name = "ClickStore",

	DataTemplate = {
		Version = 2,
		Data = V2,
	},

	CompressionLayoutHistory = {
		[1] = V1,
	},

	Migrations = {
		[2] = function(data)
			data.Gems = data.Gems or 0
			return data
		end,
	},
})
```

For migration convenience, the module can also reuse `SchemaHistory` when `CompressionLayoutHistory` is not provided.

`SchemaHistory` itself is now mainly a **legacy SchemaBuffer compatibility setting**.

For new v2.x IndexedLayout saves, prefer:

```lua
CompressionLayoutHistory
```

---

# Migrations

Migrations are indexed by the **target version**.

```lua
Migrations = {
	[2] = function(data, fromVersion, toVersion)
		data.Gems = data.Gems or 0
		return data
	end,

	[3] = function(data, fromVersion, toVersion)
		data.Runes = data.Runes or {
			Common = 0,
			Uncommon = 0,
			Epic = 0,
			Legendary = 0,
		}

		return data
	end,
}
```

A migration may:

- mutate `data` and return `nil`; or
- return a replacement table.

---

# Reconciliation

Enabled by default:

```lua
Reconcile = true
```

Reconciliation fills missing fixed map fields from the current configured template.

Example:

Current template:

```lua
{
	Clicks = 0,
	Rebirths = 0,
	PlayTime = 0,
}
```

Old loaded data:

```lua
{
	Clicks = 100,
	Rebirths = 2,
}
```

After reconciliation:

```lua
{
	Clicks = 100,
	Rebirths = 2,
	PlayTime = 0,
}
```

Migrations are still recommended when a schema change has gameplay meaning.

---

# Session Locking

Session locking uses:

```text
MemoryStoreService
```

while persistent player data uses:

```text
DataStoreService
```

Defaults:

```lua
SessionLocking = true
SessionLockTimeout = 180
LoadTimeout = 30
LockRetryInterval = 1
```

`OpenPlayerAsync()` supports:

```text
Wait
Cancel
Steal
```

---

# Lock Modes

## Wait

Default:

```lua
local profile, err = Data:OpenPlayerAsync(
	player,
	{
		Locked = "Wait",
	}
)
```

Waits until the lock becomes available or `LoadTimeout` expires.

## Cancel

```lua
local profile, err = Data:OpenPlayerAsync(
	player,
	{
		Locked = "Cancel",
	}
)
```

Immediately returns when another session owns the profile.

## Steal

```lua
local profile, err = Data:OpenPlayerAsync(
	player,
	{
		Locked = "Steal",
	}
)
```

Use this carefully because another live server may still believe it owns the profile.

---

# Session Compression v2

The new session path uses Compression v3's indexed layout.

Conceptually the session structure is:

```lua
{
	Id = ...,
	JobId = "",
	PlaceId = 0,
	TouchedAt = 0,
	Released = false,
}
```

With:

```lua
SessionStoreDiagnostics = false
```

the diagnostics remain at defaults.

The generated session GUID is normalized to a compact binary UUID representation before Compression encodes the session table.

Configuration:

```lua
SessionCompressionEnabled = true
SessionStoreDiagnostics = false
```

If session compression is disabled, the session lock falls back to a normal table representation.

---

# Autosave

Enabled by default:

```lua
AutoSave = true
AutoSaveInterval = 60
```

Minimum:

```text
10 seconds
```

The DataStore autosave loop saves dirty active profiles.

You do **not** need to manually save every time a click happens.

For high-frequency stats:

```lua
profile.Data.Clicks += profile.Data.ClickPlus
profile:MarkDirty()
```

and let autosave persist the state.

---

# Manual Saving

```lua
local success, saveError = profile:SaveAsync()

if not success then
	warn(
		"Save failed:",
		saveError
	)
end
```

Store equivalent:

```lua
local success, saveError =
	Data:SavePlayerAsync(player)
```

---

# Manual Release

Normally automatic on `PlayerRemoving`.

Manual profile release:

```lua
local success, releaseError =
	profile:ReleaseAsync("ManualRelease")
```

Store equivalent:

```lua
local success, releaseError =
	Data:ReleasePlayerAsync(
		player,
		"ManualRelease"
	)
```

`ReleaseAsync()` performs the final save before releasing session ownership.

---

# Manual CloseAsync

The store automatically registers `BindToClose`, but `CloseAsync()` remains public:

```lua
local success = Data:CloseAsync()

if not success then
	warn("One or more profiles did not close cleanly")
end
```

Calling it more than once is safe; an already closed store returns `true`.

---

# Compact Player Keys

Enabled by default:

```lua
CompactPlayerKeys = true
CompactKeyPrefix = "p"
```

Instead of:

```text
Player_10800269681
```

the UserId can be represented as a shorter Base62 key.

Inspect:

```lua
local info = Data:GetKeyInfo(player)

print("Key:", info.Key)
print("Key bytes:", info.KeyBytes)

print("Legacy key:", info.LegacyKey)
print("Legacy bytes:", info.LegacyKeyBytes)

print("Saved bytes:", info.SavedBytes)
print("Savings:", info.SavingsPercent)
```

Legacy keys can still be read and migrated.

Defaults:

```lua
MigrateLegacyPlayerKeys = true
DeleteLegacyPlayerKeys = true
```

The old key is removed only after a successful compact-key save.

---

# Inspecting Compression Layouts

Use:

```lua
local info = Data:GetCompressionLayoutInfo()

print(info)
```

This replaces the old SchemaBuffer-centric inspection model for new saves.

Legacy schema inspection remains available:

```lua
local legacy = Data:GetLegacySchemaInfo()

print(legacy)
```

`GetLegacySchemaInfo()` exists for older SchemaBuffer compatibility, not because new writes use SchemaBuffer.

---

# Storage Information

After a save:

```lua
local info = profile:GetStorageInfo()
```

Useful current fields include:

```lua
print(
	"Stored bytes:",
	info.LastBufferBytes
)

print(
	"Raw bytes:",
	info.LastRawBufferBytes
)

print(
	"Saved bytes:",
	info.LastCompressionSavedBytes
)

print(
	"Savings:",
	info.LastCompressionSavingsPercent
)

print(
	"Codec:",
	info.LastCompressionMode
)
```

Indexed candidate:

```lua
print(
	"Indexed layout enabled:",
	info.CompressionIndexedLayoutEnabled
)

print(
	"Indexed layout available:",
	info.IndexedLayoutAvailable
)

print(
	"Indexed candidate:",
	info.IndexedCandidateAvailable
)

print(
	"Indexed selected:",
	info.IndexedSelected
)

print(
	"Indexed candidate bytes:",
	info.LastIndexedCandidateBytes
)

print(
	"Indexed mode:",
	info.LastIndexedCandidateMode
)
```

Session:

```lua
print(
	"Session bytes:",
	info.LastSessionLockBytes
)

print(
	"Session raw bytes:",
	info.LastSessionRawBytes
)

print(
	"Session codec:",
	info.LastSessionCompressionMode
)
```

Compatibility fields with old `Schema*` names still exist in `GetStorageInfo()` so older debugging code does not immediately break.

For new code, prefer the `Indexed*` names.

---

# Example Storage Test

```lua
local Players = game:GetService("Players")

Players.PlayerAdded:Connect(function(player)
	local profile, loadError =
		Data:OpenPlayerAsync(player)

	if profile == nil then
		warn(loadError)
		player:Kick("Data failed to load.")
		return
	end

	profile:Set("Rebirths", 1)
	profile:Set("Clicks", 2234)

	local success, saveError =
		profile:SaveAsync()

	if not success then
		warn(saveError)
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
		"B"
	)

	print(
		"Stored:",
		info.LastBufferBytes,
		"B"
	)

	print(
		"Indexed candidate:",
		info.LastIndexedCandidateBytes,
		"B"
	)

	print(
		"Indexed selected:",
		info.IndexedSelected
	)
end)
```

Always use the actual reported values for the current Compression version and current template.

---

# Roblox Creator Hub Size vs Payload Size

`buffer.len()` and Creator Hub's displayed storage usage are not necessarily identical.

Use:

```lua
profile:GetStorageInfo()
```

to inspect the payload produced by this module.

Use Creator Hub separately to inspect Roblox's final platform-level storage representation.

A viewer showing Base64 or `Array (N)` is also displaying a representation of the stored buffer, not necessarily the same measurement as the module's compression statistics.

---

# Viewing Data Without Opening a Session

## Full DataTemplate

```lua
local dataTemplate, source, keySource =
	Data:ViewTemplateAsync(userId)

if dataTemplate then
	print(dataTemplate.Version)
	print(dataTemplate.Data)
	print(source)
	print(keySource)
end
```

## Data only

```lua
local data, version, source, keySource =
	Data:ViewAsync(userId)

if data then
	print("Version:", version)
	print("Source:", source)
	print("Key source:", keySource)
	print(data)
end
```

---

# Inspecting the Actual Stored Payload

```lua
local payload, payloadType, keySource =
	Data:GetStoredPayloadAsync(userId)

print(payloadType)
print(keySource)

if typeof(payload) == "buffer" then
	print(
		"Actual stored bytes:",
		buffer.len(payload)
	)
end
```

---

# Session Lock Inspection

```lua
local lockInfo, source, bytes =
	Data:GetSessionLockInfoAsync(userId)

if lockInfo == nil then
	warn(source)
else
	print(lockInfo)
	print("Source:", source)
	print("Bytes:", bytes)
end
```

---

# Static Compression Utilities

## Compress a DataTemplate

```lua
local packet =
	DataStore.CompressDataTemplate({
		Version = 1,

		Data = {
			Clicks = 100,
			Rebirths = 2,
		},
	})

print(packet.Bytes)
print(packet.Codec)
```

## Decompress

```lua
local decoded =
	DataStore.DecompressDataTemplate(
		packet.Data
	)

print(decoded)
```

## Generic encode/decode

```lua
local encoded =
	DataStore.Encode({
		Coins = 100,
	})

local decoded =
	DataStore.Decode(encoded)
```

---

# Legacy Buffer Helpers

The following remain primarily for compatibility:

```lua
DataStore.CompressStorageBuffer(...)
DataStore.DecompressStorageBuffer(...)
DataStore.CompactBufferExact(...)
```

New profile saves do not use the old BufferUtil/SchemaBuffer pipeline.

---

# Public Key Helpers

Encode a numeric UserId:

```lua
local encoded =
	DataStore.EncodeUserIdKey(
		10800269681
	)

print(encoded)
```

Decode:

```lua
local userId =
	DataStore.DecodeUserIdKey(
		encoded
	)

print(userId)
```

---

# Public Version Helpers

```lua
print(
	DataStore.Version()
)
```

returns:

```text
2.1.0
```

Storage format:

```lua
print(
	DataStore.FormatVersion()
)
```

returns:

```text
8
```

Compression:

```lua
print(
	DataStore.CompressionVersion()
)
```

returns:

```text
3.0.0
```

BufferUtil:

```lua
print(
	DataStore.BufferUtilVersion()
)
```

returns:

```text
Removed
```

Session format:

```lua
print(
	DataStore.SessionFormatVersion
)
```

returns:

```text
2
```

`DataStore.SchemaFormatVersion` remains exposed for **legacy SchemaBuffer decoding compatibility**.

It is not the current write format.

---

# Store API Reference

## Construction

```lua
DataStore.new(config)
```

Returns:

```text
StoreObject
```

## Profiles

```lua
Store:OpenPlayerAsync(subject, options?)
Store:LoadPlayerAsync(subject, options?)

Store:GetProfile(subject)

Store:SavePlayerAsync(subject)
Store:ReleasePlayerAsync(subject, reason?)
```

## Compression/layout inspection

```lua
Store:GetCompressionLayoutInfo()
Store:GetLegacySchemaInfo()
```

## Key inspection

```lua
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

Common conditions include:

```text
LoadFailed
DecodeFailed
MigrationFailed
InvalidLoadedData
SessionLost
SaveFailed
AutoSaveFailed
ViewDecodeFailed
LegacyKeyCleanupFailed
```

---

# Configuration Reference

| Option | Default | Description |
|---|---:|---|
| `Name` | required | Roblox DataStore name |
| `Scope` | `nil` | Optional DataStore scope |
| `KeyPrefix` | `"Player_"` | Legacy player key prefix |
| `CompactPlayerKeys` | `true` | Use compact Base62 keys |
| `CompactKeyPrefix` | `"p"` | Compact key prefix |
| `MigrateLegacyPlayerKeys` | `true` | Read legacy player keys |
| `DeleteLegacyPlayerKeys` | `true` | Remove legacy key after successful compact save |
| `DataTemplate.Version` | `1` | Current data version |
| `DataTemplate.Data` | `{}` | Default player data |
| `Migrations` | `nil` | Target-version migration callbacks |
| `RejectFutureDataVersion` | `true` | Reject newer stored versions |
| `Reconcile` | `true` | Fill missing fixed map fields |
| `AutoSave` | `true` | Enable autosave |
| `AutoSaveInterval` | `60` | Autosave interval; minimum `10` |
| `SessionLocking` | `true` | Enable MemoryStore ownership locks |
| `SessionLockTimeout` | `180` | Session lock TTL |
| `LoadTimeout` | `30` | Maximum Wait-mode lock wait |
| `LockRetryInterval` | `1` | Delay between Wait-mode attempts |
| `MemoryLockRetryAttempts` | `4` | MemoryStore retry attempts |
| `SessionCompressionEnabled` | `true` | Encode session lock with Compression v3 layout |
| `SessionStoreDiagnostics` | `false` | Include JobId/PlaceId/timestamp diagnostics |
| `RetryAttempts` | `5` | DataStore request attempts |
| `RetryDelay` | `0.75` | Retry base delay |
| `MaxRetryDelay` | `8` | Maximum retry delay |
| `ShutdownTimeout` | `25` | CloseAsync profile release window |
| `BudgetAware` | `true` | Wait for DataStore request budget |
| `BudgetWaitTimeout` | `10` | Maximum budget wait |
| `StorageMode` | `"Buffer"` | `"Buffer"` or `"Table"` |
| `CompressionEnabled` | `true` | Enable Compression-native storage |
| `CompressionIndexedLayout` | `true` | Build/use IndexedLayout candidate |
| `CompressionCompareAdaptiveTable` | `true` | Compare indexed vs adaptive candidate |
| `CompressionLayoutHistory` | `nil` | Historical templates keyed by DataVersion |
| `CompressionTableStrategy` | `"Auto"` | `Auto`, `Compact`, or `Dynamic` |
| `CompressionCompressStrings` | `true` | Enable compact string handling |
| `CompressionStringStrategy` | `"Auto"` | String strategy |
| `CompressionUseStringDictionary` | `true` | Repeated-string dictionary |
| `CompressionHomogeneousArrays` | `true` | Homogeneous-array codecs |
| `CompressionDeltaArrays` | `true` | Delta-array codecs |
| `CompressionRunLengthArrays` | `true` | RLE array codecs |
| `CompressionCompactMapKeys` | `true` | Compact map keys |
| `CompressionTableKeyMapping` | `true` | Repeated table-key mapping |
| `CompressionEntropyCoding` | `true` | Entropy coding candidates |
| `CompressionEntropyStrategy` | `"Auto"` | `Auto`, `Huffman`, `None` |
| `CompressionAllowExpansion` | `false` | Do not intentionally accept expansion |
| `MaxBufferBytes` | `3800000` | Maximum encoded buffer |
| `MaxDepth` | `64` | Maximum nested validation depth |
| `MaxTableEntries` | `100000` | Maximum validated entries |
| `Debug` | `false` | Debug warnings |

Legacy compatibility settings are still accepted:

```text
BufferUtilEnabled
BufferWriterInitialCapacity
SchemaBufferEnabled
SchemaBufferCompress
SchemaFallbackToGeneric
SchemaHistory
CompressionCompareLegacyBuffer
CompressionMinBufferBytes
CompressionMinSavingsBytes
CompressionBufferStrategy
CompressionBufferMinLength
CompressionBufferSearchDepth
CompressionBufferWindowSize
CompressionBufferMaxMatch
```

Do not treat the legacy SchemaBuffer/BufferUtil options as the preferred v2.x write path.

---

# Production Safety

## One profile owner

Do not run multiple independent persistence systems that all believe they own the same player key.

## Never trust client currency

DataStore validates storage structure.

It does not validate whether a client legitimately earned:

- clicks;
- rebirths;
- runes;
- purchases;
- rewards;
- progression.

Validate gameplay changes on the server.

## Never replace a failed load with empty data

Bad:

```lua
local profile =
	Data:OpenPlayerAsync(player)

if not profile then
	-- do not create and save fake empty data
end
```

A later write could overwrite a legitimate stored profile.

Kick or otherwise stop the player's persistent-data gameplay flow when loading fails.

## Keep profiles bounded

Compression reduces representation size.

It does not make unlimited:

- histories;
- inventories;
- logs;
- cached events;
- temporary runtime data

safe to persist.

---

# Legacy Compatibility

v2.1.0 can still decode supported older forms, including:

- v2.0 Compression-native storage frames;
- v1.9 SchemaBitBuffer;
- v1.8 SchemaBuffer;
- older direct Compression table frames;
- legacy SDSB / BufferV1 data;
- compressed legacy BufferV1 values;
- normal legacy table values;
- old `Player_<UserId>` keys.

After loading, the next successful save can rewrite the profile using the current v2.1.0 Compression-native format.

---

# Troubleshooting

## `requires Compression v3.0.0`

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
3.0.0
```

## `SessionLocked`

Another live session currently owns the player's lock.

Default behavior is:

```lua
Locked = "Wait"
```

## `SessionLost`

The server could no longer prove that it still owned the session lock.

The profile is deactivated to avoid unsafe writes.

## IndexedLayout is not selected

This is not automatically an error.

Check:

```lua
local info =
	profile:GetStorageInfo()

print(info.IndexedCandidateAvailable)
print(info.IndexedSelected)
print(info.LastIndexedCandidateBytes)
print(info.LastCompressionMode)
```

The adaptive table candidate may simply be smaller.

## Dynamic data falls back

Dynamic structures may use the adaptive table codec.

That is expected.

## Save appears larger in Creator Hub

Check:

```lua
local info =
	profile:GetStorageInfo()

print(
	"Actual payload:",
	info.LastBufferBytes
)
```

Creator Hub can display platform-level storage overhead beyond the raw Luau buffer size.

---

# Release Summary

**DataStore v2.1.0**

- strict Luau typing;
- storage format **8**;
- session format **2**;
- Compression **3.0.0**;
- BufferUtil removed from the active dependency tree;
- Compression-native player saves;
- IndexedLayout candidate for fixed templates;
- adaptive table fallback;
- automatic candidate comparison;
- default-eliding indexed schemas through Compression;
- dynamic-data-safe fallback;
- compressed MemoryStore session locks;
- binary UUID session IDs;
- automatic `PlayerRemoving` release handling;
- automatic `BindToClose` handling;
- autosave;
- compact Base62 player keys;
- legacy key migration;
- migrations;
- reconciliation;
- budget-aware retries;
- legacy save decoding;
- typed profile/store/config APIs;
- detailed compression/session/key statistics.
