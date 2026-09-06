--!native
--!optimize 2

-- DataStore v3.1.0
-- Data-only persistence core.
--
-- Permanent DataStore value:
--
--     PlayersData
--         ↓
--     Compression.IndexedLayout
--         ↓
--     buffer
--         ↓
--     DataStore:SetAsync(key, buffer)
--
-- Nothing else is placed inside the permanent player value.
--
-- Session ownership is separate and lives only in MemoryStoreService.
-- Compression v3.1 IndexedLayout is the only permanent storage codec.
-- DataTemplate metadata remains runtime-only; only Data is persisted.

local Data = require(script.Parent.PlayersData)
export type DataTable = Data.Data

export type DataTemplate = {
	Version: number,
	Data: DataTable,
}

export type LockMode = "Wait" | "Cancel" | "Steal"
export type UserSubject = Player | number

export type OpenOptions = {
	Locked: LockMode?,
}

export type CompressionOptions = {
	Mode: "Binary"?,
	CompressStrings: boolean?,
	StringStrategy: string?,
	UseStringDictionary: boolean?,
	TableCompression: boolean?,
	HomogeneousArrays: boolean?,
	DeltaArrays: boolean?,
	RunLengthArrays: boolean?,
	CompactMapKeys: boolean?,
	TableKeyMapping: boolean?,
	TableStrategy: string?,
	CompressBuffers: boolean?,
	BufferStrategy: string?,
	BufferMinLength: number?,
	BufferSearchDepth: number?,
	BufferWindowSize: number?,
	BufferMaxMatch: number?,
	EntropyCoding: boolean?,
	EntropyStrategy: string?,
	AllowExpansion: boolean?,
}

type CompressionPacket = {
	Data: buffer,
	Bytes: number,
	Bits: number,
	RawBytes: number?,
	SavedBytes: number?,
	SavingsPercent: number?,
	Codec: string?,
	UsefulBits: number?,
	PhysicalBits: number?,
	PaddingBits: number?,
	[string]: any,
}

type IndexedLayoutObject = {
	Version: number,
	Keys: {string},
	Mode: string,
	Encode: (self: IndexedLayoutObject, value: DataTable, options: CompressionOptions?) -> CompressionPacket,
	Decode: (self: IndexedLayoutObject, packet: CompressionPacket | buffer, options: CompressionOptions?) -> DataTable,
	[string]: any,
}

type CompressionModule = {
	Version: () -> string,
	Pack: (value: any, options: CompressionOptions?) -> CompressionPacket,
	Unpack: (packet: CompressionPacket | buffer, options: CompressionOptions?) -> any,
	IndexedLayout: (template: DataTable, version: number?) -> IndexedLayoutObject,
	SchemaPacketVersion: (packet: CompressionPacket | buffer, options: CompressionOptions?) -> number?,
	[string]: any,
}

export type Migration = (data: DataTable, fromVersion: number, toVersion: number) -> DataTable?
export type Mutator = (data: DataTable) -> DataTable?

export type DataStoreConfig = {
	Name: string,
	Scope: string?,

	DataTemplate: DataTemplate,
	CompressionLayoutHistory: {[number | string]: DataTable | DataTemplate}?,
	Migrations: {[number]: Migration}?,
	RejectFutureDataVersion: boolean?,
	Reconcile: boolean?,

	CompactPlayerKeys: boolean?,
	KeyPrefix: string?,

	AutoSave: boolean?,
	AutoSaveInterval: number?,
	SaveOnlyDirty: boolean?,
	SaveOnRelease: boolean?,

	SessionLocking: boolean?,
	SessionLockTimeout: number?,
	SessionRefreshInterval: number?,
	LoadTimeout: number?,
	LockRetryInterval: number?,
	MemoryLockRetryAttempts: number?,

	RetryAttempts: number?,
	RetryDelay: number?,
	MaxRetryDelay: number?,
	ShutdownTimeout: number?,
	BudgetAware: boolean?,
	BudgetWaitTimeout: number?,

	CompressionCompressStrings: boolean?,
	CompressionStringStrategy: string?,
	CompressionUseStringDictionary: boolean?,
	CompressionHomogeneousArrays: boolean?,
	CompressionDeltaArrays: boolean?,
	CompressionRunLengthArrays: boolean?,
	CompressionCompactMapKeys: boolean?,
	CompressionTableKeyMapping: boolean?,
	CompressionTableStrategy: string?,
	CompressionEntropyCoding: boolean?,
	CompressionEntropyStrategy: string?,
	CompressionAllowExpansion: boolean?,
	CompressionBufferStrategy: string?,
	CompressionBufferMinLength: number?,
	CompressionBufferSearchDepth: number?,
	CompressionBufferWindowSize: number?,
	CompressionBufferMaxMatch: number?,

	MaxBufferBytes: number?,
	MaxDepth: number?,
	MaxTableEntries: number?,
	Debug: boolean?,
}

export type StorageInfo = {
	Version: number,
	PlayerKey: string,
	PlayerKeyBytes: number,
	StoredBytes: number?,
	RawBytes: number?,
	SavedBytes: number,
	SavingsPercent: number,
	Codec: string?,
	UsefulBits: number?,
	PhysicalBits: number?,
	PaddingBits: number?,
	Dirty: boolean,
	Revision: number,
	LastSavedRevision: number,
	LastSaveClock: number,
}

export type SessionLock = {
	Id: string,
	Released: boolean,
}

export type SessionInfo = {
	Id: string?,
	Released: boolean?,
	Bytes: number?,
	Codec: string?,
}

export type RuntimeStats = {
	Loads: number,
	LoadFailures: number,
	Saves: number,
	SaveFailures: number,
	Autosaves: number,
	SessionRefreshes: number,
	SessionRefreshFailures: number,
	SessionLosses: number,
	BytesWritten: number,
}

export type KeyInfo = {
	UserId: number,
	Key: string,
	KeyBytes: number,
	Compact: boolean,
}

export type SignalConnection = {
	Connected: boolean,
	Disconnect: (self: SignalConnection) -> (),
}

export type SignalObject = {
	_listeners: {[any]: (...any) -> ()},
	_destroyed: boolean,
	Connect: (self: SignalObject, callback: (...any) -> ()) -> SignalConnection,
	Once: (self: SignalObject, callback: (...any) -> ()) -> SignalConnection,
	Fire: (self: SignalObject, ...any) -> (),
	Destroy: (self: SignalObject) -> (),
}

export type ProfileObject = {
	Store: StoreObject,
	UserId: number,
	Player: Player?,
	Key: string,
	SessionId: string,
	Version: number,
	Data: DataTable,

	Changed: SignalObject,
	Saved: SignalObject,
	Released: SignalObject,

	_active: boolean,
	_saving: boolean,
	_releasing: boolean,
	_dirty: boolean,
	_revision: number,
	_lastSavedRevision: number,
	_lastSave: number,
	_lastBufferBytes: number?,
	_lastRawBufferBytes: number?,
	_lastCodec: string?,
	_lastUsefulBits: number?,
	_lastPhysicalBits: number?,
	_lastPaddingBits: number?,
	_lastSessionBytes: number?,
	_lastSessionCodec: string?,
	_releaseRequested: string?,

	_deactivate: (self: ProfileObject, reason: string?) -> (),
	_markChanged: (self: ProfileObject) -> (),
	_waitForSave: (self: ProfileObject) -> boolean,
	_snapshotForSave: (self: ProfileObject) -> (DataTable, CompressionPacket, number),

	IsActive: (self: ProfileObject) -> boolean,
	IsDirty: (self: ProfileObject) -> boolean,
	Get: (self: ProfileObject, key: any) -> any,
	GetDataCopy: (self: ProfileObject) -> DataTable,
	GetDataTemplate: (self: ProfileObject) -> DataTemplate,
	GetBuffer: (self: ProfileObject) -> buffer,
	ToBuffer: (self: ProfileObject) -> buffer,
	GetStorageInfo: (self: ProfileObject) -> StorageInfo,
	MarkDirty: (self: ProfileObject) -> (),
	Set: (self: ProfileObject, key: any, value: any) -> any,
	Update: (self: ProfileObject, key: any, callback: (any) -> any) -> any,
	Increment: (self: ProfileObject, key: any, amount: number?) -> number,
	Overwrite: (self: ProfileObject, data: DataTable) -> DataTable,
	Reconcile: (self: ProfileObject) -> DataTable,
	Mutate: (self: ProfileObject, callback: Mutator) -> DataTable,
	SaveAsync: (self: ProfileObject) -> (boolean, any?),
	ReleaseAsync: (self: ProfileObject, reason: string?) -> (boolean, any?),
}

