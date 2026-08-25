# NexusDataStore

![Version](https://img.shields.io/badge/version-v6.2.1-4c8bf5)
![Language](https://img.shields.io/badge/language-Luau-00A2FF)
![Platform](https://img.shields.io/badge/platform-Roblox-111111)
![Runtime](https://img.shields.io/badge/runtime-server--only-orange)
![Compression](https://img.shields.io/badge/compression-codec%20621-6f42c1)

**NexusDataStore** is a session-based persistence framework for Roblox that centralizes player data loading, session ownership, validation, mutation tracking, compression, saving, retries, and shutdown handling behind one server-side API.

Instead of letting every gameplay system call `DataStoreService` directly, NexusDataStore follows one model:

```text
Open once
   ↓
Keep one active session
   ↓
Read / mutate session data
   ↓
Validate and track changes
   ↓
Queue / autosave
   ↓
Release on leave
```

> Current release: **v6.2.1**

---

## Why NexusDataStore?

Roblox `DataStoreService` gives you the persistence primitives, but production games usually need more around them:

- session ownership and stale-lock recovery;
- autosaving;
- retry handling with backoff;
- request-budget awareness;
- schema validation;
- versioned migrations;
- dirty-state tracking;
- save prioritization;
- safe transactions;
- mutation journals;
- runtime snapshots;
- data diffing and patching;
- compressed buffer persistence;
- compression compatibility across schema versions;
- cross-server messaging;
- diagnostics and health metrics;
- clean player-leave and shutdown handling.

NexusDataStore keeps those concerns in one place so gameplay systems work with a live **Session** instead of implementing their own persistence logic.

---

# Core Features

| Feature | Purpose |
|---|---|
| Session ownership | Prevents multiple servers from casually owning the same player profile |
| Stale lock recovery | Recovers expired session ownership |
| Autosave | Queues dirty sessions automatically |
| Manual saves | Save important changes immediately when required |
| Save priorities | `low`, `normal`, `high`, and `critical` |
| Budget awareness | Waits for Roblox DataStore request budget |
| Retries | Retries transient failures with delay/backoff |
| Heartbeats | Refreshes live session ownership |
| Templates | Reconciles missing default fields |
| Schema validation | Enforces expected data types and constraints |
| Migrations | Upgrades older schema versions |
| Transactions | Applies related changes atomically in memory |
| Patching | Applies structured mutation lists |
| Snapshots | Keeps limited in-memory rollback points |
| Mutation journal | Records tracked changes |
| Revision tracking | Tracks profile revisions and mutations |
| Direct mutation detection | Detects supported `session.Data` edits |
| Value bindings | Synchronizes Roblox `ValueBase` objects with session paths |
| Compression | Schema-aware bit/buffer persistence |
| Compression history | Decodes data written by older compression schemas |
| Compression reports | Measures raw vs encoded storage cost |
| Cross-server messages | Optional `MessagingService` integration |
| Diagnostics | Health, metrics, data size, queues, budget and session state |
| Lifecycle helpers | Automatic PlayerAdded / PlayerRemoving / BindToClose wiring |
| No external dependencies | Single server-side ModuleScript |

---

# Requirements

NexusDataStore is **server-only**.

The module asserts that it is running on the server, so do not require it from a `LocalScript`.

Recommended location:

```text
ServerScriptService
├── Data
│   └── NexusDataStore
├── PlayerData.server.lua
└── Systems
    ├── CurrencyService.lua
    ├── InventoryService.lua
    └── QuestService.lua
```

---

# Installation

Place the ModuleScript somewhere only server code needs to access it.

Example:

```lua
local ServerScriptService = game:GetService("ServerScriptService")

local NexusDataStore = require(
	ServerScriptService.Data.NexusDataStore
)
```

No separate `Start()` call is required.

Creating a store starts the internal store systems.

---

# Five-Minute Quick Start

## 1. Create the store

For v6.2.1, `DataTemplate` is a clean way to keep the data version, template, strict mode, and schema together.

```lua
local ServerScriptService = game:GetService("ServerScriptService")

local NexusDataStore = require(
	ServerScriptService.Data.NexusDataStore
)

local Store = NexusDataStore.new({
	Name = "PlayersDataV2",

	DataTemplate = {
		Version = 1,

		Data = {
			Coins = 0,
			Gems = 0,
			Level = 1,
			XP = 0,

			Inventory = {},

			Settings = {
				Music = true,
				SFX = true,
			},
		},

		Strict = true,

		Schema = {
			Coins = {
				Type = "number",
				Required = true,
				Integer = true,
				Min = 0,
				Encoding = "VarUInt",
				OmitDefault = true,
			},

			Gems = {
				Type = "number",
				Required = true,
				Integer = true,
				Min = 0,
				Encoding = "VarUInt",
				OmitDefault = true,
			},

			Level = {
				Type = "number",
				Required = true,
				Integer = true,
				Min = 1,
				Encoding = "VarUInt",
			},

			XP = {
				Type = "number",
				Required = true,
				Integer = true,
				Min = 0,
				Encoding = "VarUInt",
				OmitDefault = true,
			},

			Inventory = {
				Type = "table",
			},

			Settings = {
				Type = "table",

				Children = {
					Music = {
						Type = "boolean",
					},

					SFX = {
						Type = "boolean",
					},
				},
			},
		},
	},

	Compression = true,

	AutoSave = true,
	AutoSaveInterval = 30,

	LockTimeout = 120,
	RetryAttempts = 6,

	BudgetAware = true,
})
```

---

## 2. Attach the player lifecycle

The simplest production bootstrap is:

```lua
Store:AttachPlayerLifecycle(
	"Your data could not be loaded. Please rejoin."
)

Store:BindToClose()
```

`AttachPlayerLifecycle()`:

- opens a session when a player joins;
- kicks the player if the session cannot be opened;
- releases the session when the player leaves.

`BindToClose()` connects the store's shutdown flow to `game:BindToClose()`.

---

## 3. Wait for a session

Other server systems can wait for the central data system:

```lua
local session, err = Store:WaitForSession(player, 30)

if not session then
	warn("Data unavailable:", err)
	return
end

print(session.Data.Coins)
```

---

## 4. Change data

```lua
session:Add("Coins", 100)
session:Sub("Coins", 25)

session:Set("Level", 10)

print(session:Get("Coins"))
```

Convenience currency methods are also available:

```lua
session:Award("Coins", 250)

local success, err = session:Spend("Coins", 100)

if not success then
	warn("Could not spend coins:", err)
end
```

---

# Recommended Architecture

A larger game should normally have **one place that opens player sessions**.

Other systems should reuse the existing session.

```text
                    ┌─────────────────────┐
Player joins ──────►│   NexusDataStore    │
                    │     Open session    │
                    └──────────┬──────────┘
                               │
                               ▼
                     ┌───────────────────┐
                     │   Live Session    │
                     │   session.Data    │
                     └─────────┬─────────┘
                               │
          ┌────────────────────┼────────────────────┐
          ▼                    ▼                    ▼
   Currency System      Inventory System      Quest System
          │                    │                    │
          └────────────────────┼────────────────────┘
                               ▼
                    Validation / Journal
                               ▼
                       Save Queue / Retry
                               ▼
                         DataStoreService
```

Do **not** open a separate session from every gameplay system.

---

# Store Creation

Two configuration styles are supported.

## `DataTemplate` style

```lua
local Store = NexusDataStore.new({
	Name = "PlayersData",

	DataTemplate = {
		Version = 3,

		Data = {
			Coins = 0,
			Level = 1,
		},

		Strict = true,

		Schema = {
			Coins = {
				Type = "number",
				Integer = true,
				Min = 0,
			},

			Level = {
				Type = "number",
				Integer = true,
				Min = 1,
			},
		},
	},
})
```

## Separate template style

```lua
local Store = NexusDataStore.new({
	Name = "PlayersData",

	Template = {
		Coins = 0,
		Level = 1,
	},

	SchemaVersion = 3,

	Strict = true,

	Schema = {
		Coins = {
			Type = "number",
			Integer = true,
			Min = 0,
		},

		Level = {
			Type = "number",
			Integer = true,
			Min = 1,
		},
	},
})
```

---

# Player Lifecycle

## Automatic lifecycle

```lua
Store:AttachPlayerLifecycle()
Store:BindToClose()
```

This is the shortest setup.

---

## Manual lifecycle

Use this if you need custom load/release behavior.

```lua
local Players = game:GetService("Players")

Players.PlayerAdded:Connect(function(player)
	local session, err = Store:OpenPlayerAsync(player)

	if not session then
		warn(
			"[NexusDataStore] load failed:",
			player.Name,
			err
		)

		player:Kick(
			"Your data could not be loaded. Please rejoin."
		)

		return
	end

	print(
		"[NexusDataStore] loaded:",
		player.Name
	)
end)

Players.PlayerRemoving:Connect(function(player)
	local session = Store:GetSession(player)

	if not session then
		return
	end

	local success, err = Store:ReleaseAsync(session)

	if not success then
		warn(
			"[NexusDataStore] release failed:",
			player.Name,
			err
		)
	end
end)

game:BindToClose(function()
	Store:Close()
end)
```

---

# Sessions

A session is the live source of truth for one player while that profile is owned by the current server.

```lua
local session = Store:GetSession(player)

if session and session:IsActive() then
	print(session.Data)
end
```

Important session fields include:

```text
Store
Player
Key
Data
Revision
SchemaVersion
SessionId
Active
Dirty
```

Use:

```lua
session:IsActive()
```

before work that must only happen on an owned session.

---

# Paths

Most mutation APIs accept a path.

A path can be:

```lua
"Coins"
```

or:

```lua
{"Stats", "Level"}
```

or include numeric indexes:

```lua
{"Inventory", 1, "Quantity"}
```

Example:

```lua
session:Set(
	{"Settings", "Music"},
	false
)

local musicEnabled = session:Get(
	{"Settings", "Music"}
)
```

---

# Reading Data

## Read through the session

```lua
local coins = session:Get("Coins")
```

`Get()` returns a cloned value.

Check existence:

```lua
if session:Has("Coins") then
	print("Coins exists")
end
```

Fallback value:

```lua
local title = session:GetOr(
	"Title",
	"Rookie"
)
```

---

## Read through the store

```lua
local coins, err = Store:Read(
	player,
	"Coins"
)
```

The store helper accepts either a `Player` or a session object.

---

## Get the entire profile

```lua
local data, err = Store:GetData(player)
```

By default this returns a copy.

To request the live table:

```lua
local liveData, err = Store:GetData(
	player,
	false
)
```

Treat the live table carefully.

---

# Mutating Data

Tracked mutation methods should be your default choice.

## Set

```lua
local success, err = session:Set(
	"Coins",
	500
)
```

---

## Increment

```lua
session:Increment(
	"Coins",
	100
)
```

Alias:

```lua
session:Add(
	"Coins",
	100
)
```

Subtract:

```lua
session:Sub(
	"Coins",
	50
)
```

---

## Increment with limits

```lua
session:IncrementClamped(
	"Level",
	1,
	1,
	100
)
```

---

## Delete

```lua
session:Delete("TemporaryFlag")
```

---

## Insert

```lua
session:Insert(
	"Inventory",
	{
		Id = "Potion",
		Quantity = 1,
	}
)
```

Alias:

```lua
session:Append(
	"Inventory",
	item
)
```

---

## Remove array entry

```lua
session:RemoveAt(
	"Inventory",
	2
)
```

---

## Toggle boolean

```lua
session:Toggle(
	{"Settings", "Music"}
)
```

---

# Direct `session.Data` Changes

v6.2.1 enables direct-change detection by default:

```lua
DetectDirectChanges = true
```

This means code such as:

```lua
session.Data.Coins += 100
```

can be detected when NexusDataStore checks the session.

When a valid direct change is found, NexusDataStore can:

- mark the session dirty;
- add a journal entry;
- increment the mutation counter;
- emit `DirectMutationDetected`;
- emit `DataChanged` for discovered differences.

If the direct edit produces invalid data, the module restores the previously observed snapshot and emits `DirectMutationRejected`.

Tracked methods such as:

```lua
session:Set(...)
session:Increment(...)
session:Transaction(...)
```

are still recommended because they validate and record intent immediately.

---

# Transactions

Transactions are designed for changes that should succeed or fail together.

Example purchase:

```lua
local success, result = session:Transaction(function(tx)
	tx:Require(
		"Coins",
		function(coins)
			return coins >= 500
		end
	)

	tx:Increment(
		"Coins",
		-500
	)

	tx:Insert(
		"Inventory",
		{
			Id = "Sword",
			Quantity = 1,
		}
	)
end)

if not success then
	warn("Purchase failed:", result)
end
```

The live session is not replaced until the transaction callback succeeds and the resulting data passes validation.

---

## Reject a transaction

Returning `false` rolls the transaction back:

```lua
local success, err = session:Transaction(function(tx)
	if not canPurchase then
		return false
	end

	tx:Increment("Coins", -100)
end)
```

Errors thrown inside the callback also roll the transaction back.

---

## Transaction helpers

```lua
tx:Get(path)

tx:Set(path, value)
tx:Delete(path)

tx:Increment(path, amount)
tx:IncrementClamped(path, amount, minimum, maximum)

tx:Insert(path, value)
tx:RemoveAt(path, index)

tx:Require(path, expectedOrPredicate)
tx:CompareAndSet(path, expected, value)

tx:Savepoint(name)
tx:RollbackTo(name)

tx:Diff()
tx:Validate()

tx:Commit()
tx:Rollback()
```

For normal usage, let `session:Transaction()` handle final commit/rollback behavior.

---

# Patches

You can apply a list of mutations through one transaction.

```lua
local success, err = session:Patch({
	{
		Op = "Increment",
		Path = "Coins",
		Amount = 100,
	},

	{
		Op = "Set",
		Path = {"Settings", "Music"},
		Value = false,
	},

	{
		Op = "Insert",
		Path = "Inventory",
		Value = {
			Id = "Potion",
			Quantity = 1,
		},
	},
})
```

Supported patch operations include:

```text
Set
Replace
Add
Delete
Remove
Increment
Insert
```

---

# Snapshots

Snapshots are in-memory rollback points owned by the store.

Create one:

```lua
local snapshot = session:Snapshot(
	"BeforeTrade"
)
```

Restore it:

```lua
local success, err = session:Restore(
	snapshot
)
```

You can also use the store API:

```lua
local snapshot = Store:CreateSnapshot(
	session,
	"BeforeTrade"
)

local snapshots = Store:GetSnapshots(
	session
)

Store:RestoreSnapshot(
	session,
	snapshot
)
```

The number kept per session is limited by:

```lua
MaxSnapshots = 10
```

Snapshots are runtime tools, not permanent off-site backups.

---

# Data Diffing

Compare current data against another table:

```lua
local changes = session:Diff(otherData)
```

Compare current data against the last persisted snapshot:

```lua
local changes = session:DiffFromPersisted()
```

A change entry contains information such as:

```text
Path
Before
After
Operation
```

This is useful for diagnostics, administration, and auditing game-side changes.

---

# Mutation Journal

Tracked mutations are stored in the session journal.

```lua
local journal = session:GetJournal()

for _, entry in ipairs(journal) do
	print(
		entry.Id,
		entry.Operation,
		entry.Path
	)
end
```

Clear it:

```lua
session:ClearJournal()
```

Journal size is bounded by:

```lua
MaxJournalEntries = 1000
```

The journal is primarily an in-memory diagnostic feature. Avoid turning player profiles into permanent giant debug logs.

---

# Schema Validation

Schemas define what valid player data is allowed to contain.

Example:

```lua
Schema = {
	Coins = {
		Type = "number",
		Required = true,
		Integer = true,
		Min = 0,
	},

	Name = {
		Type = "string",
		Required = true,
		MinLength = 1,
		MaxLength = 32,
	},

	Class = {
		Type = "string",

		Enum = {
			"Warrior",
			"Mage",
			"Rogue",
		},

		Encoding = "Enum",

		Values = {
			"Warrior",
			"Mage",
			"Rogue",
		},
	},

	Inventory = {
		Type = "table",

		ArrayOf = {
			Type = "table",

			Children = {
				Id = {
					Type = "string",
				},

				Quantity = {
					Type = "number",
					Integer = true,
					Min = 1,
				},
			},
		},
	},
}
```

---

## Schema rule fields

v6.2.1 supports schema-rule fields including:

```text
Type
Required
Integer
Min
Max
MinLength
MaxLength
Bits
Encoding
Values
Enum
Children
ArrayOf
AllowUnknown
OmitDefault
Optional
Validate
```

Custom validator:

```lua
Coins = {
	Type = "number",
	Integer = true,
	Min = 0,

	Validate = function(value, path)
		if value > 1_000_000_000 then
			return "currency exceeds game limit"
		end

		return true
	end,
}
```

A validator can return:

```text
true
false
"custom error text"
```

---

# Strict Mode

Enable:

```lua
Strict = true
```

or inside `DataTemplate`:

```lua
DataTemplate = {
	Strict = true,
	Data = {...},
	Schema = {...},
}
```

Strict mode rejects fields that are not defined by the schema where unknown fields are not allowed.

Use strict schemas for important production profiles where accidental fields should be caught early.

---

# Template vs Schema

They solve different problems.

**Template**

> What should a new player's profile contain?

**Schema**

> What profile values are valid?

Example:

```lua
Data = {
	Coins = 0,
	Level = 1,
}

Schema = {
	Coins = {
		Type = "number",
		Integer = true,
		Min = 0,
	},

	Level = {
		Type = "number",
		Integer = true,
		Min = 1,
	},
}
```

---

# Compression

Compression is enabled by default:

```lua
Compression = true
```

NexusDataStore v6.2.1 builds a schema-aware compressed persistence format from your template and schema.

This means your in-game data remains normal Luau data:

```lua
session.Data
```

while the persistence layer can store an encoded buffer.

You should not build gameplay logic around the internal buffer layout.

---

## Common compression encodings

Schemas can explicitly choose an encoding:

```lua
Coins = {
	Type = "number",
	Integer = true,
	Min = 0,
	Encoding = "VarUInt",
}
```

Supported encoding names include forms of:

| Encoding | Typical use |
|---|---|
| `Bit` / `Bool` / `Boolean` | Booleans |
| `VarUInt` / `UInt` | Non-negative integers |
| `VarInt` / `SInt` / `ZigZag` | Signed integers |
| `UIntRange` / `Range` | Integer bounded by `Min` / `Max` |
| `Float32` | 32-bit floating point |
| `Float64` / `Number` | 64-bit floating point |
| `Quantized` / `QuantizedFloat` | Bounded lossy float |
| `Enum` | One value from a known list |
| `String` / `RawString` | UTF-8 strings |
| `Array` | Dense arrays |
| `Map` | Tables/maps |

If no encoding is supplied, NexusDataStore chooses an encoding from the rule and default value.

---

## Range encoding

For a value with a known range:

```lua
Level = {
	Type = "number",
	Integer = true,
	Min = 1,
	Max = 100,
	Encoding = "UIntRange",
}
```

The codec can use only enough bits to represent that range.

---

## Explicit bit width

```lua
Level = {
	Type = "number",
	Integer = true,
	Min = 0,
	Max = 255,
	Encoding = "UIntRange",
	Bits = 8,
}
```

`Bits` must still be large enough to represent the configured range.

---

## Quantized values

```lua
Volume = {
	Type = "number",
	Min = 0,
	Max = 1,
	Encoding = "Quantized",
	Bits = 8,
}
```

Quantization trades precision for a smaller bounded representation.

Only use it where small precision loss is acceptable.

---

## Enum encoding

```lua
Class = {
	Type = "string",

	Encoding = "Enum",

	Values = {
		"Warrior",
		"Mage",
		"Rogue",
	},
}
```

---

## Omit defaults

For fields that often remain at their default:

```lua
Rebirths = {
	Type = "number",
	Integer = true,
	Min = 0,
	Encoding = "VarUInt",
	OmitDefault = true,
}
```

The codec can store a compact marker instead of the full field value when it matches the template default.

---

## Optional values

```lua
Title = {
	Type = "string",
	Required = false,
	Optional = true,
}
```

Optional fields include presence information in the compressed representation.

---

# Compression Reports

You can measure a profile without saving it.

```lua
local report, err = Store:GetCompressionReport(
	session
)

if not report then
	warn(err)
	return
end

print("Raw bytes:", report.RawBytes)
print("Encoded bytes:", report.EncodedBytes)
print("Saved bytes:", report.SavedBytes)
print("Savings:", report.SavingsPercent)
print("Ratio:", report.Ratio)
```

Reports include:

```text
RawBytes
RawBits
EncodedBytes
EncodedBits
PayloadBytes
PayloadBits
HeaderBytes
SavedBytes
SavedBits
Ratio
SavingsPercent
Fields
```

---

## Print a compression report

```lua
Store:PrintCompressionReport(session)
```

---

## Measure key usage

```lua
local measurement, err =
	Store:MeasureCompressedData(session.Data)

if measurement then
	print(
		"Record bytes:",
		measurement.RecordBytes
	)

	print(
		"Remaining bytes:",
		measurement.RemainingBytes
	)

	print(
		"Percent of key limit:",
		measurement.PercentOfKeyLimit
	)
end
```

---

## Encode / decode manually

For tooling or tests:

```lua
local encoded, err = Store:EncodeCompressed(
	session.Data
)

if encoded then
	local decoded, record =
		Store:DecodeCompressed(encoded)
end
```

Do not normally use these methods for gameplay persistence. The store already handles encoding internally.

---

# Compression History

Changing a compression schema can make older compressed records impossible to interpret unless the old schema is still known.

`CompressionHistory` lets v6.2.1 keep older schema definitions available for decoding.

Example:

```lua
local Store = NexusDataStore.new({
	Name = "PlayersData",

	DataTemplate = {
		Version = 3,
		Data = CurrentTemplate,
		Schema = CurrentSchema,
		Strict = true,
	},

	CompressionHistory = {
		[1] = {
			Data = Version1Template,
			Schema = Version1Schema,
			Strict = true,
		},

		[2] = {
			Data = Version2Template,
			Schema = Version2Schema,
			Strict = true,
		},
	},
})
```

Keep historical compression definitions for old schema versions that may still exist in production.

---

# Migrations

Schema versions and migrations let data evolve safely.

Example:

```lua
local Store = NexusDataStore.new({
	Name = "PlayersData",

	DataTemplate = {
		Version = 3,

		Data = {
			Coins = 0,
			Gems = 0,

			Stats = {
				Level = 1,
				XP = 0,
			},
		},
	},

	Migrations = {
		[2] = function(data, context)
			data.Gems = data.Gems or 0
			return data
		end,

		[3] = function(data, context)
			data.Stats = data.Stats or {
				Level = 1,
				XP = 0,
			}

			return data
		end,
	},
})
```

The migration map is indexed by the target version.

Keep migrations that may still be needed by old live data.

---

# Saving

## Autosave

Enabled by default:

```lua
AutoSave = true
AutoSaveInterval = 30
```

Only dirty sessions need to be queued for autosave.

---

## Manual save

```lua
local success, err = session:Save()

if not success then
	warn("Save failed:", err)
end
```

Store equivalent:

```lua
Store:Save(
	player,
	"high"
)
```

---

## Save priorities

Supported names:

```text
low
normal
high
critical
```

Example:

```lua
session:Save("critical")
```

Internally, queued saves can be promoted when a higher priority request arrives for the same profile.

---

## When to manually save

Useful cases include:

- expensive purchases;
- rare rewards;
- prestige/rebirth;
- major inventory operations;
- admin edits;
- important progression checkpoints.

Do not manually save every small mutation.

Autosave should still handle normal persistence.

---

# Save Queue

The save pipeline centralizes persistence work:

```text
Dirty Session
     │
     ▼
Priority Save Queue
     │
     ▼
Budget Check
     │
     ▼
Retry Pipeline
     │
     ▼
UpdateAsync
     │
     ▼
Revision / Dirty State Update
```

This keeps gameplay systems from racing each other with independent `UpdateAsync()` calls.

---

# Budget Awareness

Enabled by default:

```lua
BudgetAware = true
```

The store considers:

```lua
DataStoreService:GetRequestBudgetForRequestType(
	Enum.DataStoreRequestType.UpdateAsync
)
```

before performing budget-sensitive work.

Default budget wait timeout:

```lua
BudgetWaitTimeout = 10
```

---

# Retry Handling

Defaults:

```lua
RetryAttempts = 6
RetryBaseDelay = 0.5
RetryMaxDelay = 10
```

Transient failures such as throttling and temporary service errors can be retried instead of being treated as immediately permanent.

---

# Session Locking

When a player profile is opened, the record includes session ownership information.

A second server cannot simply take a non-expired session.

Default lock timeout:

```lua
LockTimeout = 120
```

The default heartbeat interval is derived from the lock timeout and is clamped to at least 15 seconds.

With the default lock timeout, this resolves to approximately:

```text
40 seconds
```

---

## Stale session recovery

When stored ownership has expired, NexusDataStore can recover it and emits:

```text
StaleSessionRecovered
```

Do not set lock timeouts extremely low. Legitimate servers need time to maintain ownership.

---

# Heartbeats

Active sessions periodically refresh ownership when required.

Related events include:

```text
SessionHeartbeat
HeartbeatDeferred
HeartbeatFailed
SessionLost
```

If ownership is lost, the session is no longer safe to use as an active profile.

---

# Session Lookup

Get a session:

```lua
local session = Store:GetSession(player)
```

Alias:

```lua
local session = Store:Get(player)
```

Wait:

```lua
local session, err = Store:WaitForSession(
	player,
	30
)
```

Alias:

```lua
local session, err = Store:Wait(
	player,
	30
)
```

Find by session ID:

```lua
local session = Store:GetSessionById(
	sessionId
)
```

Get all active sessions:

```lua
local sessions =
	Store:GetActiveSessions()
```

Count:

```lua
local count =
	Store:CountSessions()
```

---

# Value Bindings

NexusDataStore can bind a session path to a Roblox `ValueBase`.

Example:

```lua
local leaderstats = Instance.new("Folder")
leaderstats.Name = "leaderstats"
leaderstats.Parent = player

local coins = Instance.new("IntValue")
coins.Name = "Coins"
coins.Parent = leaderstats

local binding = session:BindValue(
	"Coins",
	coins
)
```

The binding initially pushes the session value into the `ValueBase`.

By default it is two-way.

Disable ValueBase -> session writes:

```lua
local binding = session:BindValue(
	"Coins",
	coins,
	{
		TwoWay = false,
	}
)
```

Destroy a binding manually:

```lua
binding:Destroy()
```

Session-scoped bindings are also cleaned up with the session.

---

# Events

Listen with:

```lua
local connection = Store:On(
	"DataChanged",
	function(
		session,
		path,
		oldValue,
		newValue,
		entry
	)
		print(
			session.Player.Name,
			path,
			oldValue,
			newValue
		)
	end
)
```

One-time listener:

```lua
Store:Once(
	"SessionOpened",
	function(session)
		print(
			"Opened:",
			session.Player.Name
		)
	end
)
```

Disconnect:

```lua
connection:Disconnect()
```

---

## Store event names

v6.2.1 emits events including:

```text
BindingRejected
CompressionReport
CrossServer
DataChanged
DirectMutationDetected
DirectMutationRejected
HeartbeatDeferred
HeartbeatFailed
MigrationCompleted
MigrationStarted
PlayerLoadFailed
PlayerLoaded
SaveCompleted
SaveFailed
SaveQueued
SaveStarted
SessionAborted
SessionHeartbeat
SessionLost
SessionOpened
SessionReleased
ShutdownStarted
SnapshotCreated
SnapshotRestored
StaleSessionRecovered
TransactionCommitted
TransactionRolledBack
TransactionStarted
UpdateFailed
```

Use events to keep systems decoupled.

For example:

```text
DataChanged
    ├── Leaderstats
    ├── UI replication
    ├── Achievement checks
    └── Analytics
```

---

# Cross-Server Messages

Cross-server support is optional.

Enable it:

```lua
local Store = NexusDataStore.new({
	Name = "PlayersData",

	Template = {
		Coins = 0,
	},

	EnableCrossServer = true,
})
```

Default topic:

```text
NexusDataStore:<StoreName>
```

Override:

```lua
CrossServerTopic = "MyGame:PlayerData"
```

Publish:

```lua
local success, err = Store:Publish(
	"GlobalRefresh",
	{
		UserId = player.UserId,
	}
)
```

Incoming messages are exposed through the `CrossServer` store event.

This uses `MessagingService`; it is not a replacement for persistent storage.

---

# Diagnostics

## Store health

```lua
local health = Store:GetHealth()

print("Version:", health.Version)
print("Active:", health.ActiveSessions)
print("Dirty:", health.DirtySessions)
print("Queued:", health.QueuedSaves)
print("Budget:", health.UpdateBudget)
```

Health contains:

```text
Version
Closed
Closing
JobId
ActiveSessions
DirtySessions
QueuedSaves
UpdateBudget
Metrics
```

---

## Metrics

```lua
local metrics = Store:GetMetrics()

print(metrics.Opened)
print(metrics.Saved)
print(metrics.SaveFailed)
print(metrics.Retries)
print(metrics.Mutations)
print(metrics.Transactions)
print(metrics.Rollbacks)
print(metrics.ActiveSessions)
print(metrics.QueuedSaves)
```

Metrics include counters for:

```text
Opened
Released
LoadsFailed
Saved
SaveFailed
Retries
Mutations
Transactions
Rollbacks
Heartbeats
LocksRecovered
SessionLost
TypeErrors
BytesEncoded
LoadTime
SaveTime
ActiveSessions
QueuedSaves
SaveWorkerRunning
AverageLoadTime
AverageSaveTime
```

---

## Session status

```lua
local status = session:GetStatus()

print(status.Active)
print(status.Revision)
print(status.Dirty)
print(status.JournalSize)
print(status.LastSaveAge)
```

Session status includes information such as:

```text
Exists
Active
Key
SessionId
Revision
SchemaVersion
Dirty
MutationId
Age
LastTouchedAge
LastSaveAge
LastHeartbeatAge
LastSaveError
JournalSize
Bindings
```

---

## Data stats

```lua
local stats = session:GetStats()

print("Valid:", stats.Valid)
print("Bytes:", stats.Bytes)
print("Nodes:", stats.Nodes)
print("Revision:", stats.Revision)
```

---

# Validation

Validate arbitrary data using the current store rules:

```lua
local valid, err, details =
	Store:Validate(data)

if not valid then
	warn(err)
end
```

The module also validates:

- node count;
- encoded-size estimate;
- schema requirements;
- custom rules.

---

# Persistent Value Types

The generic persistence layer supports:

- `nil`;
- booleans;
- finite numbers;
- valid UTF-8 strings;
- dense arrays;
- map-like tables;
- string and number table keys.

Avoid storing unsupported runtime objects such as:

- Roblox Instances;
- functions;
- threads;
- connections;
- userdata that is not explicitly serialized by your own layer;
- circular tables.

Keep persistent data focused on information required to restore progression.

---

# Configuration Reference

| Option | Default | Description |
|---|---:|---|
| `Name` | required | Roblox DataStore name |
| `Scope` | `"Global"` | DataStore scope |
| `Template` | — | Default profile table |
| `Schema` | `nil` | Validation/compression schema |
| `Strict` | `false` | Strict schema handling |
| `DataTemplate` | `nil` | Combined version/data/schema definition |
| `SchemaVersion` | `1` | Current data schema version |
| `Migrations` | `{}` | Version migration callbacks |
| `Compression` | `true` | Use compressed persistence |
| `CompressionReports` | `false` | Emit compression reports during encoding |
| `CompressionHistory` | `{}` | Historical compression schemas |
| `AutoSave` | `true` | Enable automatic saving |
| `AutoSaveInterval` | `30` | Autosave interval; minimum 10 |
| `LockTimeout` | `120` | Session lock timeout; minimum 45 |
| `HeartbeatInterval` | `LockTimeout / 3` | Heartbeat interval; minimum 15 |
| `RetryAttempts` | `6` | Retry count |
| `RetryBaseDelay` | `0.5` | Initial retry delay |
| `RetryMaxDelay` | `10` | Maximum retry delay |
| `BudgetAware` | `true` | Respect DataStore request budget |
| `BudgetWaitTimeout` | `10` | Maximum budget wait |
| `MinimumSaveInterval` | `3` | Minimum save spacing |
| `MaxDataNodes` | `50000` | Maximum validated data-node count |
| `MaxDataBytes` | `3900000` | Maximum estimated encoded data size |
| `MaxJournalEntries` | `1000` | Mutation journal cap |
| `MaxSnapshots` | `10` | Snapshot cap per profile |
| `LoadTimeout` | `30` | Load timeout setting |
| `SaveTimeout` | `30` | Manual save wait timeout |
| `EnableCrossServer` | `false` | Enable MessagingService integration |
| `CrossServerTopic` | `"NexusDataStore:<Name>"` | MessagingService topic |
| `DetectDirectChanges` | `true` | Detect supported direct session table edits |
| `Debug` | `false` | Debug logging |

---

# Store API Reference

## Construction

```lua
NexusDataStore.new(config)
```

---

## Session lifecycle

```lua
Store:OpenPlayerAsync(player)
Store:Open(player)

Store:GetSession(player)
Store:Get(player)

Store:GetSessionById(sessionId)
Store:GetActiveSessions()
Store:CountSessions()

Store:WaitForSession(player, timeout)
Store:Wait(player, timeout)

Store:ReleaseAsync(session)
Store:Release(playerOrSession)

Store:AbortSession(session, {
	Confirmed = true,
})

Store:ReleaseAllAsync()
```

`AbortSession` intentionally requires:

```lua
Confirmed = true
```

because it releases ownership without normal session save semantics.

---

## Data access

```lua
Store:Read(playerOrSession, path)
Store:Write(playerOrSession, path, value)

Store:GetData(playerOrSession, copy?)

Store:Set(session, path, value)
Store:Delete(session, path)
Store:Increment(session, path, amount?)
Store:IncrementClamped(session, path, amount, minimum?, maximum?)
Store:Insert(session, path, value)
Store:RemoveAt(session, path, index)
Store:Update(session, callback)
Store:Transaction(session, callback)
Store:Patch(session, patches)
```

Convenience:

```lua
Store:Add(playerOrSession, path, amount?)
Store:Sub(playerOrSession, path, amount?)
Store:Mutate(playerOrSession, callback)
```

---

## Saving

```lua
Store:SaveAsync(session, priority?)
Store:Save(playerOrSession, priority?)

Store:FlushAsync(timeout?)
Store:ReleaseAllAsync()

Store:Close()
```

---

## Snapshots

```lua
Store:CreateSnapshot(session, label?)
Store:GetSnapshots(session)
Store:RestoreSnapshot(session, snapshot)
```

---

## Validation / metadata

```lua
Store:Validate(data)

Store:GetTemplate()
Store:GetSchema()
Store:GetVersion()

Store:GetSessionStatus(session)
Store:GetDataStats(session)

Store:GetMetrics()
Store:GetHealth()
```

---

## Compression

```lua
Store:GetCompressionSchema()

Store:EncodeCompressed(data)
Store:DecodeCompressed(buffer)

Store:GetCompressionReport(dataOrSession)
Store:PrintCompressionReport(dataOrSession)
Store:MeasureCompressedData(data)
```

The module also exposes:

```lua
NexusDataStore.Compression.Version
NexusDataStore.Compression.BuildSchema
NexusDataStore.Compression.BitWriter
NexusDataStore.Compression.BitReader
```

These are lower-level codec tools.

---

## Lifecycle / events / cross-server

```lua
Store:On(eventName, callback)
Store:Once(eventName, callback)

Store:AttachPlayerLifecycle(loadFailureMessage?)
Store:BindToClose()

Store:Publish(eventName, payload)
```

---

# Session API Reference

```lua
session:IsActive()

session:Get(path)
session:Read(path)
session:Has(path)
session:GetOr(path, fallback)

session:Set(path, value)
session:Write(path, value)

session:Delete(path)

session:Increment(path, amount?)
session:Add(path, amount?)
session:Sub(path, amount?)
session:IncrementClamped(path, amount, minimum?, maximum?)

session:Insert(path, value)
session:Append(path, value)
session:RemoveAt(path, index)

session:Toggle(path)

session:Award(path, amount)
session:Spend(path, amount)

session:Update(callback)

session:Transaction(callback)
session:Mutate(callback)
session:Patch(patches)

session:Snapshot(label?)
session:Restore(snapshot)

session:Diff(otherData)
session:DiffFromPersisted()

session:GetJournal()
session:ClearJournal()

session:Save(priority?)
session:Release()
session:Abort(options)

session:GetStatus()
session:GetStats()

session:GetKey()
session:GetSessionId()
session:GetAge()
session:GetLastSaveAge()

session:MarkDirty()
session:IsDirty()

session:BindValue(path, valueObject, options?)
```

---

# Transaction API Reference

```lua
tx:Get(path)

tx:Set(path, value)
tx:Delete(path)

tx:Increment(path, amount?)
tx:IncrementClamped(path, amount, minimum?, maximum?)

tx:Insert(path, value)
tx:RemoveAt(path, index)

tx:Require(path, expectedOrPredicate)
tx:CompareAndSet(path, expected, value)

tx:Savepoint(name)
tx:RollbackTo(name)

tx:Diff()
tx:Validate()

tx:Commit()
tx:Rollback()
```

---

# Convenience API Example

v6.2.1 includes a shorter API for common game code:

```lua
local session, err = Store:Open(player)

if not session then
	return
end

Store:Write(
	player,
	"Coins",
	100
)

Store:Add(
	player,
	"Coins",
	50
)

Store:Sub(
	player,
	"Coins",
	25
)

Store:Mutate(
	player,
	function(tx)
		tx:Increment(
			"Coins",
			100
		)
	end
)

Store:Save(
	player,
	"high"
)

Store:Release(player)
```

The full session API is still recommended when a system repeatedly accesses the same player.

---

# Example: Currency System

```lua
local function GiveCoins(
	player,
	amount
)
	if amount <= 0 then
		return false,
			"INVALID_AMOUNT"
	end

	local session = Store:GetSession(
		player
	)

	if not session
		or not session:IsActive() then
		return false,
			"NO_SESSION"
	end

	return session:Award(
		"Coins",
		amount
	)
end
```

Spend:

```lua
local function BuyUpgrade(
	player,
	price
)
	local session = Store:GetSession(
		player
	)

	if not session then
		return false,
			"NO_SESSION"
	end

	return session:Spend(
		"Coins",
		price
	)
end
```

---

# Example: Inventory Purchase

```lua
local function BuyItem(
	player,
	itemId,
	price
)
	local session = Store:GetSession(
		player
	)

	if not session then
		return false,
			"NO_SESSION"
	end

	return session:Transaction(function(tx)
		tx:Require(
			"Coins",
			function(coins)
				return coins >= price
			end
		)

		tx:Increment(
			"Coins",
			-price
		)

		tx:Insert(
			"Inventory",
			{
				Id = itemId,
				Quantity = 1,
			}
		)
	end)
end
```

Always validate item IDs, prices, ownership, permissions, and gameplay rules on the server.

---

# Example: Leaderstats

```lua
local function CreateLeaderstats(
	player,
	session
)
	local leaderstats =
		Instance.new("Folder")

	leaderstats.Name = "leaderstats"
	leaderstats.Parent = player

	local coins =
		Instance.new("IntValue")

	coins.Name = "Coins"
	coins.Parent = leaderstats

	session:BindValue(
		"Coins",
		coins
	)
end
```

This avoids writing a second copy of the persistence system just to keep leaderstats synchronized.

---

# Error Handling

Most operational APIs return a result plus an error string.

Example:

```lua
local success, err =
	session:Set(
		"Coins",
		-100
	)

if not success then
	warn(
		"Mutation rejected:",
		err
	)
end
```

Load:

```lua
local session, err =
	Store:OpenPlayerAsync(
		player
	)

if not session then
	warn(
		"Load failed:",
		err
	)
end
```

Potential operational errors include conditions such as:

```text
SESSION_LOCKED:<owner>
SESSION_INACTIVE
SESSION_NOT_FOUND
STORE_CLOSED
BUDGET_TIMEOUT
SAVE_TIMEOUT
FLUSH_TIMEOUT
SESSION_OWNERSHIP_LOST
TRANSACTION_PRECONDITION_FAILED
CROSS_SERVER_DISABLED
```

Treat returned errors as data. Do not silently continue with a fresh empty profile after a failed load.

---

# Production Safety

## Never trust the client

NexusDataStore protects persistence mechanics. It does not make client requests trustworthy.

The server must still validate:

- purchases;
- currency changes;
- inventory ownership;
- item IDs;
- rewards;
- trade state;
- cooldowns;
- permissions;
- admin actions;
- progression requirements.

---

## Never replace failed data with empty data

Bad:

```lua
local session = Store:OpenPlayerAsync(
	player
)

if not session then
	-- create fake empty data and continue
end
```

This can lead to valid player data being overwritten later.

Prefer failing the join or disabling persistent gameplay until a real session is available.

---

## Keep one session per player

Bad design:

```text
Currency opens a session
Inventory opens a session
Quests open a session
Trading opens a session
```

Preferred design:

```text
One NexusDataStore session
        │
        ├── Currency
        ├── Inventory
        ├── Quests
        └── Trading
```

---

## Keep data bounded

Avoid placing these in a player profile:

- giant histories;
- unnecessary logs;
- server-only temporary state;
- Instances;
- connections;
- cached objects that can be rebuilt;
- enormous arrays with no practical limit.

The profile should contain what is needed to restore persistent progress.

---

# Troubleshooting

## Player is kicked because data did not load

Inspect the error from:

```lua
local session, err =
	Store:OpenPlayerAsync(player)

print(err)
```

Common causes can include:

- another server still owns the session;
- request-budget timeout;
- malformed or incompatible stored data;
- migration failure;
- schema failure;
- compression schema history missing for older data;
- DataStore service failure.

Also inspect:

```lua
print(Store:GetHealth())
print(Store:GetMetrics())
```

---

## `SESSION_LOCKED`

Another live server still owns the stored session.

Do not bypass the lock by loading empty data.

The session can become available when ownership is released or the lock becomes stale.

---

## Compression data fails after a schema update

If old records were written under an older schema version, keep that schema in:

```lua
CompressionHistory
```

and make sure your normal `Migrations` path can still upgrade the decoded profile.

---

## Direct table edit was rejected

When:

```lua
DetectDirectChanges = true
```

NexusDataStore validates discovered direct edits.

If the edit violates the schema or limits, it restores the previously observed data and emits:

```text
DirectMutationRejected
```

Use tracked mutation methods to catch problems closer to the code that caused them.

---

## Saves are slow

Check:

```lua
local health = Store:GetHealth()
local metrics = Store:GetMetrics()

print(health.UpdateBudget)
print(health.QueuedSaves)
print(metrics.AverageSaveTime)
print(metrics.Retries)
```

A queue can grow when producers request saves faster than the configured save/budget path can process them.

---

# Production Checklist

Before shipping a game with NexusDataStore:

- [ ] Keep NexusDataStore server-only.
- [ ] Use one active session per player.
- [ ] Use a stable `Name`.
- [ ] Define a real template.
- [ ] Add a schema for important production data.
- [ ] Use `DataTemplate.Version` or `SchemaVersion`.
- [ ] Keep migrations for older live data.
- [ ] Keep `CompressionHistory` when compression schemas change.
- [ ] Validate the template at startup.
- [ ] Keep `BudgetAware = true` unless you have a measured reason not to.
- [ ] Release sessions on `PlayerRemoving`.
- [ ] Bind shutdown handling.
- [ ] Never trust the client for persistent mutations.
- [ ] Never replace a failed load with empty data.
- [ ] Use transactions for multi-field purchases/trades.
- [ ] Keep player profiles below configured size/node limits.
- [ ] Watch `GetHealth()` and `GetMetrics()` during stress tests.
- [ ] Test server hopping and stale locks.
- [ ] Test migration from old live versions.
- [ ] Test compression decode compatibility.
- [ ] Test shutdown with active dirty sessions.

---

# v6.2.1 Summary

NexusDataStore v6.2.1 combines the session/store architecture with the newer schema-aware compression path and convenience APIs.

Key v6.2.1 capabilities documented here include:

- `NexusDataStore.Version = "6.2.1"`;
- codec/compression version `621`;
- `DataTemplate`;
- schema-aware compression;
- `CompressionHistory`;
- compression size reports;
- direct session-data mutation detection;
- store convenience methods such as `Open`, `Get`, `Wait`, `Read`, `Write`, `Add`, `Sub`, `Mutate`, `Save`, and `Release`;
- session convenience methods such as `GetOr`, `Toggle`, `Append`, `Award`, `Spend`, and `Mutate`;
- session locking and heartbeats;
- priority save queues;
- transactions, patches, snapshots, diffs, and journals;
- optional cross-server messages;
- lifecycle helpers;
- store/session diagnostics.

---

# Design Summary

A healthy production setup looks like this:

```text
                        NexusDataStore v6.2.1
                                  │
                                  ▼
                        ┌───────────────────┐
                        │ OpenPlayerAsync() │
                        └─────────┬─────────┘
                                  │
                                  ▼
                        ┌───────────────────┐
                        │   Active Session  │
                        │   session.Data    │
                        └─────────┬─────────┘
                                  │
              ┌───────────────────┼───────────────────┐
              │                   │                   │
              ▼                   ▼                   ▼
        Tracked Mutations   Transactions        Direct Changes
              │                   │                   │
              └───────────────────┼───────────────────┘
                                  ▼
                          Schema Validation
                                  │
                                  ▼
                     Dirty State / Journal / Diff
                                  │
                                  ▼
                     Priority Save Queue / Budget
                                  │
                                  ▼
                         Retry + UpdateAsync
                                  │
                                  ▼
                       Compressed Buffer Record
                                  │
                                  ▼
                         Roblox DataStore
```

The goal is not to call DataStore more often.

The goal is to make persistent player data **predictable, validated, recoverable, observable, and centralized**.