export type StoreObject = {
	Name: string,
	Config: any,
	_store: any,
	_lockMap: any,
	_profiles: {[number]: ProfileObject},
	_opening: {[number]: boolean},
	_closed: boolean,
	_autosaveCursor: number,
	_heartbeatCursor: number,
	_playerRemovingConnection: RBXScriptConnection?,
	_stats: RuntimeStats,

	ProfileLoaded: SignalObject,
	ProfileReleased: SignalObject,
	Issue: SignalObject,

	_key: (self: StoreObject, userId: number) -> string,
	_lockKey: (self: StoreObject, userId: number) -> string,
	_makeLockValue: (self: StoreObject, sessionId: string, released: boolean) -> (buffer, number, string),
	_acquireSessionLock: (self: StoreObject, userId: number, sessionId: string, mode: LockMode) -> (boolean, any?, number?, string?),
	_refreshSessionLock: (self: StoreObject, profile: ProfileObject) -> (boolean, any?),
	_releaseSessionLock: (self: StoreObject, profile: ProfileObject | {UserId: number, SessionId: string}) -> (boolean, any?),
	_readStoredValue: (self: StoreObject, userId: number) -> (boolean, any, string),
	_autoSaveLoop: (self: StoreObject) -> (),
	_sessionHeartbeatLoop: (self: StoreObject) -> (),
	_openPlayerCore: (self: StoreObject, subject: UserSubject, options: OpenOptions?) -> (ProfileObject?, any?, any?),

	GetProfile: (self: StoreObject, subject: UserSubject) -> ProfileObject?,
	OpenPlayerAsync: (self: StoreObject, subject: UserSubject, options: OpenOptions?) -> (ProfileObject?, any?, any?),
	LoadPlayerAsync: (self: StoreObject, subject: UserSubject, options: OpenOptions?) -> (ProfileObject?, any?, any?),
	ViewTemplateAsync: (self: StoreObject, subject: UserSubject) -> (DataTemplate?, any?),
	ViewAsync: (self: StoreObject, subject: UserSubject) -> (DataTable?, any?, any?),
	GetStoredBufferAsync: (self: StoreObject, subject: UserSubject) -> (buffer?, any?),
	GetStoredPayloadAsync: (self: StoreObject, subject: UserSubject) -> (any, string?),
	GetSessionLockInfoAsync: (self: StoreObject, subject: UserSubject) -> (SessionInfo?, any?),
	SavePlayerAsync: (self: StoreObject, subject: UserSubject) -> (boolean, any?),
	ReleasePlayerAsync: (self: StoreObject, subject: UserSubject, reason: string?) -> (boolean, any?),
	FlushAsync: (self: StoreObject) -> (boolean, number),
	CloseAsync: (self: StoreObject) -> boolean,
	IsClosed: (self: StoreObject) -> boolean,
	GetLoadedProfiles: (self: StoreObject) -> {ProfileObject},
	GetRuntimeStats: (self: StoreObject) -> RuntimeStats,
	GetKeyInfo: (self: StoreObject, subject: UserSubject) -> KeyInfo,
	GetCompressionLayoutInfo: (self: StoreObject) -> {[string]: any},
}

local DataStoreService = game:GetService("DataStoreService")
local MemoryStoreService = game:GetService("MemoryStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local VERSION = "3.1.0"
local STORAGE_FORMAT_VERSION = 11
local SESSION_FORMAT_VERSION = 4
local REQUIRED_COMPRESSION_VERSION = "3.1.0"
local MAX_SAFE_INTEGER = 9007199254740991

local KEY_BASE62_ALPHABET = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
local KEY_BASE62_RADIX = #KEY_BASE62_ALPHABET

local SESSION_LAYOUT_VERSION = 1
local SESSION_TEMPLATE = {
	Id = buffer.create(16),
	Released = false,
}

local DEFAULTS = {
	Scope = nil,

	CompressionLayoutHistory = nil,
	Migrations = nil,
	RejectFutureDataVersion = true,
	Reconcile = true,

	CompactPlayerKeys = true,
	KeyPrefix = "p",

	AutoSave = true,
	AutoSaveInterval = 60,
	SaveOnlyDirty = true,
	SaveOnRelease = true,

	SessionLocking = true,
	SessionLockTimeout = 180,
	SessionRefreshInterval = 60,
	LoadTimeout = 30,
	LockRetryInterval = 1,
	MemoryLockRetryAttempts = 4,

	RetryAttempts = 5,
	RetryDelay = 0.75,
	MaxRetryDelay = 8,
	ShutdownTimeout = 25,
	BudgetAware = true,
	BudgetWaitTimeout = 10,

	CompressionCompressStrings = true,
	CompressionStringStrategy = "Auto",
	CompressionUseStringDictionary = true,
	CompressionHomogeneousArrays = true,
	CompressionDeltaArrays = true,
	CompressionRunLengthArrays = true,
	CompressionCompactMapKeys = true,
	CompressionTableKeyMapping = true,
	CompressionTableStrategy = "Auto",
	CompressionEntropyCoding = true,
	CompressionEntropyStrategy = "Auto",
	CompressionAllowExpansion = false,
	CompressionBufferStrategy = "Auto",
	CompressionBufferMinLength = 6,
	CompressionBufferSearchDepth = 32,
	CompressionBufferWindowSize = 32767,
	CompressionBufferMaxMatch = 66,

	MaxBufferBytes = 3800000,
	MaxDepth = 64,
	MaxTableEntries = 100000,
	Debug = false,
}

local Compression: CompressionModule? = nil
local SessionLayout: IndexedLayoutObject? = nil

local DataStore = {}
DataStore.__index = DataStore

local Profile = {}
Profile.__index = Profile

local Signal = {}
Signal.__index = Signal

local function getCompression(): CompressionModule
	if Compression ~= nil then
		return Compression
	end

	local moduleScript = assert(script:WaitForChild("Compression", 10), "DataStore v3.1.0 requires a child ModuleScript named Compression v3.1.0")
	local codec = require(moduleScript) :: CompressionModule

	assert(type(codec) == "table", "Compression must return a table")
	assert(type(codec.Version) == "function", "Compression.Version is required")
	assert(codec.Version() == REQUIRED_COMPRESSION_VERSION, "DataStore v3.1.0 requires Compression v3.1.0")
	assert(type(codec.IndexedLayout) == "function", "Compression.IndexedLayout is required")
	assert(type(codec.SchemaPacketVersion) == "function", "Compression.SchemaPacketVersion is required")
	assert(type(codec.Pack) == "function", "Compression.Pack is required")
	assert(type(codec.Unpack) == "function", "Compression.Unpack is required")

	Compression = codec
	return codec
end

local function getSessionLayout(): IndexedLayoutObject
	if SessionLayout ~= nil then
		return SessionLayout
	end

	SessionLayout = getCompression().IndexedLayout(SESSION_TEMPLATE, SESSION_LAYOUT_VERSION)
	return SessionLayout
end

local function debugWarn(config: any, ...: any): ()
	if config.Debug then
		warn("[DataStore v" .. VERSION .. "]", ...)
	end
end

function Signal.new(): SignalObject
	return setmetatable({
		_listeners = {},
		_destroyed = false,
	}, Signal) :: any
end

function Signal.Connect(self: SignalObject, callback: (...any) -> ()): SignalConnection
	assert(type(callback) == "function", "Signal:Connect expects a function")
	assert(not self._destroyed, "Signal is destroyed")

	local signal = self
	local token = {}
	local connection: SignalConnection = {Connected = true} :: any

	function connection:Disconnect(): ()
		if not connection.Connected then
			return
		end

		connection.Connected = false
		if not signal._destroyed then
			signal._listeners[token] = nil
		end
	end

	signal._listeners[token] = callback
	return connection
end

function Signal.Once(self: SignalObject, callback: (...any) -> ()): SignalConnection
	local connection: SignalConnection? = nil

	connection = self:Connect(function(...: any): ()
		local current = connection
		if current ~= nil then
			current:Disconnect()
		end
		callback(...)
	end)

	return assert(connection)
end

function Signal.Fire(self: SignalObject, ...: any): ()
	if self._destroyed then
		return
	end

	for _, callback in pairs(self._listeners) do
		task.spawn(callback, ...)
	end
end

function Signal.Destroy(self: SignalObject): ()
	if self._destroyed then
		return
	end

	self._destroyed = true
	table.clear(self._listeners)
end

local function cloneBuffer(source: buffer): buffer
	local length = buffer.len(source)
	local out = buffer.create(length)

	if length > 0 then
		buffer.copy(out, 0, source, 0, length)
	end

	return out
end

local function deepCopy(value: any, seen: {[any]: boolean}?): any
	if typeof(value) == "buffer" then
		return cloneBuffer(value)
	end

	if type(value) ~= "table" then
		return value
	end

	local visited = seen or {}

	if visited[value] then
		error("Circular tables cannot be copied", 3)
	end

	visited[value] = true

	local out = {}

	for key, child in pairs(value) do
		out[deepCopy(key, visited)] = deepCopy(child, visited)
	end

	visited[value] = nil
	return out
end

local function deepEqual(a: any, b: any, seen: {[any]: any}?): boolean
	if typeof(a) ~= typeof(b) then
		return false
	end

	if typeof(a) == "buffer" then
		local aBuffer = a :: buffer
		local bBuffer = b :: buffer
		local length = buffer.len(aBuffer)

		if length ~= buffer.len(bBuffer) then
			return false
		end

		for i = 0, length - 1 do
			if buffer.readu8(aBuffer, i) ~= buffer.readu8(bBuffer, i) then
				return false
			end
		end

		return true
	end

	if type(a) ~= "table" then
		return a == b
	end

	local visited = seen or {}

	if visited[a] ~= nil then
		return visited[a] == b
	end

	visited[a] = b

	for key, value in pairs(a) do
		if not deepEqual(value, b[key], visited) then
			visited[a] = nil
			return false
		end
	end

	for key in pairs(b) do
		if a[key] == nil then
			visited[a] = nil
			return false
		end
	end

	visited[a] = nil
	return true
end

local function isFiniteNumber(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function isArray(value: any): (boolean, number)
	if type(value) ~= "table" then
		return false, 0
	end

	local count = 0
	local maxIndex = 0

	for key in pairs(value) do
		if type(key) ~= "number" or key < 1 or key ~= math.floor(key) then
			return false, 0
		end

		count += 1
		maxIndex = math.max(maxIndex, key)
	end

	return count == maxIndex, maxIndex
end

type ValidateState = {
	Entries: number,
}

local function validateSavable(value: any, path: string, seen: {[any]: boolean}, depth: number, state: ValidateState, config: any): ()
	if depth > config.MaxDepth then
		error(path .. " exceeded MaxDepth", 3)
	end

	local robloxType = typeof(value)
	local valueType = type(value)

	if value == nil or valueType == "boolean" then
		return
	end

	if valueType == "number" then
		if not isFiniteNumber(value) then
			error(path .. " contains NaN or infinity", 3)
		end
		return
	end

	if valueType == "string" or robloxType == "buffer" then
		return
	end

	if robloxType == "Vector2" then
		if not isFiniteNumber(value.X) or not isFiniteNumber(value.Y) then
			error(path .. " contains a non-finite Vector2", 3)
		end
		return
	end

	if robloxType == "Vector3" then
		if not isFiniteNumber(value.X) or not isFiniteNumber(value.Y) or not isFiniteNumber(value.Z) then
			error(path .. " contains a non-finite Vector3", 3)
		end
		return
	end

	if robloxType == "Color3" then
		if not isFiniteNumber(value.R) or not isFiniteNumber(value.G) or not isFiniteNumber(value.B) then
			error(path .. " contains a non-finite Color3", 3)
		end
		return
	end

	if robloxType == "CFrame" then
		for _, component in ipairs({value:GetComponents()}) do
			if not isFiniteNumber(component) then
				error(path .. " contains a non-finite CFrame", 3)
			end
		end
		return
	end

	if robloxType == "UDim" or robloxType == "UDim2" or robloxType == "Rect" or robloxType == "NumberRange" or robloxType == "BrickColor" or robloxType == "DateTime" then
		return
	end

	if valueType ~= "table" then
		error(path .. " contains unsupported type " .. robloxType, 3)
	end

	if seen[value] then
		error(path .. " contains a circular table", 3)
	end

	seen[value] = true

	local numericKeys = 0
	local stringKeys = 0
	local maxIndex = 0

	for key, child in pairs(value) do
		state.Entries += 1

		if state.Entries > config.MaxTableEntries then
			error(path .. " exceeded MaxTableEntries", 3)
		end

		if type(key) == "number" then
			if key < 1 or key ~= math.floor(key) then
				error(path .. " contains an invalid numeric key", 3)
			end

			numericKeys += 1
			maxIndex = math.max(maxIndex, key)
		elseif type(key) == "string" then
			stringKeys += 1
		else
			error(path .. " contains unsupported key type " .. type(key), 3)
		end

		if numericKeys > 0 and stringKeys > 0 then
			error(path .. " mixes numeric and string keys", 3)
		end

		validateSavable(child, path .. "." .. tostring(key), seen, depth + 1, state, config)
	end

	if numericKeys > 0 and numericKeys ~= maxIndex then
		error(path .. " contains a numeric array with gaps", 3)
	end

	seen[value] = nil
end

local function validateData(data: DataTable, config: any): ()
	validateSavable(data, "Data", {}, 0, {Entries = 0}, config)
end

local function validateTemplateShape(data: any, template: any, path: string): ()
	if type(data) ~= "table" or type(template) ~= "table" then
		return
	end

	local templateIsArray = isArray(template)
	local dataIsArray = isArray(data)

	if templateIsArray then
		if not dataIsArray then
			error(path .. " must remain an array", 3)
		end
		return
	end

	if dataIsArray then
		error(path .. " must remain a keyed table", 3)
	end

	for key, value in pairs(data) do
		if template[key] == nil then
			error(path .. "." .. tostring(key) .. " is not declared in DataTemplate.Data", 3)
		end

		local templateValue = template[key]

		if type(value) == "table" and type(templateValue) == "table" then
			validateTemplateShape(value, templateValue, path .. "." .. tostring(key))
		end
	end
end

local function reconcile(target: DataTable, template: DataTable): (DataTable, boolean)
	local targetIsArray = isArray(target)
	local templateIsArray = isArray(template)

	if targetIsArray or templateIsArray then
		return target, false
	end

	local changed = false

	for key, defaultValue in pairs(template) do
		local current = target[key]

		if current == nil then
			target[key] = deepCopy(defaultValue)
			changed = true
		elseif type(current) == "table" and type(defaultValue) == "table" then
			local _, nestedChanged = reconcile(current, defaultValue)
			changed = changed or nestedChanged
		end
	end

	return target, changed
end

local function compressionOptions(config: any): CompressionOptions
	return {
		Mode = "Binary",
		TableCompression = true,
		TableStrategy = config.CompressionTableStrategy,
		CompressStrings = config.CompressionCompressStrings,
		StringStrategy = config.CompressionStringStrategy,
		UseStringDictionary = config.CompressionUseStringDictionary,
		HomogeneousArrays = config.CompressionHomogeneousArrays,
		DeltaArrays = config.CompressionDeltaArrays,
		RunLengthArrays = config.CompressionRunLengthArrays,
		CompactMapKeys = config.CompressionCompactMapKeys,
		TableKeyMapping = config.CompressionTableKeyMapping,
		CompressBuffers = true,
		BufferStrategy = config.CompressionBufferStrategy,
		BufferMinLength = config.CompressionBufferMinLength,
		BufferSearchDepth = config.CompressionBufferSearchDepth,
		BufferWindowSize = config.CompressionBufferWindowSize,
		BufferMaxMatch = config.CompressionBufferMaxMatch,
		EntropyCoding = config.CompressionEntropyCoding,
		EntropyStrategy = config.CompressionEntropyStrategy,
		AllowExpansion = config.CompressionAllowExpansion,
	}
end

local function mergeConfig(config: DataStoreConfig): any
	local out = table.clone(DEFAULTS)

	for key, value in pairs(config) do
		out[key] = value
	end

	out.Name = config.Name
	out.DataTemplate = deepCopy(config.DataTemplate)
	out.DataVersion = config.DataTemplate.Version
	out.Template = deepCopy(config.DataTemplate.Data)
	out._LayoutsPrepared = false
	out._LayoutsByVersion = {}
	out._LayoutErrors = {}

	return out
end

local function validateConfig(config: any): ()
	assert(type(config.Name) == "string" and #config.Name > 0, "Config.Name must be a non-empty string")
	assert(type(config.DataTemplate) == "table", "Config.DataTemplate is required")
	assert(type(config.DataTemplate.Data) == "table", "Config.DataTemplate.Data must be a table")
	assert(type(config.DataVersion) == "number" and config.DataVersion >= 0 and config.DataVersion == math.floor(config.DataVersion), "DataTemplate.Version must be a non-negative integer")
	assert(type(config.KeyPrefix) == "string" and #config.KeyPrefix > 0 and #config.KeyPrefix <= 16, "Config.KeyPrefix must be 1..16 bytes")
	assert(type(config.CompactPlayerKeys) == "boolean", "Config.CompactPlayerKeys must be a boolean")
	assert(type(config.AutoSave) == "boolean", "Config.AutoSave must be a boolean")
	assert(type(config.AutoSaveInterval) == "number" and config.AutoSaveInterval >= 10, "AutoSaveInterval must be at least 10")
	assert(type(config.SaveOnlyDirty) == "boolean", "SaveOnlyDirty must be a boolean")
	assert(type(config.SaveOnRelease) == "boolean", "SaveOnRelease must be a boolean")
	assert(type(config.SessionLocking) == "boolean", "SessionLocking must be a boolean")
	assert(type(config.SessionLockTimeout) == "number" and config.SessionLockTimeout >= 30, "SessionLockTimeout must be at least 30")
	assert(type(config.SessionRefreshInterval) == "number" and config.SessionRefreshInterval >= 5, "SessionRefreshInterval must be at least 5")
	assert(config.SessionRefreshInterval < config.SessionLockTimeout, "SessionRefreshInterval must be smaller than SessionLockTimeout")
	assert(type(config.LoadTimeout) == "number" and config.LoadTimeout > 0, "LoadTimeout must be > 0")
	assert(type(config.LockRetryInterval) == "number" and config.LockRetryInterval > 0, "LockRetryInterval must be > 0")
	assert(type(config.MemoryLockRetryAttempts) == "number" and config.MemoryLockRetryAttempts >= 1, "MemoryLockRetryAttempts must be >= 1")
	assert(type(config.RetryAttempts) == "number" and config.RetryAttempts >= 1, "RetryAttempts must be >= 1")
	assert(type(config.RetryDelay) == "number" and config.RetryDelay >= 0, "RetryDelay must be >= 0")
	assert(type(config.MaxRetryDelay) == "number" and config.MaxRetryDelay >= config.RetryDelay, "MaxRetryDelay must be >= RetryDelay")
	assert(type(config.ShutdownTimeout) == "number" and config.ShutdownTimeout > 0, "ShutdownTimeout must be > 0")
	assert(type(config.BudgetWaitTimeout) == "number" and config.BudgetWaitTimeout > 0, "BudgetWaitTimeout must be > 0")
	assert(type(config.MaxBufferBytes) == "number" and config.MaxBufferBytes > 0, "MaxBufferBytes must be > 0")
	assert(type(config.MaxDepth) == "number" and config.MaxDepth >= 1, "MaxDepth must be >= 1")
	assert(type(config.MaxTableEntries) == "number" and config.MaxTableEntries >= 1, "MaxTableEntries must be >= 1")
	assert(config.CompressionLayoutHistory == nil or type(config.CompressionLayoutHistory) == "table", "CompressionLayoutHistory must be nil or a table")
	assert(config.Migrations == nil or type(config.Migrations) == "table", "Migrations must be nil or a table")

	validateData(config.Template, config)
	validateTemplateShape(config.Template, config.Template, "Data")
end

local function prepareLayouts(config: any): ()
	if config._LayoutsPrepared then
		return
	end

	config._LayoutsPrepared = true

	local codec = getCompression()

	local function addLayout(dataVersion: number?, template: any): ()
		if type(dataVersion) ~= "number" or dataVersion < 0 or dataVersion ~= math.floor(dataVersion) or type(template) ~= "table" then
			return
		end

		if config._LayoutsByVersion[dataVersion] ~= nil then
			return
		end

		local ok, layout = pcall(codec.IndexedLayout, template, dataVersion + 1)

		if ok and type(layout) == "table" then
			config._LayoutsByVersion[dataVersion] = layout
		else
			config._LayoutErrors[dataVersion] = tostring(layout)
		end
	end

	addLayout(config.DataVersion, config.Template)

	if type(config.CompressionLayoutHistory) == "table" then
		for rawVersion, historical in pairs(config.CompressionLayoutHistory) do
			local version = if type(rawVersion) == "number" then rawVersion else tonumber(rawVersion)
			local template = historical

			if type(historical) == "table" and type(historical.Data) == "table" then
				template = historical.Data
			end

			addLayout(version, template)
		end
	end
end

local function getLayout(config: any, dataVersion: number): IndexedLayoutObject?
	prepareLayouts(config)
	return config._LayoutsByVersion[dataVersion]
end

local function getTemplateForVersion(config: any, dataVersion: number): DataTable?
	if dataVersion == config.DataVersion then
		return config.Template
	end

	if type(config.CompressionLayoutHistory) ~= "table" then
		return nil
	end

	local historical = config.CompressionLayoutHistory[dataVersion]

	if historical == nil then
		historical = config.CompressionLayoutHistory[tostring(dataVersion)]
	end

	if type(historical) ~= "table" then
		return nil
	end

	if type(historical.Data) == "table" then
		return historical.Data
	end

	return historical
end

local function encodePlayerData(data: DataTable, dataVersion: number, config: any): CompressionPacket
	validateData(data, config)

	local template = getTemplateForVersion(config, dataVersion)

	if template == nil then
		error("No Compression layout template exists for DataVersion " .. tostring(dataVersion), 2)
	end

	validateTemplateShape(data, template, "Data")

	local layout = getLayout(config, dataVersion)

	if layout == nil then
		error("Compression layout unavailable for DataVersion " .. tostring(dataVersion) .. ": " .. tostring(config._LayoutErrors[dataVersion]), 2)
	end

	local packet = layout:Encode(data, compressionOptions(config))

	if typeof(packet.Data) ~= "buffer" then
		error("Compression IndexedLayout returned an invalid packet", 2)
	end

	local bytes = buffer.len(packet.Data)

	if bytes > config.MaxBufferBytes then
		error(string.format("Encoded player data is %d bytes, above MaxBufferBytes (%d)", bytes, config.MaxBufferBytes), 2)
	end

	return packet
end

local function decodePlayerData(value: buffer, config: any): DataTemplate
	if buffer.len(value) > config.MaxBufferBytes then
		error("Stored player buffer exceeds MaxBufferBytes", 2)
	end

	local codec = getCompression()
	local schemaVersion = codec.SchemaPacketVersion(value, compressionOptions(config))

	if schemaVersion == nil or schemaVersion < 1 then
		error("Stored value is not a DataStore v3.1 IndexedSchema packet", 2)
	end

	local dataVersion = schemaVersion - 1
	local layout = getLayout(config, dataVersion)

	if layout == nil then
		error("Stored DataVersion " .. tostring(dataVersion) .. " has no CompressionLayoutHistory entry", 2)
	end

	local data = layout:Decode(value, compressionOptions(config))

	if type(data) ~= "table" then
		error("Compression decoded a non-table player value", 2)
	end

	validateData(data, config)

	local template = getTemplateForVersion(config, dataVersion)

	if template ~= nil then
		validateTemplateShape(data, template, "Data")
	end

	return {
		Version = dataVersion,
		Data = deepCopy(data),
	}
end

local function encodeBase62UInt(value: number): string
	assert(value >= 0 and value <= MAX_SAFE_INTEGER and value == math.floor(value), "Base62 expects a non-negative safe integer")

	if value == 0 then
		return "0"
	end

	local chars = {}

	while value > 0 do
		local remainder = value % KEY_BASE62_RADIX
		value = math.floor(value / KEY_BASE62_RADIX)
		chars[#chars + 1] = string.sub(KEY_BASE62_ALPHABET, remainder + 1, remainder + 1)
	end

	local left = 1
	local right = #chars

	while left < right do
		chars[left], chars[right] = chars[right], chars[left]
		left += 1
		right -= 1
	end

	return table.concat(chars)
end

local function decodeBase62UInt(value: string): number
	assert(type(value) == "string" and #value > 0, "Base62 expects a non-empty string")

	local result = 0

	for i = 1, #value do
		local byte = string.byte(value, i)
		local digit: number

		if byte >= 48 and byte <= 57 then
			digit = byte - 48
		elseif byte >= 65 and byte <= 90 then
			digit = byte - 65 + 10
		elseif byte >= 97 and byte <= 122 then
			digit = byte - 97 + 36
		else
			error("Invalid Base62 character", 2)
		end

		result = result * KEY_BASE62_RADIX + digit

		if result > MAX_SAFE_INTEGER then
			error("Base62 value exceeds Luau safe integer range", 2)
		end
	end

	return result
end

local function guidHex(value: any): string?
	if type(value) ~= "string" then
		return nil
	end

	local compact = string.gsub(value, "-", "")

	if #compact ~= 32 or string.find(compact, "[^0-9a-fA-F]") ~= nil then
		return nil
	end

	return string.lower(compact)
end

local function guidToBuffer(value: any): buffer?
	local compact = guidHex(value)

	if compact == nil then
		return nil
	end

	local out = buffer.create(16)

	for i = 1, 32, 2 do
		local byte = tonumber(string.sub(compact, i, i + 1), 16)

		if byte == nil then
			return nil
		end

		buffer.writeu8(out, (i - 1) // 2, byte)
	end

	return out
end

local function bufferToGuid(value: any): string?
	if typeof(value) ~= "buffer" or buffer.len(value) ~= 16 then
		return nil
	end

	local parts = table.create(16)

	for i = 0, 15 do
		parts[i + 1] = string.format("%02x", buffer.readu8(value, i))
	end

	local compact = table.concat(parts)

	return string.sub(compact, 1, 8)
		.. "-"
		.. string.sub(compact, 9, 12)
		.. "-"
		.. string.sub(compact, 13, 16)
		.. "-"
		.. string.sub(compact, 17, 20)
		.. "-"
		.. string.sub(compact, 21, 32)
end

local function encodeSession(session: SessionLock, config: any): (buffer, number, string)
	local idBuffer = assert(guidToBuffer(session.Id), "Session Id must be a GUID")
	local packet = getSessionLayout():Encode({
		Id = idBuffer,
		Released = session.Released,
	}, compressionOptions(config))

	return packet.Data, buffer.len(packet.Data), packet.Codec or "IndexedSchema"
end

local function decodeSession(value: any, config: any): SessionLock?
	if typeof(value) ~= "buffer" then
		return nil
	end

	local ok, decoded = pcall(function(): DataTable
		return getSessionLayout():Decode(value, compressionOptions(config))
	end)

	if not ok or type(decoded) ~= "table" then
		return nil
	end

	local id = bufferToGuid(decoded.Id)

	if id == nil then
		return nil
	end

	return {
		Id = id,
		Released = decoded.Released == true,
	}
end

local function sessionIdsEqual(a: string?, b: string?): boolean
	if a == b then
		return true
	end

	local aHex = guidHex(a)
	local bHex = guidHex(b)

	return aHex ~= nil and bHex ~= nil and aHex == bHex
end

local function waitForBudget(config: any, requestType: Enum.DataStoreRequestType): (boolean, string?)
	if not config.BudgetAware then
		return true
	end

	local deadline = os.clock() + config.BudgetWaitTimeout

	while DataStoreService:GetRequestBudgetForRequestType(requestType) <= 0 do
		if os.clock() >= deadline then
			return false, "DataStoreBudgetTimeout"
		end

		task.wait(0.25)
	end

	return true
end

local function retryDataStore(config: any, requestType: Enum.DataStoreRequestType, callback: () -> any): (boolean, any)
	local lastError: any = nil

	for attempt = 1, config.RetryAttempts do
		local budgetOk, budgetError = waitForBudget(config, requestType)

		if budgetOk then
			local ok, result = pcall(callback)

			if ok then
				return true, result
			end

			lastError = result
		else
			lastError = budgetError
		end

		if attempt < config.RetryAttempts then
			local delayTime = math.min(config.RetryDelay * (2 ^ (attempt - 1)), config.MaxRetryDelay)
			task.wait(delayTime + math.random() * 0.2)
		end
	end

	return false, lastError
end

local function retryMemory(config: any, callback: () -> any): (boolean, any)
	local lastError: any = nil

	for attempt = 1, config.MemoryLockRetryAttempts do
		local ok, result = pcall(callback)

		if ok then
			return true, result
		end

		lastError = result

		if attempt < config.MemoryLockRetryAttempts then
			task.wait(math.min(0.25 * (2 ^ (attempt - 1)), 2) + math.random() * 0.1)
		end
	end

	return false, lastError
end

local function resolveUserId(subject: UserSubject): (number, Player?)
	if typeof(subject) == "Instance" and subject:IsA("Player") then
		local player = subject :: Player
		return player.UserId, player
	end

	assert(type(subject) == "number" and subject > 0 and subject == math.floor(subject), "Expected a Player or positive integer UserId")
	return subject, Players:GetPlayerByUserId(subject)
end

local function applyMigrations(data: DataTable, savedVersion: number, config: any): (DataTable, number, boolean)
	if savedVersion > config.DataVersion then
		if config.RejectFutureDataVersion then
			error("Stored DataVersion " .. tostring(savedVersion) .. " is newer than current DataVersion " .. tostring(config.DataVersion), 2)
		end

		return data, savedVersion, false
	end

	local currentData = data
	local currentVersion = savedVersion
	local changed = false

	while currentVersion < config.DataVersion do
		local targetVersion = currentVersion + 1
		local migration = config.Migrations and config.Migrations[targetVersion]

		if migration ~= nil then
			local replacement = migration(currentData, currentVersion, targetVersion)

			if replacement ~= nil then
				assert(type(replacement) == "table", "Migration must return a table or nil")
				currentData = replacement
			end
		end

		currentVersion = targetVersion
		changed = true
	end

	return currentData, currentVersion, changed
end

function Profile._deactivate(self: ProfileObject, reason: string?): ()
	if not self._active then
		return
	end

	self._active = false
	self._saving = false
	self._releasing = false
	self.Store._profiles[self.UserId] = nil

	self.Released:Fire(reason or "Released")
	self.Store.ProfileReleased:Fire(self, reason or "Released")
end

function Profile._markChanged(self: ProfileObject): ()
	self._dirty = true
	self._revision += 1
end

function Profile._waitForSave(self: ProfileObject): boolean
	while self._saving do
		if not self._active then
			return false
		end

		task.wait()
	end

	return self._active
end

function Profile._snapshotForSave(self: ProfileObject): (DataTable, CompressionPacket, number)
	validateData(self.Data, self.Store.Config)

	local template = getTemplateForVersion(self.Store.Config, self.Version)

	if template == nil then
		error("No template exists for current profile DataVersion " .. tostring(self.Version), 2)
	end

	validateTemplateShape(self.Data, template, "Data")

	local snapshot = deepCopy(self.Data)
	local packet = encodePlayerData(snapshot, self.Version, self.Store.Config)

	return snapshot, packet, self._revision
end

function Profile.IsActive(self: ProfileObject): boolean
	return self._active
end

function Profile.IsDirty(self: ProfileObject): boolean
	return self._dirty
end

function Profile.Get(self: ProfileObject, key: any): any
	return self.Data[key]
end

function Profile.GetDataCopy(self: ProfileObject): DataTable
	return deepCopy(self.Data)
end

function Profile.GetDataTemplate(self: ProfileObject): DataTemplate
	return {
		Version = self.Version,
		Data = deepCopy(self.Data),
	}
end

function Profile.GetBuffer(self: ProfileObject): buffer
	return cloneBuffer(encodePlayerData(self.Data, self.Version, self.Store.Config).Data)
end

Profile.ToBuffer = Profile.GetBuffer

function Profile.GetStorageInfo(self: ProfileObject): StorageInfo
	local savedBytes = 0
	local savingsPercent = 0

	if self._lastRawBufferBytes ~= nil and self._lastBufferBytes ~= nil then
		savedBytes = math.max(0, self._lastRawBufferBytes - self._lastBufferBytes)

		if self._lastRawBufferBytes > 0 then
			savingsPercent = savedBytes / self._lastRawBufferBytes * 100
		end
	end

	return {
		Version = self.Version,
		PlayerKey = self.Key,
		PlayerKeyBytes = #self.Key,
		StoredBytes = self._lastBufferBytes,
		RawBytes = self._lastRawBufferBytes,
		SavedBytes = savedBytes,
		SavingsPercent = savingsPercent,
		Codec = self._lastCodec,
		UsefulBits = self._lastUsefulBits,
		PhysicalBits = self._lastPhysicalBits,
		PaddingBits = self._lastPaddingBits,
		Dirty = self._dirty,
		Revision = self._revision,
		LastSavedRevision = self._lastSavedRevision,
		LastSaveClock = self._lastSave,
	}
end

function Profile.MarkDirty(self: ProfileObject): ()
	assert(self._active, "Cannot modify an inactive profile")
	self:_markChanged()
end

function Profile.Set(self: ProfileObject, key: any, value: any): any
	assert(self._active, "Cannot modify an inactive profile")

	if self.Store.Config.Template[key] == nil then
		error("Data." .. tostring(key) .. " is not declared in DataTemplate.Data", 2)
	end

	local oldValue = self.Data[key]
	self.Data[key] = value

	local ok, validationError = pcall(function(): ()
		validateData(self.Data, self.Store.Config)
		validateTemplateShape(self.Data, self.Store.Config.Template, "Data")
	end)

	if not ok then
		self.Data[key] = oldValue
		error(validationError, 2)
	end

	self:_markChanged()
	self.Changed:Fire(key, value, oldValue)

	return value
end

function Profile.Update(self: ProfileObject, key: any, callback: (any) -> any): any
	assert(self._active, "Cannot modify an inactive profile")
	assert(type(callback) == "function", "Profile:Update expects a function")

	if self.Store.Config.Template[key] == nil then
		error("Data." .. tostring(key) .. " is not declared in DataTemplate.Data", 2)
	end

	local backup = deepCopy(self.Data)
	local oldValue = self.Data[key]
	local okCallback, newValue = pcall(callback, oldValue)

	if not okCallback then
		error(newValue, 2)
	end

	self.Data[key] = newValue

	local ok, validationError = pcall(function(): ()
		validateData(self.Data, self.Store.Config)
		validateTemplateShape(self.Data, self.Store.Config.Template, "Data")
	end)

	if not ok then
		self.Data = backup
		error(validationError, 2)
	end

	self:_markChanged()
	self.Changed:Fire(key, newValue, oldValue)

	return newValue
end

function Profile.Increment(self: ProfileObject, key: any, amount: number?): number
	local delta = amount or 1

	assert(isFiniteNumber(delta), "Profile:Increment amount must be a finite number")

	return self:Update(key, function(value: any): number
		local current = value or 0

		assert(isFiniteNumber(current), "Profile:Increment target must be a finite number")

		return current + delta
	end)
end

function Profile.Overwrite(self: ProfileObject, data: DataTable): DataTable
	assert(self._active, "Cannot modify an inactive profile")
	assert(type(data) == "table", "Profile:Overwrite expects a table")

	validateData(data, self.Store.Config)
	validateTemplateShape(data, self.Store.Config.Template, "Data")

	local oldData = self.Data
	self.Data = deepCopy(data)
	self:_markChanged()
	self.Changed:Fire(nil, self.Data, oldData)

	return self.Data
end

function Profile.Reconcile(self: ProfileObject): DataTable
	assert(self._active, "Cannot reconcile an inactive profile")

	local before = deepCopy(self.Data)
	local _, changed = reconcile(self.Data, self.Store.Config.Template)

	if changed then
		validateData(self.Data, self.Store.Config)
		validateTemplateShape(self.Data, self.Store.Config.Template, "Data")
		self:_markChanged()
		self.Changed:Fire(nil, self.Data, before)
	end

	return self.Data
end

function Profile.Mutate(self: ProfileObject, callback: Mutator): DataTable
	assert(self._active, "Cannot mutate an inactive profile")
	assert(type(callback) == "function", "Profile:Mutate expects a function")

	local backup = deepCopy(self.Data)
	local ok, replacement = pcall(callback, self.Data)

	if not ok then
		self.Data = backup
		error(replacement, 2)
	end

	if replacement ~= nil then
		assert(type(replacement) == "table", "Profile:Mutate callback must return a table or nil")
		self.Data = replacement
	end

	local valid, validationError = pcall(function(): ()
		validateData(self.Data, self.Store.Config)
		validateTemplateShape(self.Data, self.Store.Config.Template, "Data")
	end)

	if not valid then
		self.Data = backup
		error(validationError, 2)
	end

	self:_markChanged()
	self.Changed:Fire(nil, self.Data, backup)

	return self.Data
end

function DataStore._key(self: StoreObject, userId: number): string
	if self.Config.CompactPlayerKeys then
		return self.Config.KeyPrefix .. encodeBase62UInt(userId)
	end

	return self.Config.KeyPrefix .. tostring(userId)
end

function DataStore._lockKey(self: StoreObject, userId: number): string
	return "u" .. encodeBase62UInt(userId)
end

function DataStore._makeLockValue(self: StoreObject, sessionId: string, released: boolean): (buffer, number, string)
	return encodeSession({
		Id = sessionId,
		Released = released,
	}, self.Config)
end

function DataStore._acquireSessionLock(self: StoreObject, userId: number, sessionId: string, mode: LockMode): (boolean, any?, number?, string?)
	if not self.Config.SessionLocking then
		return true
	end

	local key = self:_lockKey(userId)
	local claimed = false
	local observed: any = nil
	local storedBytes: number? = nil
	local codec: string? = nil

	local ok, result = retryMemory(self.Config, function(): any
		return self._lockMap:UpdateAsync(key, function(current: any): any
			local currentSession = decodeSession(current, self.Config)
			observed = currentSession

			local available = current == nil
				or (currentSession ~= nil and currentSession.Released)
				or (currentSession ~= nil and sessionIdsEqual(currentSession.Id, sessionId))

			if available or mode == "Steal" then
				claimed = true

				local packed: buffer
				packed, storedBytes, codec = self:_makeLockValue(sessionId, false)

				return packed
			end

			claimed = false
			return nil
		end, self.Config.SessionLockTimeout)
	end)

	if not ok then
		return false, result
	end

	local resultSession = decodeSession(result, self.Config)

	if claimed and resultSession ~= nil and sessionIdsEqual(resultSession.Id, sessionId) then
		return true, nil, storedBytes, codec
	end

	return false, observed or result
end

function DataStore._refreshSessionLock(self: StoreObject, profile: ProfileObject): (boolean, any?)
	if not self.Config.SessionLocking then
		return true
	end

	local key = self:_lockKey(profile.UserId)
	local refreshed = false
	local storedBytes: number? = nil
	local codec: string? = nil

	local ok, result = retryMemory(self.Config, function(): any
		return self._lockMap:UpdateAsync(key, function(current: any): any
			local currentSession = decodeSession(current, self.Config)

			if currentSession ~= nil and sessionIdsEqual(currentSession.Id, profile.SessionId) then
				refreshed = true

				local packed: buffer
				packed, storedBytes, codec = self:_makeLockValue(profile.SessionId, false)

				return packed
			end

			refreshed = false
			return nil
		end, self.Config.SessionLockTimeout)
	end)

	if not ok then
		return false, result
	end

	local resultSession = decodeSession(result, self.Config)

	if refreshed and resultSession ~= nil and sessionIdsEqual(resultSession.Id, profile.SessionId) then
		profile._lastSessionBytes = storedBytes
		profile._lastSessionCodec = codec
		self._stats.SessionRefreshes += 1

		return true
	end

	return false, "SessionLost"
end

function DataStore._releaseSessionLock(self: StoreObject, profile: ProfileObject | {UserId: number, SessionId: string}): (boolean, any?)
	if not self.Config.SessionLocking then
		return true
	end

	local key = self:_lockKey(profile.UserId)
	local released = false

	local ok, result = retryMemory(self.Config, function(): any
		return self._lockMap:UpdateAsync(key, function(current: any): any
			local currentSession = decodeSession(current, self.Config)

			if currentSession ~= nil and sessionIdsEqual(currentSession.Id, profile.SessionId) then
				released = true
				local packed = self:_makeLockValue(profile.SessionId, true)
				return packed
			end

			released = false
			return nil
		end, 1)
	end)

	if not ok then
		return false, result
	end

	return released or result == nil
end

function Profile.SaveAsync(self: ProfileObject): (boolean, any?)
	if not self._active then
		return false, "ProfileInactive"
	end

	if not self:_waitForSave() then
		return false, "ProfileInactive"
	end

	self._saving = true

	local lockOk, lockError = self.Store:_refreshSessionLock(self)

	if not lockOk then
		self._saving = false
		self.Store._stats.SessionLosses += 1
		self:_deactivate("SessionLost")
		self.Store.Issue:Fire("SessionLost", self, lockError)

		return false, "SessionLost"
	end

	local okSnapshot, snapshotOrError, packet, revision = pcall(function(): (DataTable, CompressionPacket, number)
		return self:_snapshotForSave()
	end)

	if not okSnapshot then
		self._saving = false
		return false, snapshotOrError
	end

	local storedBytes = buffer.len(packet.Data)
	local rawBytes = packet.RawBytes or storedBytes

	local ok, result = retryDataStore(self.Store.Config, Enum.DataStoreRequestType.SetIncrementAsync, function(): any
		return self.Store._store:SetAsync(self.Key, packet.Data)
	end)

	if not ok then
		self._saving = false
		self.Store._stats.SaveFailures += 1
		self.Store.Issue:Fire("SaveFailed", self, result)
		debugWarn(self.Store.Config, "Save failed for", self.Key, result)

		return false, result
	end

	self._lastSave = os.clock()
	self._lastBufferBytes = storedBytes
	self._lastRawBufferBytes = rawBytes
	self._lastCodec = packet.Codec or "IndexedSchema"
	self._lastUsefulBits = packet.UsefulBits or packet.Bits
	self._lastPhysicalBits = storedBytes * 8
	self._lastPaddingBits = packet.PaddingBits
	self._lastSavedRevision = revision

	if self._revision == revision then
		self._dirty = false
	end

	self.Store._stats.Saves += 1
	self.Store._stats.BytesWritten += storedBytes

	self._saving = false
	self.Saved:Fire(self:GetStorageInfo())

	return true
end

function Profile.ReleaseAsync(self: ProfileObject, reason: string?): (boolean, any?)
	if not self._active then
		return true
	end

	if self._releasing then
		while self._releasing and self._active do
			task.wait()
		end

		return not self._active
	end

	self._releasing = true

	if not self:_waitForSave() then
		self._releasing = false
		return true
	end

	if self.Store.Config.SaveOnRelease and self._dirty then
		local saved, saveError = self:SaveAsync()

		if not saved then
			self._releasing = false
			return false, saveError
		end
	end

	local releasedLock, releaseError = self.Store:_releaseSessionLock(self)

	if not releasedLock then
		self.Store.Issue:Fire("SessionReleaseFailed", self, releaseError)
		debugWarn(self.Store.Config, "Session lock release failed for", self.Key, releaseError)
	end

	self._releasing = false
	self:_deactivate(reason or "Released")

	return true
end

function DataStore.new(config: DataStoreConfig): StoreObject
	assert(RunService:IsServer(), "DataStore can only be used from the server")
	assert(type(config) == "table", "DataStore.new expects a config table")

	local merged = mergeConfig(config)

	validateConfig(merged)
	getCompression()
	prepareLayouts(merged)

	local currentLayout = getLayout(merged, merged.DataVersion)

	assert(currentLayout ~= nil, "Unable to compile current Compression IndexedLayout")

	local startupPacket = encodePlayerData(merged.Template, merged.DataVersion, merged)
	local startupDecoded = decodePlayerData(startupPacket.Data, merged)

	assert(startupDecoded.Version == merged.DataVersion, "DataStore startup DataVersion round trip failed")
	assert(deepEqual(startupDecoded.Data, merged.Template), "DataStore startup data round trip failed")

	if merged.SessionLocking then
		local sessionId = HttpService:GenerateGUID(false)
		local packed = encodeSession({Id = sessionId, Released = false}, merged)
		local decoded = decodeSession(packed, merged)

		assert(decoded ~= nil and sessionIdsEqual(decoded.Id, sessionId), "DataStore session round trip failed")
	end

	local robloxStore: any

	if merged.Scope ~= nil then
		robloxStore = DataStoreService:GetDataStore(merged.Name, merged.Scope)
	else
		robloxStore = DataStoreService:GetDataStore(merged.Name)
	end

	local lockName = "DS31:" .. merged.Name

	if merged.Scope ~= nil then
		lockName ..= ":" .. tostring(merged.Scope)
	end

	if #lockName > 120 then
		lockName = string.sub(lockName, 1, 120)
	end

	local stats: RuntimeStats = {
		Loads = 0,
		LoadFailures = 0,
		Saves = 0,
		SaveFailures = 0,
		Autosaves = 0,
		SessionRefreshes = 0,
		SessionRefreshFailures = 0,
		SessionLosses = 0,
		BytesWritten = 0,
	}

	local self: StoreObject = setmetatable({
		Name = merged.Name,
		Config = merged,
		_store = robloxStore,
		_lockMap = MemoryStoreService:GetHashMap(lockName),
		_profiles = {},
		_opening = {},
		_closed = false,
		_autosaveCursor = 1,
		_heartbeatCursor = 1,
		_playerRemovingConnection = nil,
		_stats = stats,
		ProfileLoaded = Signal.new(),
		ProfileReleased = Signal.new(),
		Issue = Signal.new(),
	}, DataStore) :: any

	self._playerRemovingConnection = Players.PlayerRemoving:Connect(function(player: Player): ()
		local profile = self._profiles[player.UserId]

		if profile ~= nil then
			profile._releaseRequested = "PlayerRemoving"

			task.spawn(function(): ()
				local ok, err = profile:ReleaseAsync("PlayerRemoving")

				if not ok and profile:IsActive() then
					debugWarn(merged, "PlayerRemoving release failed for", profile.Key, err)
				end
			end)
		end
	end)

	if merged.AutoSave then
		task.spawn(function(): ()
			self:_autoSaveLoop()
		end)
	end

	if merged.SessionLocking then
		task.spawn(function(): ()
			self:_sessionHeartbeatLoop()
		end)
	end

	game:BindToClose(function(): ()
		self:CloseAsync()
	end)

	return self
end

function DataStore.GetKeyInfo(self: StoreObject, subject: UserSubject): KeyInfo
	local userId = resolveUserId(subject)
	local key = self:_key(userId)

	return {
		UserId = userId,
		Key = key,
		KeyBytes = #key,
		Compact = self.Config.CompactPlayerKeys,
	}
end

function DataStore.GetCompressionLayoutInfo(self: StoreObject): {[string]: any}
	local layout = getLayout(self.Config, self.Config.DataVersion)
	local reason = self.Config._LayoutErrors[self.Config.DataVersion]

	if layout == nil then
		return {
			Available = false,
			Reason = reason or "No layout compiled",
			DataVersion = self.Config.DataVersion,
		}
	end

	return {
		Available = true,
		DataVersion = self.Config.DataVersion,
		LayoutVersion = layout.Version,
		Mode = layout.Mode,
		FieldCount = #layout.Keys,
		Keys = table.clone(layout.Keys),
	}
end

function DataStore._readStoredValue(self: StoreObject, userId: number): (boolean, any, string)
	local key = self:_key(userId)

	local ok, result = retryDataStore(self.Config, Enum.DataStoreRequestType.GetAsync, function(): any
		return self._store:GetAsync(key)
	end)

	if not ok then
		return false, result, key
	end

	return true, result, key
end

function DataStore._autoSaveLoop(self: StoreObject): ()
	while not self._closed do
		local profiles = self:GetLoadedProfiles()
		local count = #profiles

		if count == 0 then
			task.wait(1)
			continue
		end

		if self._autosaveCursor > count then
			self._autosaveCursor = 1
		end

		local profile = profiles[self._autosaveCursor]
		self._autosaveCursor += 1

		task.wait(math.max(0.5, self.Config.AutoSaveInterval / count))

		if self._closed or not profile:IsActive() then
			continue
		end

		if profile._releaseRequested ~= nil then
			task.spawn(function(): ()
				profile:ReleaseAsync(profile._releaseRequested)
			end)

			continue
		end

		if self.Config.SaveOnlyDirty and not profile:IsDirty() then
			continue
		end

		task.spawn(function(): ()
			self._stats.Autosaves += 1

			local ok, err = profile:SaveAsync()

			if not ok and err ~= "ProfileInactive" and err ~= "SessionLost" then
				self.Issue:Fire("AutoSaveFailed", profile, err)
			end
		end)
	end
end

function DataStore._sessionHeartbeatLoop(self: StoreObject): ()
	while not self._closed do
		local profiles = self:GetLoadedProfiles()
		local count = #profiles

		if count == 0 then
			task.wait(1)
			continue
		end

		if self._heartbeatCursor > count then
			self._heartbeatCursor = 1
		end

		local profile = profiles[self._heartbeatCursor]
		self._heartbeatCursor += 1

		task.wait(math.max(0.25, self.Config.SessionRefreshInterval / count))

		if self._closed or not profile:IsActive() or profile._saving or profile._releasing then
			continue
		end

		task.spawn(function(): ()
			local ok, err = self:_refreshSessionLock(profile)

			if not ok and profile:IsActive() then
				self._stats.SessionRefreshFailures += 1

				if err == "SessionLost" then
					self._stats.SessionLosses += 1
					profile:_deactivate("SessionLost")
					self.Issue:Fire("SessionLost", profile, err)
				else
					self.Issue:Fire("SessionRefreshFailed", profile, err)
				end
			end
		end)
	end
end

function DataStore.GetProfile(self: StoreObject, subject: UserSubject): ProfileObject?
	local userId = resolveUserId(subject)
	return self._profiles[userId]
end

function DataStore._openPlayerCore(self: StoreObject, subject: UserSubject, options: OpenOptions?): (ProfileObject?, any?, any?)
	local userId, player = resolveUserId(subject)
	local existing = self._profiles[userId]

	if existing ~= nil and existing:IsActive() then
		return existing
	end

	local resolvedOptions = options or {}
	local lockMode = resolvedOptions.Locked or "Wait"

	assert(lockMode == "Wait" or lockMode == "Cancel" or lockMode == "Steal", "options.Locked must be Wait, Cancel, or Steal")

	local sessionId = HttpService:GenerateGUID(false)
	local deadline = os.clock() + self.Config.LoadTimeout

	while not self._closed do
		local lockOk, lockInfo, sessionBytes, sessionCodec = self:_acquireSessionLock(userId, sessionId, lockMode)

		if lockOk then
			local okRead, stored, key = self:_readStoredValue(userId)

			if not okRead then
				self:_releaseSessionLock({UserId = userId, SessionId = sessionId})
				self._stats.LoadFailures += 1
				self.Issue:Fire("LoadFailed", userId, stored)

				return nil, stored
			end

			local data: DataTable
			local version: number
			local isNew = stored == nil

			if isNew then
				data = deepCopy(self.Config.Template)
				version = self.Config.DataVersion
			else
				if typeof(stored) ~= "buffer" then
					self:_releaseSessionLock({UserId = userId, SessionId = sessionId})
					self._stats.LoadFailures += 1

					return nil, "StoredValueIsNotBuffer"
				end

				local okDecode, decodedOrError = pcall(decodePlayerData, stored, self.Config)

				if not okDecode then
					self:_releaseSessionLock({UserId = userId, SessionId = sessionId})
					self._stats.LoadFailures += 1
					self.Issue:Fire("DecodeFailed", userId, decodedOrError)

					return nil, decodedOrError
				end

				local decoded = decodedOrError :: DataTemplate

				data = deepCopy(decoded.Data)
				version = decoded.Version
			end

			local okMigrate, migratedData, migratedVersion, migrated = pcall(applyMigrations, data, version, self.Config)

			if not okMigrate then
				self:_releaseSessionLock({UserId = userId, SessionId = sessionId})
				self._stats.LoadFailures += 1
				self.Issue:Fire("MigrationFailed", userId, migratedData)

				return nil, migratedData
			end

			data = migratedData
			version = migratedVersion

			local reconciled = false

			if self.Config.Reconcile then
				local _, changed = reconcile(data, self.Config.Template)
				reconciled = changed
			end

			local valid, validationError = pcall(function(): ()
				validateData(data, self.Config)
				validateTemplateShape(data, self.Config.Template, "Data")
			end)

			if not valid then
				self:_releaseSessionLock({UserId = userId, SessionId = sessionId})
				self._stats.LoadFailures += 1
				self.Issue:Fire("InvalidLoadedData", userId, validationError)

				return nil, validationError
			end

			if player ~= nil and player.Parent ~= Players then
				self:_releaseSessionLock({UserId = userId, SessionId = sessionId})
				return nil, "PlayerLeftDuringLoad"
			end

			local profile: ProfileObject = setmetatable({
				Store = self,
				UserId = userId,
				Player = player,
				Key = key,
				SessionId = sessionId,
				Version = version,
				Data = data,
				Changed = Signal.new(),
				Saved = Signal.new(),
				Released = Signal.new(),
				_active = true,
				_saving = false,
				_releasing = false,
				_dirty = isNew or migrated or reconciled,
				_revision = 0,
				_lastSavedRevision = 0,
				_lastSave = os.clock(),
				_lastBufferBytes = nil,
				_lastRawBufferBytes = nil,
				_lastCodec = nil,
				_lastUsefulBits = nil,
				_lastPhysicalBits = nil,
				_lastPaddingBits = nil,
				_lastSessionBytes = sessionBytes,
				_lastSessionCodec = sessionCodec,
				_releaseRequested = nil,
			}, Profile) :: any

			self._profiles[userId] = profile
			self._stats.Loads += 1
			self.ProfileLoaded:Fire(profile)

			return profile
		end

		if lockMode == "Cancel" then
			return nil, "SessionLocked", lockInfo
		end

		if lockMode == "Steal" then
			return nil, "UnableToStealSession", lockInfo
		end

		if os.clock() >= deadline then
			return nil, "SessionLocked", lockInfo
		end

		task.wait(self.Config.LockRetryInterval)
	end

	return nil, "StoreClosed"
end

function DataStore.OpenPlayerAsync(self: StoreObject, subject: UserSubject, options: OpenOptions?): (ProfileObject?, any?, any?)
	assert(not self._closed, "DataStore is closed")

	local userId = resolveUserId(subject)
	local existing = self._profiles[userId]

	if existing ~= nil and existing:IsActive() then
		return existing
	end

	local deadline = os.clock() + self.Config.LoadTimeout

	while self._opening[userId] do
		if self._closed then
			return nil, "StoreClosed"
		end

		local opened = self._profiles[userId]

		if opened ~= nil and opened:IsActive() then
			return opened
		end

		if os.clock() >= deadline then
			return nil, "OpenAlreadyInProgress"
		end

		task.wait(0.05)
	end

	self._opening[userId] = true

	local ok, profile, err, detail = pcall(self._openPlayerCore, self, subject, options)

	self._opening[userId] = nil

	if not ok then
		self._stats.LoadFailures += 1
		self.Issue:Fire("OpenFailed", userId, profile)

		return nil, profile
	end

	return profile, err, detail
end

DataStore.LoadPlayerAsync = DataStore.OpenPlayerAsync

function DataStore.ViewTemplateAsync(self: StoreObject, subject: UserSubject): (DataTemplate?, any?)
	local userId = resolveUserId(subject)
	local ok, result = self:_readStoredValue(userId)

	if not ok then
		return nil, result
	end

	if result == nil then
		return nil
	end

	if typeof(result) ~= "buffer" then
		return nil, "StoredValueIsNotBuffer"
	end

	local okDecode, decodedOrError = pcall(decodePlayerData, result, self.Config)

	if not okDecode then
		return nil, decodedOrError
	end

	return decodedOrError
end

function DataStore.ViewAsync(self: StoreObject, subject: UserSubject): (DataTable?, any?, any?)
	local dataTemplate, errorMessage = self:ViewTemplateAsync(subject)

	if dataTemplate == nil then
		return nil, errorMessage
	end

	return deepCopy(dataTemplate.Data), dataTemplate.Version
end

function DataStore.GetStoredBufferAsync(self: StoreObject, subject: UserSubject): (buffer?, any?)
	local userId = resolveUserId(subject)
	local ok, result = self:_readStoredValue(userId)

	if not ok then
		return nil, result
	end

	if result == nil then
		return nil
	end

	if typeof(result) ~= "buffer" then
		return nil, "StoredValueIsNotBuffer"
	end

	return cloneBuffer(result)
end

function DataStore.GetStoredPayloadAsync(self: StoreObject, subject: UserSubject): (any, string?)
	local value, err = self:GetStoredBufferAsync(subject)

	if value == nil then
		return nil, err
	end

	return value, "buffer"
end

function DataStore.GetSessionLockInfoAsync(self: StoreObject, subject: UserSubject): (SessionInfo?, any?)
	if not self.Config.SessionLocking then
		return nil, "SessionLockingDisabled"
	end

	local userId = resolveUserId(subject)
	local key = self:_lockKey(userId)

	local ok, result = retryMemory(self.Config, function(): any
		return self._lockMap:GetAsync(key)
	end)

	if not ok then
		return nil, result
	end

	if result == nil then
		return {
			Id = nil,
			Released = nil,
			Bytes = nil,
			Codec = nil,
		}
	end

	local session = decodeSession(result, self.Config)

	if session == nil then
		return nil, "SessionDecodeFailed"
	end

	return {
		Id = session.Id,
		Released = session.Released,
		Bytes = typeof(result) == "buffer" and buffer.len(result) or nil,
		Codec = "IndexedSchema",
	}
end

function DataStore.SavePlayerAsync(self: StoreObject, subject: UserSubject): (boolean, any?)
	local profile = self:GetProfile(subject)

	if profile == nil then
		return false, "ProfileNotLoaded"
	end

	return profile:SaveAsync()
end

function DataStore.ReleasePlayerAsync(self: StoreObject, subject: UserSubject, reason: string?): (boolean, any?)
	local profile = self:GetProfile(subject)

	if profile == nil then
		return true
	end

	return profile:ReleaseAsync(reason)
end

function DataStore.FlushAsync(self: StoreObject): (boolean, number)
	local profiles = self:GetLoadedProfiles()
	local remaining = 0
	local failures = 0
	local deadline = os.clock() + self.Config.ShutdownTimeout

	for _, profile in ipairs(profiles) do
		if profile:IsActive() and profile:IsDirty() then
			remaining += 1

			task.spawn(function(): ()
				local ok = profile:SaveAsync()

				if not ok then
					failures += 1
				end

				remaining -= 1
			end)
		end
	end

	while remaining > 0 and os.clock() < deadline do
		task.wait(0.05)
	end

	return remaining == 0 and failures == 0, failures + remaining
end

function DataStore.CloseAsync(self: StoreObject): boolean
	if self._closed then
		return true
	end

	self._closed = true

	if self._playerRemovingConnection ~= nil then
		self._playerRemovingConnection:Disconnect()
		self._playerRemovingConnection = nil
	end

	local profiles = self:GetLoadedProfiles()
	local remaining = 0
	local failures = 0
	local deadline = os.clock() + self.Config.ShutdownTimeout

	for _, profile in ipairs(profiles) do
		if profile:IsActive() then
			remaining += 1
			profile._releaseRequested = "ServerClosing"

			task.spawn(function(): ()
				local ok = profile:ReleaseAsync("ServerClosing")

				if not ok and profile:IsActive() then
					failures += 1
				end

				remaining -= 1
			end)
		end
	end

	while remaining > 0 and os.clock() < deadline do
		task.wait(0.05)
	end

	if remaining > 0 then
		warn(string.format("[DataStore v%s] shutdown timed out with %d profile(s) pending", VERSION, remaining))
	end

	if failures > 0 then
		warn(string.format("[DataStore v%s] shutdown finished with %d release failure(s)", VERSION, failures))
	end

	return remaining == 0 and failures == 0
end

function DataStore.IsClosed(self: StoreObject): boolean
	return self._closed
end

function DataStore.GetLoadedProfiles(self: StoreObject): {ProfileObject}
	local profiles = {}

	for _, profile in pairs(self._profiles) do
		if profile:IsActive() then
			profiles[#profiles + 1] = profile
		end
	end

	return profiles
end

function DataStore.GetRuntimeStats(self: StoreObject): RuntimeStats
	return table.clone(self._stats)
end

function DataStore.CompressDataTemplate(dataTemplate: DataTemplate, options: {[string]: any}?): CompressionPacket
	assert(type(dataTemplate) == "table" and type(dataTemplate.Data) == "table", "CompressDataTemplate expects {Version, Data}")

	local config = table.clone(DEFAULTS)

	if type(options) == "table" then
		for key, value in pairs(options) do
			config[key] = value
		end
	end

	config.Name = "Static"
	config.DataVersion = dataTemplate.Version

	if type(options) == "table" and type(options.DataTemplate) == "table" and type(options.DataTemplate.Data) == "table" then
		config.Template = deepCopy(options.DataTemplate.Data)
		config.DataTemplate = deepCopy(options.DataTemplate)
	else
		config.Template = deepCopy(dataTemplate.Data)
		config.DataTemplate = deepCopy(dataTemplate)
	end

	config._LayoutsPrepared = false
	config._LayoutsByVersion = {}
	config._LayoutErrors = {}

	return encodePlayerData(dataTemplate.Data, dataTemplate.Version, config)
end

function DataStore.DecompressDataTemplate(dataBuffer: buffer, options: {[string]: any}?): DataTemplate
	assert(typeof(dataBuffer) == "buffer", "DecompressDataTemplate expects a buffer")
	assert(type(options) == "table" and type(options.DataTemplate) == "table" and type(options.DataTemplate.Data) == "table", "DecompressDataTemplate requires options.DataTemplate")

	local config = table.clone(DEFAULTS)

	for key, value in pairs(options) do
		config[key] = value
	end

	config.Name = "Static"
	config.DataVersion = options.DataTemplate.Version
	config.Template = deepCopy(options.DataTemplate.Data)
	config.DataTemplate = deepCopy(options.DataTemplate)
	config._LayoutsPrepared = false
	config._LayoutsByVersion = {}
	config._LayoutErrors = {}

	return decodePlayerData(dataBuffer, config)
end

function DataStore.Encode(data: any, options: CompressionOptions?): buffer
	return getCompression().Pack(data, options).Data
end

function DataStore.Decode(dataBuffer: buffer, options: CompressionOptions?): any
	assert(typeof(dataBuffer) == "buffer", "Decode expects a buffer")
	return getCompression().Unpack(dataBuffer, options)
end

function DataStore.EncodeUserIdKey(userId: number): string
	assert(userId > 0 and userId <= MAX_SAFE_INTEGER and userId == math.floor(userId), "EncodeUserIdKey expects a positive safe integer")
	return encodeBase62UInt(userId)
end

function DataStore.DecodeUserIdKey(encoded: string): number
	return decodeBase62UInt(encoded)
end

function DataStore.Version(): string
	return VERSION
end

function DataStore.FormatVersion(): number
	return STORAGE_FORMAT_VERSION
end

function DataStore.CompressionVersion(): string
	return getCompression().Version()
end

DataStore.Profile = Profile
DataStore.Signal = Signal
DataStore.SessionFormatVersion = SESSION_FORMAT_VERSION

return DataStore
