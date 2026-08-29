--!native
--!optimize 2

local DataStoreService = game:GetService("DataStoreService")
local MemoryStoreService = game:GetService("MemoryStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Compression = nil
local BufferUtil = nil

local function getCompression()
	if Compression ~= nil then
		return Compression
	end

	local moduleScript = assert(
		script:WaitForChild("Compression", 10),
		"DataStore v1.8.4 requires a child ModuleScript named Compression v2.6.7"
	)

	local codec = require(moduleScript)
	assert(
		type(codec) == "table"
			and type(codec.Version) == "function"
			and codec.Version() == "2.6.7"
			and type(codec.CompressTablePacket) == "function"
			and type(codec.DecompressTable) == "function"
			and type(codec.CompressBuffer) == "function"
			and type(codec.CompressBufferSmart) == "function"
			and type(codec.DecompressBuffer) == "function",
		"DataStore v1.8.4 requires Compression v2.6.7 with table + smart buffer codecs"
	)

	Compression = codec
	return codec
end

local function getBufferUtil()
	if BufferUtil ~= nil then
		return BufferUtil
	end

	local moduleScript = assert(
		script:WaitForChild("BufferUtil", 10),
		"DataStore v1.8.4 requires a child ModuleScript named BufferUtil v1.1.0"
	)

	local util = require(moduleScript)
	assert(
		type(util) == "table"
			and util.VERSION == "1.1.0"
			and type(util.writer) == "function"
			and type(util.compactBytes) == "function"
			and type(util.varUIntSize) == "function",
		"DataStore v1.8.4 requires BufferUtil v1.1.0 with writer + compact APIs"
	)

	BufferUtil = util
	return util
end

local DataStore = {}
DataStore.__index = DataStore

local Profile = {}
Profile.__index = Profile

local Signal = {}
Signal.__index = Signal

local VERSION = "1.8.4"
local STORAGE_FORMAT_VERSION = 6
local SESSION_FORMAT_VERSION = 1
local SESSION_MAGIC = 0x53
local SESSION_FLAG_RELEASED = 0x01
local SESSION_FLAG_ID_GUID = 0x02
local SESSION_FLAG_JOB_GUID = 0x04
local SESSION_FLAG_DIAGNOSTICS = 0x08
local BUFFER_ENCODING = "BufferV1"
local TABLE_ENCODING = "Table"

local LEGACY_FORMAT_TAG = "__SimpleDataStore"
local LEGACY_FORMAT_V151 = 3
local LEGACY_FORMAT_V150 = 2
local LEGACY_FORMAT_V1 = 1

local CODEC_MAGIC = "SDSB"
local CODEC_VERSION = 1
local MAX_SAFE_INTEGER = 9007199254740991
local MAX_SAFE_SIGNED_VARINT = math.floor(MAX_SAFE_INTEGER / 2)
local ADLER_MOD = 65521

-- v1.8.4 compact player-key codec. Base62 keeps keys printable and reversible
-- while avoiding binary/Base64 expansion. A one-byte prefix namespaces new keys
-- away from legacy decimal/custom-prefix keys during migration.
local KEY_BASE62_ALPHABET = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
local KEY_BASE62_RADIX = #KEY_BASE62_ALPHABET

local function encodeBase62UInt(value)
	assert(type(value) == "number" and value >= 0 and value <= MAX_SAFE_INTEGER and value == math.floor(value), "Base62 expects a non-negative safe integer")
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

local function decodeBase62UInt(value)
	assert(type(value) == "string" and #value > 0, "Base62 expects a non-empty string")
	local result = 0
	for i = 1, #value do
		local byte = string.byte(value, i)
		local digit
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

local TAG_NIL = 0
local TAG_FALSE = 1
local TAG_TRUE = 2
local TAG_UINT = 3
local TAG_SINT = 4
local TAG_F64 = 5
local TAG_STRING = 6
local TAG_ARRAY = 7
local TAG_MAP = 8
local TAG_BUFFER = 9
local TAG_VECTOR2 = 10
local TAG_VECTOR3 = 11
local TAG_COLOR3 = 12
local TAG_CFRAME = 13
local TAG_UDIM = 14
local TAG_UDIM2 = 15

local DEFAULTS = {
	Scope = nil,
	KeyPrefix = "Player_",
	CompactPlayerKeys = true,
	CompactKeyPrefix = "p",
	MigrateLegacyPlayerKeys = true,
	DeleteLegacyPlayerKeys = true,

	DataTemplate = {
		Version = 1,
		Data = {},
	},

	Template = {},
	DataVersion = 1,
	Migrations = nil,
	RejectFutureDataVersion = true,
	Reconcile = true,

	AutoSave = true,
	AutoSaveInterval = 60,

	SessionLocking = true,
	SessionLockTimeout = 180,
	LoadTimeout = 30,
	LockRetryInterval = 1,
	MemoryLockRetryAttempts = 4,
	SessionCompressionEnabled = true,
	SessionStoreDiagnostics = false,

	RetryAttempts = 5,
	RetryDelay = 0.75,
	MaxRetryDelay = 8,

	ShutdownTimeout = 25,

	BudgetAware = true,
	BudgetWaitTimeout = 10,

	StorageMode = "Buffer",

	CompressionEnabled = true,

	-- v1.8.4 exact-buffer pipeline. BufferUtil owns working-buffer growth and
	-- compactBytes trims every DataStore-owned writer to its exact written length
	-- before the value is handed to Compression or Roblox persistence.
	BufferUtilEnabled = true,
	BufferWriterInitialCapacity = 32,

	-- v1.8.4 SchemaBuffer removes DataTemplate field names and per-value type tags
	-- from the persisted payload. The readable runtime table is reconstructed from
	-- the versioned template on load. Unsupported/dynamic templates automatically
	-- fall back to the generic Compression codec.
	SchemaBufferEnabled = true,
	SchemaBufferCompress = true,
	SchemaFallbackToGeneric = true,
	SchemaHistory = nil,

	-- v1.8 primary storage codec: Compression v2.6.7 adaptive table compression.
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
	CompressionCompareLegacyBuffer = true,

	-- Legacy BufferV1 compression settings retained for old-save decoding and
	-- the public CompressStorageBuffer helper.
	CompressionMinBufferBytes = 16,
	CompressionMinSavingsBytes = 1,
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

local function debugWarn(config, ...)
	if config.Debug then
		warn("[DataStore v" .. VERSION .. "]", ...)
	end
end

function Signal.new()
	return setmetatable({
		_listeners = {},
		_destroyed = false,
	}, Signal)
end

function Signal:Connect(callback)
	assert(type(callback) == "function", "Signal:Connect expects a function")
	assert(not self._destroyed, "Signal is destroyed")

	local signal = self
	local token = {}
	local connection = { Connected = true }
	signal._listeners[token] = callback

	function connection:Disconnect()
		if not connection.Connected then
			return
		end
		connection.Connected = false
		if not signal._destroyed then
			signal._listeners[token] = nil
		end
	end

	return connection
end

function Signal:Once(callback)
	local connection
	connection = self:Connect(function(...)
		connection:Disconnect()
		callback(...)
	end)
	return connection
end

function Signal:Fire(...)
	if self._destroyed then
		return
	end

	for _, callback in pairs(self._listeners) do
		task.spawn(callback, ...)
	end
end

function Signal:Destroy()
	if self._destroyed then
		return
	end
	self._destroyed = true
	table.clear(self._listeners)
end

local function cloneBuffer(source)
	local length = buffer.len(source)
	local out = buffer.create(length)
	if length > 0 then
		buffer.copy(out, 0, source, 0, length)
	end
	return out
end

local function deepCopy(value, seen)
	local robloxType = typeof(value)
	if robloxType == "buffer" then
		return cloneBuffer(value)
	end

	if type(value) ~= "table" then
		return value
	end

	seen = seen or {}
	if seen[value] then
		error("Circular tables cannot be copied", 3)
	end

	seen[value] = true
	local out = {}
	for key, child in pairs(value) do
		out[deepCopy(key, seen)] = deepCopy(child, seen)
	end
	seen[value] = nil
	return out
end

local function isFiniteNumber(value)
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function isInteger(value)
	return type(value) == "number" and value == math.floor(value)
end

local function isArray(value)
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
		if key > maxIndex then
			maxIndex = key
		end
	end

	return count == maxIndex, maxIndex
end

local function reconcile(target, template)
	if type(target) ~= "table" or type(template) ~= "table" then
		return target
	end

	local templateIsArray = isArray(template)
	if templateIsArray then
		return target
	end

	for key, defaultValue in pairs(template) do
		local current = target[key]
		if current == nil then
			target[key] = deepCopy(defaultValue)
		elseif type(current) == "table" and type(defaultValue) == "table" then
			local defaultIsArray = isArray(defaultValue)
			if not defaultIsArray then
				reconcile(current, defaultValue)
			end
		end
	end

	return target
end

local function validateSavable(value, path, seen, depth, state, config)
	path = path or "Data"
	seen = seen or {}
	depth = depth or 0
	state = state or { Entries = 0 }
	config = config or DEFAULTS

	if depth > config.MaxDepth then
		error(path .. " exceeded MaxDepth", 3)
	end

	local robloxType = typeof(value)
	local valueType = type(value)

	if value == nil or valueType == "boolean" then
		return true
	end

	if valueType == "number" then
		if not isFiniteNumber(value) then
			error(path .. " contains NaN or infinity", 3)
		end
		return true
	end

	if valueType == "string" then
		if config.StorageMode == "Table" and utf8.len(value) == nil then
			error(path .. " contains invalid UTF-8; use Buffer storage for arbitrary byte strings", 3)
		end
		return true
	end

	if robloxType == "buffer" then
		return true
	end

	if robloxType == "Vector2" then
		if config.StorageMode ~= "Buffer" then
			error(path .. " contains Vector2, which requires Buffer storage", 3)
		end
		if not isFiniteNumber(value.X) or not isFiniteNumber(value.Y) then
			error(path .. " contains a non-finite Vector2", 3)
		end
		return true
	elseif robloxType == "Vector3" then
		if config.StorageMode ~= "Buffer" then
			error(path .. " contains Vector3, which requires Buffer storage", 3)
		end
		if not isFiniteNumber(value.X) or not isFiniteNumber(value.Y) or not isFiniteNumber(value.Z) then
			error(path .. " contains a non-finite Vector3", 3)
		end
		return true
	elseif robloxType == "Color3" then
		if config.StorageMode ~= "Buffer" then
			error(path .. " contains Color3, which requires Buffer storage", 3)
		end
		if not isFiniteNumber(value.R) or not isFiniteNumber(value.G) or not isFiniteNumber(value.B) then
			error(path .. " contains a non-finite Color3", 3)
		end
		return true
	elseif robloxType == "CFrame" then
		if config.StorageMode ~= "Buffer" then
			error(path .. " contains CFrame, which requires Buffer storage", 3)
		end
		for _, component in ipairs({ value:GetComponents() }) do
			if not isFiniteNumber(component) then
				error(path .. " contains a non-finite CFrame", 3)
			end
		end
		return true
	elseif robloxType == "UDim" then
		if config.StorageMode ~= "Buffer" then
			error(path .. " contains UDim, which requires Buffer storage", 3)
		end
		if not isFiniteNumber(value.Scale) or not isInteger(value.Offset) or math.abs(value.Offset) > MAX_SAFE_SIGNED_VARINT then
			error(path .. " contains an invalid UDim", 3)
		end
		return true
	elseif robloxType == "UDim2" then
		if config.StorageMode ~= "Buffer" then
			error(path .. " contains UDim2, which requires Buffer storage", 3)
		end
		if not isFiniteNumber(value.X.Scale) or not isFiniteNumber(value.Y.Scale)
			or not isInteger(value.X.Offset) or not isInteger(value.Y.Offset)
			or math.abs(value.X.Offset) > MAX_SAFE_SIGNED_VARINT or math.abs(value.Y.Offset) > MAX_SAFE_SIGNED_VARINT then
			error(path .. " contains an invalid UDim2", 3)
		end
		return true
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

		local keyType = type(key)
		if keyType == "number" then
			if key < 1 or key ~= math.floor(key) then
				error(path .. " contains a non-positive or non-integer numeric key", 3)
			end
			numericKeys += 1
			if key > maxIndex then
				maxIndex = key
			end
		elseif keyType == "string" then
			if config.StorageMode == "Table" and utf8.len(key) == nil then
				error(path .. " contains an invalid UTF-8 table key", 3)
			end
			stringKeys += 1
		else
			error(path .. " contains unsupported table key type " .. keyType, 3)
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
	return true
end

local Writer = {}
Writer.__index = Writer

-- DataStore v1.8.4 delegates temporary byte-buffer growth to BufferUtil.
-- The backing buffer may grow geometrically while encoding, but Finish() always
-- calls BufferUtil.compactBytes with the exact number of bytes written. Therefore
-- unused working capacity never reaches Compression, MemoryStore, or DataStore.
function Writer.new(capacity)
	local util = getBufferUtil()
	local requested = capacity or DEFAULTS.BufferWriterInitialCapacity or 32
	requested = math.max(1, math.floor(requested))
	return setmetatable({
		Core = util.writer(requested),
		LastWorkingBytes = requested,
		LastUsedBytes = 0,
		LastRemovedBytes = 0,
	}, Writer)
end

function Writer:U8(value)
	self.Core:WriteU8(value)
end

function Writer:U32(value)
	self.Core:WriteU32(value)
end

function Writer:F64(value)
	self.Core:WriteF64(value)
end

function Writer:RawString(value)
	self.Core:WriteString(value)
end

function Writer:RawBuffer(value)
	self.Core:WriteBuffer(value)
end

function Writer:VarUInt(value)
	assert(value >= 0 and value <= MAX_SAFE_INTEGER and isInteger(value), "VarUInt expects a non-negative safe integer")
	self.Core:WriteVarUInt(value)
end

function Writer:VarInt(value)
	assert(math.abs(value) <= MAX_SAFE_SIGNED_VARINT and isInteger(value), "VarInt expects a safe integer")
	self.Core:WriteVarInt(value)
end

function Writer:Finish()
	local util = getBufferUtil()
	local usedBytes = self.Core:Length()
	local working = self.Core:GetBuffer()
	local workingBytes = buffer.len(working)
	local out = util.compactBytes(working, usedBytes)

	self.LastWorkingBytes = workingBytes
	self.LastUsedBytes = usedBytes
	self.LastRemovedBytes = math.max(0, workingBytes - usedBytes)
	return out
end

function Writer:GetCompactionInfo()
	return {
		WorkingBytes = self.LastWorkingBytes or 0,
		UsedBytes = self.LastUsedBytes or 0,
		RemovedBytes = self.LastRemovedBytes or 0,
	}
end

local Reader = {}
Reader.__index = Reader

function Reader.new(data)
	return setmetatable({
		Data = data,
		Position = 0,
		Length = buffer.len(data),
	}, Reader)
end

function Reader:Need(bytes)
	if bytes < 0 or self.Position + bytes > self.Length then
		error("DataStore buffer decode overflow", 0)
	end
end

function Reader:U8()
	self:Need(1)
	local value = buffer.readu8(self.Data, self.Position)
	self.Position += 1
	return value
end

function Reader:U32()
	self:Need(4)
	local value = buffer.readu32(self.Data, self.Position)
	self.Position += 4
	return value
end

function Reader:F64()
	self:Need(8)
	local value = buffer.readf64(self.Data, self.Position)
	self.Position += 8
	return value
end

function Reader:RawString(length)
	self:Need(length)
	local value = if length == 0 then "" else buffer.readstring(self.Data, self.Position, length)
	self.Position += length
	return value
end

function Reader:RawBuffer(length)
	self:Need(length)
	local out = buffer.create(length)
	if length > 0 then
		buffer.copy(out, 0, self.Data, self.Position, length)
		self.Position += length
	end
	return out
end

function Reader:VarUInt()
	local result = 0
	local multiplier = 1
	for _ = 1, 8 do
		local byte = self:U8()
		result += (byte % 128) * multiplier
		if result > MAX_SAFE_INTEGER then
			error("DataStore buffer VarUInt exceeds safe integer range", 0)
		end
		if byte < 128 then
			return result
		end
		multiplier *= 128
	end
	error("DataStore buffer VarUInt overflow", 0)
end

function Reader:VarInt()
	local value = self:VarUInt()
	if value % 2 == 0 then
		return value / 2
	end
	return -((value + 1) / 2)
end

local function adler32(data, startOffset, length)
	local a = 1
	local b = 0
	local stop = startOffset + length
	local i = startOffset
	while i < stop do
		local chunkStop = math.min(i + 4096, stop)
		while i < chunkStop do
			a = (a + buffer.readu8(data, i)) % ADLER_MOD
			b = (b + a) % ADLER_MOD
			i += 1
		end
	end
	return b * 65536 + a
end

-- v1.8.4 positional schema codec. Only one top-level local is used for the
-- whole implementation so the module keeps substantial headroom under Luau's
-- 200-local/register limit.
local SchemaCodec = {
	MAGIC = 0xA4,
	VERSION = 1,
	KIND_UINT = "uint",
	KIND_INT = "int",
	KIND_F64 = "f64",
	KIND_BOOL = "bool",
	KIND_STRING = "string",
	KIND_BUFFER = "buffer",
	KIND_VECTOR2 = "Vector2",
	KIND_VECTOR3 = "Vector3",
	KIND_COLOR3 = "Color3",
	KIND_CFRAME = "CFrame",
	KIND_UDIM = "UDim",
	KIND_UDIM2 = "UDim2",
}

function SchemaCodec.kindForDefault(value)
	local kind = typeof(value)
	if kind == "number" then
		if isInteger(value) and value >= 0 and value <= MAX_SAFE_INTEGER then
			return SchemaCodec.KIND_UINT
		elseif isInteger(value) and math.abs(value) <= MAX_SAFE_SIGNED_VARINT then
			return SchemaCodec.KIND_INT
		end
		return SchemaCodec.KIND_F64
	elseif kind == "boolean" then
		return SchemaCodec.KIND_BOOL
	elseif kind == "string" then
		return SchemaCodec.KIND_STRING
	elseif kind == "buffer" then
		return SchemaCodec.KIND_BUFFER
	elseif kind == "Vector2" then
		return SchemaCodec.KIND_VECTOR2
	elseif kind == "Vector3" then
		return SchemaCodec.KIND_VECTOR3
	elseif kind == "Color3" then
		return SchemaCodec.KIND_COLOR3
	elseif kind == "CFrame" then
		return SchemaCodec.KIND_CFRAME
	elseif kind == "UDim" then
		return SchemaCodec.KIND_UDIM
	elseif kind == "UDim2" then
		return SchemaCodec.KIND_UDIM2
	end
	return nil
end

function SchemaCodec.pathValue(root, path)
	local current = root
	for i = 1, #path do
		if type(current) ~= "table" then
			return nil
		end
		current = current[path[i]]
	end
	return current
end

function SchemaCodec.setPathValue(root, path, value)
	local current = root
	for i = 1, #path - 1 do
		local key = path[i]
		local nextValue = current[key]
		if type(nextValue) ~= "table" then
			nextValue = {}
			current[key] = nextValue
		end
		current = nextValue
	end
	current[path[#path]] = value
end

function SchemaCodec.valuesEqual(a, b, kind)
	if kind == SchemaCodec.KIND_BUFFER then
		if typeof(a) ~= "buffer" or typeof(b) ~= "buffer" then
			return false
		end
		local length = buffer.len(a)
		if length ~= buffer.len(b) then
			return false
		end
		for i = 0, length - 1 do
			if buffer.readu8(a, i) ~= buffer.readu8(b, i) then
				return false
			end
		end
		return true
	end
	return a == b
end

function SchemaCodec.defaultDescriptor(value, kind)
	if kind == SchemaCodec.KIND_UINT or kind == SchemaCodec.KIND_INT or kind == SchemaCodec.KIND_F64 then
		return string.format("%.17g", value)
	elseif kind == SchemaCodec.KIND_BOOL then
		return value and "1" or "0"
	elseif kind == SchemaCodec.KIND_STRING then
		return value
	elseif kind == SchemaCodec.KIND_BUFFER then
		local length = buffer.len(value)
		return length > 0 and buffer.readstring(value, 0, length) or ""
	elseif kind == SchemaCodec.KIND_VECTOR2 then
		return string.format("%.17g,%.17g", value.X, value.Y)
	elseif kind == SchemaCodec.KIND_VECTOR3 then
		return string.format("%.17g,%.17g,%.17g", value.X, value.Y, value.Z)
	elseif kind == SchemaCodec.KIND_COLOR3 then
		return string.format("%.17g,%.17g,%.17g", value.R, value.G, value.B)
	elseif kind == SchemaCodec.KIND_CFRAME then
		local components = {value:GetComponents()}
		local parts = table.create(12)
		for i = 1, 12 do parts[i] = string.format("%.17g", components[i]) end
		return table.concat(parts, ",")
	elseif kind == SchemaCodec.KIND_UDIM then
		return string.format("%.17g,%.0f", value.Scale, value.Offset)
	elseif kind == SchemaCodec.KIND_UDIM2 then
		return string.format("%.17g,%.0f,%.17g,%.0f", value.X.Scale, value.X.Offset, value.Y.Scale, value.Y.Offset)
	end
	return ""
end

function SchemaCodec.compile(template, version)
	if type(template) ~= "table" then
		return nil, "Schema template must be a table"
	end

	local leaves = {}
	local descriptor = {}

	local function walk(node, path)
		if type(node) == "table" then
			local arrayMode, arrayLength = isArray(node)
			if arrayMode and arrayLength > 0 then
				return false, "SchemaBuffer does not encode variable/array template nodes"
			end
			if next(node) == nil then
				return false, "SchemaBuffer does not encode empty/dynamic template tables"
			end

			local keys = {}
			for key in pairs(node) do
				if type(key) ~= "string" then
					return false, "SchemaBuffer map keys must be strings"
				end
				keys[#keys + 1] = key
			end
			table.sort(keys)

			for _, key in ipairs(keys) do
				local childPath = table.clone(path)
				childPath[#childPath + 1] = key
				local ok, reason = walk(node[key], childPath)
				if not ok then
					return false, reason
				end
			end
			return true
		end

		local kind = SchemaCodec.kindForDefault(node)
		if kind == nil then
			return false, "SchemaBuffer unsupported template leaf type " .. typeof(node)
		end

		local pathText = table.concat(path, ".")
		leaves[#leaves + 1] = {
			Path = path,
			PathText = pathText,
			Kind = kind,
			Default = deepCopy(node),
		}

		for _, component in ipairs(path) do
			descriptor[#descriptor + 1] = tostring(#component)
			descriptor[#descriptor + 1] = ":"
			descriptor[#descriptor + 1] = component
			descriptor[#descriptor + 1] = "/"
		end
		descriptor[#descriptor + 1] = kind
		descriptor[#descriptor + 1] = "="
		local defaultDescriptor = SchemaCodec.defaultDescriptor(node, kind)
		descriptor[#descriptor + 1] = tostring(#defaultDescriptor)
		descriptor[#descriptor + 1] = ":"
		descriptor[#descriptor + 1] = defaultDescriptor
		descriptor[#descriptor + 1] = ";"
		return true
	end

	local ok, reason = walk(template, {})
	if not ok then
		return nil, reason
	end
	if #leaves == 0 then
		return nil, "SchemaBuffer requires at least one fixed leaf"
	end

	local descriptorString = table.concat(descriptor)
	local descriptorBuffer = buffer.fromstring(descriptorString)
	local fingerprint = adler32(descriptorBuffer, 0, buffer.len(descriptorBuffer))

	return {
		Version = version,
		Template = deepCopy(template),
		Leaves = leaves,
		FieldCount = #leaves,
		BitmapBytes = math.ceil(#leaves / 8),
		Fingerprint = fingerprint,
		Descriptor = descriptorString,
	}
end

function SchemaCodec.ensureConfig(config)
	if config._SchemaPrepared == true then
		return
	end

	config._SchemaPrepared = true
	config._SchemaByVersion = {}
	config._SchemaCurrent = nil
	config._SchemaReason = "SchemaBufferDisabled"

	if config.SchemaBufferEnabled ~= true then
		return
	end

	local current, currentReason = SchemaCodec.compile(config.Template or {}, config.DataVersion or 1)
	if current ~= nil then
		config._SchemaCurrent = current
		config._SchemaByVersion[current.Version] = current
		config._SchemaReason = nil
	else
		config._SchemaReason = currentReason
	end

	if type(config.SchemaHistory) == "table" then
		for rawVersion, historical in pairs(config.SchemaHistory) do
			local historyVersion = tonumber(rawVersion)
			if historyVersion ~= nil and historyVersion >= 0 and historyVersion == math.floor(historyVersion) then
				local historyData = historical
				if type(historical) == "table" and type(historical.Data) == "table" then
					historyData = historical.Data
				end
				if type(historyData) == "table" and config._SchemaByVersion[historyVersion] == nil then
					local compiled = SchemaCodec.compile(historyData, historyVersion)
					if compiled ~= nil then
						config._SchemaByVersion[historyVersion] = compiled
					end
				end
			end
		end
	end
end

function SchemaCodec.isFrame(data)
	return typeof(data) == "buffer"
		and buffer.len(data) >= 2
		and buffer.readu8(data, 0) == SchemaCodec.MAGIC
end

function SchemaCodec.writeLeaf(writer, leaf, value)
	local kind = leaf.Kind
	if kind == SchemaCodec.KIND_UINT then
		if type(value) ~= "number" or not isInteger(value) or value < 0 or value > MAX_SAFE_INTEGER then
			error("SchemaBuffer unsigned field " .. leaf.PathText .. " is outside VarUInt range", 0)
		end
		writer:VarUInt(value)
	elseif kind == SchemaCodec.KIND_INT then
		if type(value) ~= "number" or not isInteger(value) or math.abs(value) > MAX_SAFE_SIGNED_VARINT then
			error("SchemaBuffer integer field " .. leaf.PathText .. " is outside signed VarInt range", 0)
		end
		writer:VarInt(value)
	elseif kind == SchemaCodec.KIND_F64 then
		if not isFiniteNumber(value) then
			error("SchemaBuffer number field " .. leaf.PathText .. " must be finite", 0)
		end
		writer:F64(value)
	elseif kind == SchemaCodec.KIND_BOOL then
		if type(value) ~= "boolean" then
			error("SchemaBuffer boolean field " .. leaf.PathText .. " changed type", 0)
		end
		-- A present boolean is always the inverse of its template default, so the
		-- presence bit itself stores the complete value with zero payload bytes.
	elseif kind == SchemaCodec.KIND_STRING then
		if type(value) ~= "string" then
			error("SchemaBuffer string field " .. leaf.PathText .. " changed type", 0)
		end
		writer:VarUInt(#value)
		writer:RawString(value)
	elseif kind == SchemaCodec.KIND_BUFFER then
		if typeof(value) ~= "buffer" then
			error("SchemaBuffer buffer field " .. leaf.PathText .. " changed type", 0)
		end
		writer:VarUInt(buffer.len(value))
		writer:RawBuffer(value)
	elseif kind == SchemaCodec.KIND_VECTOR2 then
		if typeof(value) ~= "Vector2" then error("SchemaBuffer Vector2 type mismatch at " .. leaf.PathText, 0) end
		writer:F64(value.X); writer:F64(value.Y)
	elseif kind == SchemaCodec.KIND_VECTOR3 then
		if typeof(value) ~= "Vector3" then error("SchemaBuffer Vector3 type mismatch at " .. leaf.PathText, 0) end
		writer:F64(value.X); writer:F64(value.Y); writer:F64(value.Z)
	elseif kind == SchemaCodec.KIND_COLOR3 then
		if typeof(value) ~= "Color3" then error("SchemaBuffer Color3 type mismatch at " .. leaf.PathText, 0) end
		writer:F64(value.R); writer:F64(value.G); writer:F64(value.B)
	elseif kind == SchemaCodec.KIND_CFRAME then
		if typeof(value) ~= "CFrame" then error("SchemaBuffer CFrame type mismatch at " .. leaf.PathText, 0) end
		local components = {value:GetComponents()}
		for i = 1, 12 do writer:F64(components[i]) end
	elseif kind == SchemaCodec.KIND_UDIM then
		if typeof(value) ~= "UDim" then error("SchemaBuffer UDim type mismatch at " .. leaf.PathText, 0) end
		writer:F64(value.Scale); writer:VarInt(value.Offset)
	elseif kind == SchemaCodec.KIND_UDIM2 then
		if typeof(value) ~= "UDim2" then error("SchemaBuffer UDim2 type mismatch at " .. leaf.PathText, 0) end
		writer:F64(value.X.Scale); writer:VarInt(value.X.Offset)
		writer:F64(value.Y.Scale); writer:VarInt(value.Y.Offset)
	else
		error("SchemaBuffer has unknown field kind " .. tostring(kind), 0)
	end
end

function SchemaCodec.readLeaf(reader, leaf, config)
	local kind = leaf.Kind
	if kind == SchemaCodec.KIND_UINT then
		return reader:VarUInt()
	elseif kind == SchemaCodec.KIND_INT then
		return reader:VarInt()
	elseif kind == SchemaCodec.KIND_F64 then
		return reader:F64()
	elseif kind == SchemaCodec.KIND_BOOL then
		return not leaf.Default
	elseif kind == SchemaCodec.KIND_STRING then
		local length = reader:VarUInt()
		if length > config.MaxBufferBytes then error("SchemaBuffer string exceeds MaxBufferBytes", 0) end
		return reader:RawString(length)
	elseif kind == SchemaCodec.KIND_BUFFER then
		local length = reader:VarUInt()
		if length > config.MaxBufferBytes then error("SchemaBuffer nested buffer exceeds MaxBufferBytes", 0) end
		return reader:RawBuffer(length)
	elseif kind == SchemaCodec.KIND_VECTOR2 then
		return Vector2.new(reader:F64(), reader:F64())
	elseif kind == SchemaCodec.KIND_VECTOR3 then
		return Vector3.new(reader:F64(), reader:F64(), reader:F64())
	elseif kind == SchemaCodec.KIND_COLOR3 then
		return Color3.new(reader:F64(), reader:F64(), reader:F64())
	elseif kind == SchemaCodec.KIND_CFRAME then
		local components = table.create(12)
		for i = 1, 12 do components[i] = reader:F64() end
		return CFrame.new(table.unpack(components, 1, 12))
	elseif kind == SchemaCodec.KIND_UDIM then
		return UDim.new(reader:F64(), reader:VarInt())
	elseif kind == SchemaCodec.KIND_UDIM2 then
		return UDim2.new(reader:F64(), reader:VarInt(), reader:F64(), reader:VarInt())
	end
	error("SchemaBuffer contains unknown field kind " .. tostring(kind), 0)
end

function SchemaCodec.structureCompatible(data, template, pathText)
	pathText = pathText or "Data"
	if type(template) ~= "table" then
		return true
	end
	if data == nil then
		return true
	end
	if type(data) ~= "table" then
		return false, pathText .. " changed from a schema table into " .. typeof(data)
	end

	for key in pairs(data) do
		if template[key] == nil then
			return false, pathText .. " contains schema-unknown field " .. tostring(key)
		end
	end

	for key, defaultValue in pairs(template) do
		if type(defaultValue) == "table" then
			local ok, reason = SchemaCodec.structureCompatible(data[key], defaultValue, pathText .. "." .. tostring(key))
			if not ok then return false, reason end
		end
	end
	return true
end

function SchemaCodec.encode(dataTemplate, config)
	SchemaCodec.ensureConfig(config)
	if config.SchemaBufferEnabled ~= true then
		return nil, "Disabled"
	end
	if type(dataTemplate) ~= "table" or type(dataTemplate.Data) ~= "table" or type(dataTemplate.Version) ~= "number" then
		return nil, "InvalidDataTemplate"
	end

	local schema = config._SchemaByVersion and config._SchemaByVersion[dataTemplate.Version] or nil
	if schema == nil then
		return nil, "No schema is available for DataTemplate version " .. tostring(dataTemplate.Version)
	end

	local compatible, compatibilityError = SchemaCodec.structureCompatible(dataTemplate.Data, schema.Template, "Data")
	if not compatible then
		return nil, compatibilityError
	end

	local bitmap = buffer.create(schema.BitmapBytes)
	local present = table.create(schema.FieldCount, false)
	local presentCount = 0

	for index, leaf in ipairs(schema.Leaves) do
		local value = SchemaCodec.pathValue(dataTemplate.Data, leaf.Path)
		if value == nil then
			value = leaf.Default
		end
		if not SchemaCodec.valuesEqual(value, leaf.Default, leaf.Kind) then
			present[index] = true
			presentCount += 1
			buffer.writebits(bitmap, index - 1, 1, 1)
		end
	end

	local writer = Writer.new(config.BufferWriterInitialCapacity or 32)
	writer:U8(SchemaCodec.MAGIC)
	writer:U8(SchemaCodec.VERSION)
	writer:VarUInt(dataTemplate.Version)
	writer:U32(schema.Fingerprint)
	writer:RawBuffer(bitmap)

	local okWrite, writeError = pcall(function()
		for index, leaf in ipairs(schema.Leaves) do
			if present[index] then
				local value = SchemaCodec.pathValue(dataTemplate.Data, leaf.Path)
				if value == nil then value = leaf.Default end
				SchemaCodec.writeLeaf(writer, leaf, value)
			end
		end
	end)
	if not okWrite then
		return nil, writeError
	end

	local body = writer:Finish()
	local compactInfo = writer:GetCompactionInfo()
	local bodyLength = buffer.len(body)
	local out = buffer.create(bodyLength + 4)
	if bodyLength > 0 then buffer.copy(out, 0, body, 0, bodyLength) end
	buffer.writeu32(out, bodyLength, adler32(out, 0, bodyLength))

	return out, {
		RawBytes = buffer.len(out),
		FieldCount = schema.FieldCount,
		PresentFields = presentCount,
		DefaultFieldsOmitted = schema.FieldCount - presentCount,
		Fingerprint = schema.Fingerprint,
		Version = schema.Version,
		WorkingBufferBytes = compactInfo.WorkingBytes,
		CompactedPayloadBytes = compactInfo.UsedBytes + 4,
		UnusedWorkingBytesRemoved = compactInfo.RemovedBytes,
	}
end

function SchemaCodec.decode(raw, config)
	if not SchemaCodec.isFrame(raw) then
		return nil
	end
	SchemaCodec.ensureConfig(config)

	local length = buffer.len(raw)
	if length < 11 then error("SchemaBuffer frame is too small", 0) end
	local expectedChecksum = buffer.readu32(raw, length - 4)
	local actualChecksum = adler32(raw, 0, length - 4)
	if expectedChecksum ~= actualChecksum then error("SchemaBuffer checksum mismatch", 0) end

	local reader = Reader.new(raw)
	reader.Length = length - 4
	if reader:U8() ~= SchemaCodec.MAGIC then error("SchemaBuffer magic mismatch", 0) end
	local codecVersion = reader:U8()
	if codecVersion ~= SchemaCodec.VERSION then
		error("Unsupported SchemaBuffer codec version " .. tostring(codecVersion), 0)
	end

	local dataVersion = reader:VarUInt()
	local fingerprint = reader:U32()
	local schema = config._SchemaByVersion and config._SchemaByVersion[dataVersion] or nil
	if schema == nil then
		error(
			"SchemaBuffer save uses DataTemplate version " .. tostring(dataVersion)
				.. ", but Config.SchemaHistory does not contain that template",
			0
		)
	end
	if fingerprint ~= schema.Fingerprint then
		error(
			"SchemaBuffer fingerprint mismatch for DataTemplate version " .. tostring(dataVersion)
				.. "; bump DataTemplate.Version and preserve the old template in Config.SchemaHistory",
			0
		)
	end

	local bitmap = reader:RawBuffer(schema.BitmapBytes)
	local data = deepCopy(schema.Template)
	local presentCount = 0
	for index, leaf in ipairs(schema.Leaves) do
		if buffer.readbits(bitmap, index - 1, 1) ~= 0 then
			presentCount += 1
			SchemaCodec.setPathValue(data, leaf.Path, SchemaCodec.readLeaf(reader, leaf, config))
		end
	end
	if reader.Position ~= reader.Length then
		error("SchemaBuffer frame contains trailing payload bytes", 0)
	end

	validateSavable(data, "SchemaBufferData", nil, 0, nil, config)
	return {
		Version = dataVersion,
		Data = data,
	}, {
		FieldCount = schema.FieldCount,
		PresentFields = presentCount,
		DefaultFieldsOmitted = schema.FieldCount - presentCount,
		Fingerprint = fingerprint,
	}
end

local writeValue
local readValue

writeValue = function(writer, value, depth, seen, state, config)
	if depth > config.MaxDepth then
		error("DataStore buffer encode exceeded MaxDepth", 0)
	end

	local robloxType = typeof(value)
	local valueType = type(value)

	if value == nil then
		writer:U8(TAG_NIL)
	elseif valueType == "boolean" then
		writer:U8(if value then TAG_TRUE else TAG_FALSE)
	elseif valueType == "number" then
		if not isFiniteNumber(value) then
			error("DataStore buffer cannot encode NaN or infinity", 0)
		end
		if isInteger(value) and value >= 0 and value <= MAX_SAFE_INTEGER then
			writer:U8(TAG_UINT)
			writer:VarUInt(value)
		elseif isInteger(value) and math.abs(value) <= MAX_SAFE_SIGNED_VARINT then
			writer:U8(TAG_SINT)
			writer:VarInt(value)
		else
			writer:U8(TAG_F64)
			writer:F64(value)
		end
	elseif valueType == "string" then
		writer:U8(TAG_STRING)
		writer:VarUInt(#value)
		writer:RawString(value)
	elseif robloxType == "buffer" then
		writer:U8(TAG_BUFFER)
		writer:VarUInt(buffer.len(value))
		writer:RawBuffer(value)
	elseif robloxType == "Vector2" then
		writer:U8(TAG_VECTOR2)
		writer:F64(value.X)
		writer:F64(value.Y)
	elseif robloxType == "Vector3" then
		writer:U8(TAG_VECTOR3)
		writer:F64(value.X)
		writer:F64(value.Y)
		writer:F64(value.Z)
	elseif robloxType == "Color3" then
		writer:U8(TAG_COLOR3)
		writer:F64(value.R)
		writer:F64(value.G)
		writer:F64(value.B)
	elseif robloxType == "CFrame" then
		writer:U8(TAG_CFRAME)
		local components = { value:GetComponents() }
		for i = 1, 12 do
			writer:F64(components[i])
		end
	elseif robloxType == "UDim" then
		writer:U8(TAG_UDIM)
		writer:F64(value.Scale)
		writer:VarInt(value.Offset)
	elseif robloxType == "UDim2" then
		writer:U8(TAG_UDIM2)
		writer:F64(value.X.Scale)
		writer:VarInt(value.X.Offset)
		writer:F64(value.Y.Scale)
		writer:VarInt(value.Y.Offset)
	elseif valueType == "table" then
		if seen[value] then
			error("DataStore buffer cannot encode circular tables", 0)
		end
		seen[value] = true

		local arrayMode, length = isArray(value)
		if arrayMode then
			writer:U8(TAG_ARRAY)
			writer:VarUInt(length)
			state.Entries += length
			if state.Entries > config.MaxTableEntries then
				error("DataStore buffer encode exceeded MaxTableEntries", 0)
			end
			for i = 1, length do
				writeValue(writer, value[i], depth + 1, seen, state, config)
			end
		else
			local keys = {}
			for key in pairs(value) do
				if type(key) ~= "string" then
					error("DataStore buffer maps require string keys", 0)
				end
				keys[#keys + 1] = key
			end
			table.sort(keys)
			writer:U8(TAG_MAP)
			writer:VarUInt(#keys)
			state.Entries += #keys
			if state.Entries > config.MaxTableEntries then
				error("DataStore buffer encode exceeded MaxTableEntries", 0)
			end
			for _, key in ipairs(keys) do
				writer:VarUInt(#key)
				writer:RawString(key)
				writeValue(writer, value[key], depth + 1, seen, state, config)
			end
		end

		seen[value] = nil
	else
		error("DataStore buffer cannot encode type " .. robloxType, 0)
	end
end

readValue = function(reader, depth, state, config)
	if depth > config.MaxDepth then
		error("DataStore buffer decode exceeded MaxDepth", 0)
	end

	local tag = reader:U8()
	if tag == TAG_NIL then
		return nil
	elseif tag == TAG_FALSE then
		return false
	elseif tag == TAG_TRUE then
		return true
	elseif tag == TAG_UINT then
		return reader:VarUInt()
	elseif tag == TAG_SINT then
		return reader:VarInt()
	elseif tag == TAG_F64 then
		local value = reader:F64()
		if not isFiniteNumber(value) then
			error("DataStore buffer decoded NaN or infinity", 0)
		end
		return value
	elseif tag == TAG_STRING then
		local length = reader:VarUInt()
		return reader:RawString(length)
	elseif tag == TAG_BUFFER then
		local length = reader:VarUInt()
		return reader:RawBuffer(length)
	elseif tag == TAG_VECTOR2 then
		return Vector2.new(reader:F64(), reader:F64())
	elseif tag == TAG_VECTOR3 then
		return Vector3.new(reader:F64(), reader:F64(), reader:F64())
	elseif tag == TAG_COLOR3 then
		return Color3.new(reader:F64(), reader:F64(), reader:F64())
	elseif tag == TAG_CFRAME then
		local components = table.create(12)
		for i = 1, 12 do
			components[i] = reader:F64()
		end
		return CFrame.new(table.unpack(components, 1, 12))
	elseif tag == TAG_UDIM then
		return UDim.new(reader:F64(), reader:VarInt())
	elseif tag == TAG_UDIM2 then
		local xScale = reader:F64()
		local xOffset = reader:VarInt()
		local yScale = reader:F64()
		local yOffset = reader:VarInt()
		return UDim2.new(xScale, xOffset, yScale, yOffset)
	elseif tag == TAG_ARRAY then
		local length = reader:VarUInt()
		state.Entries += length
		if state.Entries > config.MaxTableEntries then
			error("DataStore buffer decode exceeded MaxTableEntries", 0)
		end
		local out = table.create(length)
		for i = 1, length do
			out[i] = readValue(reader, depth + 1, state, config)
		end
		return out
	elseif tag == TAG_MAP then
		local count = reader:VarUInt()
		state.Entries += count
		if state.Entries > config.MaxTableEntries then
			error("DataStore buffer decode exceeded MaxTableEntries", 0)
		end
		local out = {}
		for _ = 1, count do
			local keyLength = reader:VarUInt()
			local key = reader:RawString(keyLength)
			out[key] = readValue(reader, depth + 1, state, config)
		end
		return out
	end

	error("DataStore buffer contains unknown type tag " .. tostring(tag), 0)
end

local function encodeBuffer(value, config)
	config = config or DEFAULTS
	local codecConfig = table.clone(config)
	codecConfig.StorageMode = "Buffer"
	validateSavable(value, "Data", nil, 0, nil, codecConfig)

	local payloadWriter = Writer.new(config.BufferWriterInitialCapacity or 32)
	writeValue(payloadWriter, value, 0, {}, { Entries = 0 }, codecConfig)
	local payload = payloadWriter:Finish()
	local compactionInfo = payloadWriter:GetCompactionInfo()
	local payloadLength = buffer.len(payload)
	local totalLength = 4 + 1 + payloadLength + 4

	if totalLength > codecConfig.MaxBufferBytes then
		error(string.format("Encoded buffer is %d bytes, above MaxBufferBytes (%d)", totalLength, codecConfig.MaxBufferBytes), 2)
	end

	local out = buffer.create(totalLength)
	buffer.writestring(out, 0, CODEC_MAGIC)
	buffer.writeu8(out, 4, CODEC_VERSION)
	if payloadLength > 0 then
		buffer.copy(out, 5, payload, 0, payloadLength)
	end
	buffer.writeu32(out, 5 + payloadLength, adler32(out, 0, 5 + payloadLength))
	return out, compactionInfo
end

local function decodeBuffer(data, config)
	config = config or DEFAULTS
	local codecConfig = table.clone(config)
	codecConfig.StorageMode = "Buffer"
	assert(typeof(data) == "buffer", "Decode expects a buffer")

	local length = buffer.len(data)
	if length < 9 then
		error("DataStore buffer is too small", 2)
	end
	if length > codecConfig.MaxBufferBytes then
		error("DataStore buffer exceeds MaxBufferBytes", 2)
	end

	local magic = buffer.readstring(data, 0, 4)
	if magic ~= CODEC_MAGIC then
		error("DataStore buffer has invalid magic", 2)
	end

	local version = buffer.readu8(data, 4)
	if version ~= CODEC_VERSION then
		error("Unsupported DataStore buffer codec version " .. tostring(version), 2)
	end

	local expectedChecksum = buffer.readu32(data, length - 4)
	local actualChecksum = adler32(data, 0, length - 4)
	if expectedChecksum ~= actualChecksum then
		error("DataStore buffer checksum mismatch", 2)
	end

	local payloadLength = length - 9
	local payload = buffer.create(payloadLength)
	if payloadLength > 0 then
		buffer.copy(payload, 0, data, 5, payloadLength)
	end

	local reader = Reader.new(payload)
	local value = readValue(reader, 0, { Entries = 0 }, codecConfig)
	if reader.Position ~= reader.Length then
		error("DataStore buffer contains trailing bytes", 2)
	end
	validateSavable(value, "Data", nil, 0, nil, codecConfig)
	return value
end

local function compressionOptions(config)
	return {
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

local function tableCompressionOptions(config)
	return {
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

local function cloneRawBuffer(value)
	local out = buffer.create(buffer.len(value))
	if buffer.len(value) > 0 then
		buffer.copy(out, 0, value, 0, buffer.len(value))
	end
	return out
end

local function compressStorageBuffer(rawPayload, config)
	local rawBytes = buffer.len(rawPayload)
	if not config.CompressionEnabled or rawBytes < config.CompressionMinBufferBytes then
		return cloneRawBuffer(rawPayload), false, {
			RawBytes = rawBytes,
			StoredBytes = rawBytes,
			SavedBytes = 0,
			SavingsPercent = 0,
			Mode = "Raw",
		}
	end

	local codec = getCompression()
	local ok, packed = pcall(codec.CompressBuffer, rawPayload, compressionOptions(config))
	if not ok or typeof(packed) ~= "buffer" then
		debugWarn(config, "Buffer compression failed; saving raw BufferV1 payload instead:", packed)
		return cloneRawBuffer(rawPayload), false, {
			RawBytes = rawBytes,
			StoredBytes = rawBytes,
			SavedBytes = 0,
			SavingsPercent = 0,
			Mode = "RawFallback",
		}
	end

	local storedBytes = buffer.len(packed)
	local savedBytes = rawBytes - storedBytes
	if savedBytes < config.CompressionMinSavingsBytes then
		return cloneRawBuffer(rawPayload), false, {
			RawBytes = rawBytes,
			StoredBytes = rawBytes,
			SavedBytes = 0,
			SavingsPercent = 0,
			Mode = "Raw",
		}
	end

	local mode = "Compressed"
	if type(codec.BufferMode) == "function" then
		local modeOk, modeResult = pcall(codec.BufferMode, packed)
		if modeOk and type(modeResult) == "string" then
			mode = modeResult
		end
	end

	return packed, true, {
		RawBytes = rawBytes,
		StoredBytes = storedBytes,
		SavedBytes = savedBytes,
		SavingsPercent = rawBytes > 0 and (savedBytes / rawBytes * 100) or 0,
		Mode = mode,
	}
end

local function compressStorageTable(dataTemplate, config)
	validateSavable(dataTemplate, "DataTemplate", nil, 0, nil, config)
	SchemaCodec.ensureConfig(config)

	-- Generic SDSB remains the compatibility/reference candidate. RawBytes keeps
	-- measuring this complete named DataTemplate so savings from SchemaBuffer are
	-- visible against the old representation.
	local rawPayload, rawCompactInfo = encodeBuffer(dataTemplate, config)
	local rawBytes = buffer.len(rawPayload)
	local bestPayload = rawPayload
	local bestBytes = rawBytes
	local bestMode = "LegacyRawBuffer"
	local bestCompressed = false
	local bestSchemaSelected = false

	local schemaInfo = nil
	local schemaCandidateBytes = nil
	local schemaCandidateMode = nil

	local function selectCandidate(payload, mode, compressed, schemaSelected)
		local bytes = buffer.len(payload)
		if bytes < bestBytes then
			bestPayload = payload
			bestBytes = bytes
			bestMode = mode
			bestCompressed = compressed == true
			bestSchemaSelected = schemaSelected == true
			return true
		end
		return false
	end

	-- Candidate S: positional SchemaBuffer. Field names and generic value-type
	-- tags are removed because the versioned DataTemplate itself is the schema.
	if config.SchemaBufferEnabled == true then
		local schemaOk, schemaPayload, schemaResult = pcall(SchemaCodec.encode, dataTemplate, config)
		if schemaOk and typeof(schemaPayload) == "buffer" then
			schemaInfo = schemaResult
			local candidate = schemaPayload
			local candidateMode = "SchemaBuffer/Raw"
			local candidateCompressed = false

			if config.CompressionEnabled and config.SchemaBufferCompress then
				local codec = getCompression()
				local smartOk, smartPayload, smartCompressed = pcall(
					codec.CompressBufferSmart,
					schemaPayload,
					compressionOptions(config)
				)
				if smartOk and typeof(smartPayload) == "buffer" and buffer.len(smartPayload) < buffer.len(candidate) then
					candidate = smartPayload
					candidateCompressed = smartCompressed == true
					local bufferMode = "Compressed"
					if type(codec.BufferMode) == "function" then
						local modeOk, modeValue = pcall(codec.BufferMode, smartPayload)
						if modeOk and type(modeValue) == "string" then bufferMode = modeValue end
					end
					candidateMode = "SchemaBuffer/" .. bufferMode
				end
			end

			schemaCandidateBytes = buffer.len(candidate)
			schemaCandidateMode = candidateMode
			selectCandidate(candidate, candidateMode, candidateCompressed, true)
		else
			local reason = if schemaOk then schemaResult else schemaPayload
			if config.SchemaFallbackToGeneric ~= true then
				error("SchemaBuffer encode failed: " .. tostring(reason), 2)
			end
			debugWarn(config, "SchemaBuffer candidate unavailable; using generic codec candidates:", reason)
		end
	end

	-- SchemaBuffer is a storage encoding, not entropy compression, so it remains
	-- usable even when CompressionEnabled=false.
	if config.CompressionEnabled then
		-- Candidate A: v1.6-compatible SDSB bytes compressed by v2.6.7.
		if config.CompressionCompareLegacyBuffer ~= false then
			local legacyPayload, legacyCompressed, legacyStats = compressStorageBuffer(rawPayload, config)
			selectCandidate(
				legacyPayload,
				"LegacyBuffer/" .. tostring(legacyStats.Mode),
				legacyCompressed,
				false
			)
		end

		-- Candidate B: Compression v2.6.7 sees the full named DataTemplate. This
		-- remains important for dynamic/array-heavy templates that SchemaBuffer
		-- intentionally refuses to encode.
		local codec = getCompression()
		local ok, packet = pcall(codec.CompressTablePacket, dataTemplate, tableCompressionOptions(config))
		if ok
			and type(packet) == "table"
			and typeof(packet.Data) == "buffer" then
			local nativeData = packet.Data
			local nativeBackingBytes = buffer.len(nativeData)
			local reportedBytes = type(packet.Bytes) == "number" and math.floor(packet.Bytes) or nativeBackingBytes
			if reportedBytes >= 0 and reportedBytes < nativeBackingBytes then
				nativeData = getBufferUtil().compactBytes(nativeData, reportedBytes)
			end
			local nativeBytes = buffer.len(nativeData)
			local nativeSavings = rawBytes - nativeBytes
			if nativeBytes <= config.MaxBufferBytes and nativeSavings >= config.CompressionMinSavingsBytes then
				selectCandidate(
					nativeData,
					type(packet.Codec) == "string" and packet.Codec or "CompressionTable",
					true,
					false
				)
			end
		else
			debugWarn(config, "Compression v2.6.7 native table candidate failed; using another valid candidate:", packet)
		end
	end

	if bestBytes > config.MaxBufferBytes then
		error(string.format("Encoded DataTemplate is %d bytes, above MaxBufferBytes (%d)", bestBytes, config.MaxBufferBytes), 2)
	end

	local savedBytes = math.max(0, rawBytes - bestBytes)
	return bestPayload, {
		RawBytes = rawBytes,
		StoredBytes = bestBytes,
		SavedBytes = savedBytes,
		SavingsPercent = rawBytes > 0 and savedBytes / rawBytes * 100 or 0,
		Mode = bestMode,
		Compressed = bestCompressed,
		WorkingBufferBytes = rawCompactInfo and rawCompactInfo.WorkingBytes or rawBytes,
		CompactedPayloadBytes = rawCompactInfo and rawCompactInfo.UsedBytes or rawBytes,
		UnusedWorkingBytesRemoved = rawCompactInfo and rawCompactInfo.RemovedBytes or 0,
		SchemaEligible = config._SchemaCurrent ~= nil,
		SchemaCandidateAvailable = schemaInfo ~= nil,
		SchemaSelected = bestSchemaSelected,
		SchemaCandidateBytes = schemaCandidateBytes,
		SchemaCandidateMode = schemaCandidateMode,
		SchemaRawBytes = schemaInfo and schemaInfo.RawBytes or nil,
		SchemaFieldCount = schemaInfo and schemaInfo.FieldCount or (config._SchemaCurrent and config._SchemaCurrent.FieldCount or nil),
		SchemaPresentFields = schemaInfo and schemaInfo.PresentFields or nil,
		SchemaDefaultFieldsOmitted = schemaInfo and schemaInfo.DefaultFieldsOmitted or nil,
		SchemaFingerprint = schemaInfo and schemaInfo.Fingerprint or (config._SchemaCurrent and config._SchemaCurrent.Fingerprint or nil),
		SchemaWorkingBufferBytes = schemaInfo and schemaInfo.WorkingBufferBytes or nil,
		SchemaCompactedPayloadBytes = schemaInfo and schemaInfo.CompactedPayloadBytes or nil,
		SchemaUnusedWorkingBytesRemoved = schemaInfo and schemaInfo.UnusedWorkingBytesRemoved or 0,
	}
end

local function tryDecodeCompressionTable(storedPayload, config)
	local codec = getCompression()
	local ok, decoded = pcall(codec.DecompressTable, storedPayload, tableCompressionOptions(config))
	if not ok or type(decoded) ~= "table" then
		return nil
	end

	local valid = pcall(validateSavable, decoded, "DecodedDataTemplate", nil, 0, nil, config)
	if not valid then
		return nil
	end

	return decoded
end


local function decompressStorageBuffer(storedPayload, compressed, config)
	if not compressed then
		return cloneRawBuffer(storedPayload)
	end

	local codec = getCompression()
	local ok, rawPayload = pcall(codec.DecompressBuffer, storedPayload)
	if not ok then
		error("DataStore compressed BufferV1 payload failed to decompress: " .. tostring(rawPayload), 2)
	end
	if typeof(rawPayload) ~= "buffer" then
		error("DataStore Compression.DecompressBuffer returned a non-buffer value", 2)
	end
	if buffer.len(rawPayload) > config.MaxBufferBytes then
		error("DataStore decompressed BufferV1 payload exceeds MaxBufferBytes", 2)
	end
	return rawPayload
end


local function waitForBudget(config, requestType)
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

local function retryAsync(config, requestType, callback)
	local lastError = nil

	for attempt = 1, config.RetryAttempts do
		local budgetOk, budgetError = waitForBudget(config, requestType)
		if not budgetOk then
			lastError = budgetError
		else
			local ok, result = pcall(callback)
			if ok then
				return true, result
			end
			lastError = result
		end

		if attempt < config.RetryAttempts then
			local delayTime = math.min(config.RetryDelay * (2 ^ (attempt - 1)), config.MaxRetryDelay)
			delayTime += math.random() * 0.2
			task.wait(delayTime)
		end
	end

	return false, lastError
end

local function resolveUserId(subject)
	if typeof(subject) == "Instance" and subject:IsA("Player") then
		return subject.UserId, subject
	end

	assert(type(subject) == "number" and subject > 0 and subject == math.floor(subject), "Expected a Player or positive integer UserId")
	return subject, Players:GetPlayerByUserId(subject)
end



local function makeDataTemplate(version, data)
	return {
		Version = version,
		Data = deepCopy(data),
	}
end

local function mergeConfig(config)
	local out = table.clone(DEFAULTS)

	for key, value in pairs(config or {}) do
		out[key] = value
	end

	local suppliedTemplate = config and config.DataTemplate
	if type(suppliedTemplate) == "table" and type(suppliedTemplate.Data) == "table" then
		out.DataVersion = suppliedTemplate.Version
		out.Template = deepCopy(suppliedTemplate.Data)
		out.DataTemplate = {
			Version = suppliedTemplate.Version,
			Data = deepCopy(suppliedTemplate.Data),
		}
	elseif type(config and config.Template) == "table" then
		local version = config.DataVersion
		if version == nil then
			version = 1
		end
		out.DataVersion = version
		out.Template = deepCopy(config.Template)
		out.DataTemplate = {
			Version = version,
			Data = deepCopy(config.Template),
		}
	else
		out.DataTemplate = {
			Version = out.DataVersion or 1,
			Data = deepCopy(out.Template or {}),
		}
	end

	if config and config.BufferStorage ~= nil and config.StorageMode == nil then
		out.StorageMode = if config.BufferStorage then "Buffer" else "Table"
	end

	return out
end

local function retryMemoryAsync(config, callback)
	local attempts = math.max(1, config.MemoryLockRetryAttempts or 4)
	local lastError = nil

	for attempt = 1, attempts do
		local ok, result = pcall(callback)
		if ok then
			return true, result
		end

		lastError = result

		if attempt < attempts then
			local delayTime = math.min(0.25 * (2 ^ (attempt - 1)), 2)
			delayTime += math.random() * 0.1
			task.wait(delayTime)
		end
	end

	return false, lastError
end

local function autoDecompressStorageBuffer(storedPayload, config)
	assert(typeof(storedPayload) == "buffer", "Stored payload must be a buffer")

	local codec = getCompression()
	local ok, rawPayload = pcall(codec.DecompressBuffer, storedPayload)
	if not ok then
		error("DataStore buffer failed to decompress: " .. tostring(rawPayload), 2)
	end

	if typeof(rawPayload) ~= "buffer" then
		error("Compression.DecompressBuffer returned a non-buffer value", 2)
	end

	if buffer.len(rawPayload) > config.MaxBufferBytes then
		error("DataStore decompressed payload exceeds MaxBufferBytes", 2)
	end

	return rawPayload
end

local function prepareStorage(data, version, config)
	local dataTemplate = makeDataTemplate(version, data)

	if config.StorageMode == "Buffer" then
		local storedPayload, stats = compressStorageTable(dataTemplate, config)

		return {
			Value = storedPayload,
			RawBuffer = nil,
			Bytes = stats.StoredBytes,
			RawBytes = stats.RawBytes,
			SavedBytes = stats.SavedBytes,
			SavingsPercent = stats.SavingsPercent,
			Compressed = stats.Compressed == true,
			CompressionMode = stats.Mode,
			WorkingBufferBytes = stats.WorkingBufferBytes,
			CompactedPayloadBytes = stats.CompactedPayloadBytes,
			UnusedWorkingBytesRemoved = stats.UnusedWorkingBytesRemoved or 0,
			SchemaEligible = stats.SchemaEligible == true,
			SchemaCandidateAvailable = stats.SchemaCandidateAvailable == true,
			SchemaSelected = stats.SchemaSelected == true,
			SchemaCandidateBytes = stats.SchemaCandidateBytes,
			SchemaCandidateMode = stats.SchemaCandidateMode,
			SchemaRawBytes = stats.SchemaRawBytes,
			SchemaFieldCount = stats.SchemaFieldCount,
			SchemaPresentFields = stats.SchemaPresentFields,
			SchemaDefaultFieldsOmitted = stats.SchemaDefaultFieldsOmitted,
			SchemaFingerprint = stats.SchemaFingerprint,
			SchemaWorkingBufferBytes = stats.SchemaWorkingBufferBytes,
			SchemaCompactedPayloadBytes = stats.SchemaCompactedPayloadBytes,
			SchemaUnusedWorkingBytesRemoved = stats.SchemaUnusedWorkingBytesRemoved or 0,
		}
	end

	validateSavable(dataTemplate, "DataTemplate", nil, 0, nil, config)

	return {
		Value = deepCopy(dataTemplate),
		RawBuffer = nil,
		Bytes = nil,
		RawBytes = nil,
		SavedBytes = 0,
		SavingsPercent = 0,
		Compressed = false,
		CompressionMode = "None",
		WorkingBufferBytes = nil,
		CompactedPayloadBytes = nil,
		UnusedWorkingBytesRemoved = 0,
		SchemaEligible = false,
		SchemaCandidateAvailable = false,
		SchemaSelected = false,
		SchemaCandidateBytes = nil,
		SchemaCandidateMode = nil,
		SchemaRawBytes = nil,
		SchemaFieldCount = nil,
		SchemaPresentFields = nil,
		SchemaDefaultFieldsOmitted = nil,
		SchemaFingerprint = nil,
		SchemaWorkingBufferBytes = nil,
		SchemaCompactedPayloadBytes = nil,
		SchemaUnusedWorkingBytesRemoved = 0,
	}
end

local function decodeLegacyRecord(record, config)
	local format = record[LEGACY_FORMAT_TAG]
	if format ~= LEGACY_FORMAT_V151 and format ~= LEGACY_FORMAT_V150 and format ~= LEGACY_FORMAT_V1 then
		return nil
	end

	local data
	local savedVersion = config.DataVersion or 1

	if type(record.Meta) == "table" and type(record.Meta.DataVersion) == "number" then
		savedVersion = record.Meta.DataVersion
	end

	if record.Encoding == BUFFER_ENCODING and typeof(record.Payload) == "buffer" then
		local rawPayload
		if format == LEGACY_FORMAT_V151 and record.PayloadCompressed == true then
			rawPayload = autoDecompressStorageBuffer(record.Payload, config)
		else
			rawPayload = cloneRawBuffer(record.Payload)
		end
		data = decodeBuffer(rawPayload, config)
	elseif type(record.Data) == "table" then
		data = deepCopy(record.Data)
	else
		data = deepCopy(config.Template)
	end

	return {
		Version = savedVersion,
		Data = data,
	}, "LegacyRecord"
end

local function decodeStoredValue(value, config)
	if value == nil then
		return deepCopy(config.DataTemplate), "New"
	end

	if typeof(value) == "buffer" then
		-- v1.8+: first try Compression v2.6.7's native table frame. This keeps
		-- table structure visible to the compressor and avoids double encoding.
		local compressedTable = tryDecodeCompressionTable(value, config)
		if compressedTable ~= nil then
			if type(compressedTable.Version) == "number" and type(compressedTable.Data) == "table" then
				return {
					Version = compressedTable.Version,
					Data = deepCopy(compressedTable.Data),
				}, "CompressionTableV267"
			end

			return {
				Version = config.DataVersion or 1,
				Data = deepCopy(compressedTable),
			}, "CompressionRawTableV267"
		end

		-- v1.6 and older: BufferV1/SDSB, optionally wrapped in CompressBuffer.
		-- Compression v2.6.7 DecompressBuffer intentionally passes unknown raw
		-- buffers through unchanged, so both old raw and compressed saves work.
		local rawPayload = autoDecompressStorageBuffer(value, config)

		-- v1.8.4 SchemaBuffer may be stored raw or wrapped by CompressBufferSmart.
		-- DecompressBuffer passes raw unknown frames through unchanged, so one path
		-- safely handles both forms.
		if SchemaCodec.isFrame(rawPayload) then
			local schemaTemplate = SchemaCodec.decode(rawPayload, config)
			if schemaTemplate ~= nil then
				return schemaTemplate, "SchemaBufferV1"
			end
		end

		local decoded = decodeBuffer(rawPayload, config)

		if type(decoded) ~= "table" then
			error("Decoded DataStore buffer must contain a table", 0)
		end

		if type(decoded.Version) == "number" and type(decoded.Data) == "table" then
			return {
				Version = decoded.Version,
				Data = deepCopy(decoded.Data),
			}, "DataTemplateBuffer"
		end

		return {
			Version = config.DataVersion or 1,
			Data = deepCopy(decoded),
		}, "LegacyRawBuffer"
	end

	if type(value) ~= "table" then
		error("Existing DataStore value has unsupported type " .. typeof(value), 0)
	end

	if value[LEGACY_FORMAT_TAG] ~= nil then
		local legacy, source = decodeLegacyRecord(value, config)
		if legacy ~= nil then
			return legacy, source
		end
	end

	if type(value.Version) == "number" and type(value.Data) == "table" then
		return {
			Version = value.Version,
			Data = deepCopy(value.Data),
		}, "DataTemplateTable"
	end

	return {
		Version = config.DataVersion or 1,
		Data = deepCopy(value),
	}, "LegacyRawTable"
end

local function applyMigrations(data, savedVersion, config)
	local targetVersion = config.DataVersion or 1

	if savedVersion > targetVersion and config.RejectFutureDataVersion then
		error(
			string.format(
				"Saved DataTemplate version %d is newer than configured version %d",
				savedVersion,
				targetVersion
			),
			0
		)
	end

	local currentVersion = savedVersion

	if currentVersion < targetVersion then
		for version = currentVersion + 1, targetVersion do
			if type(config.Migrations) == "table" then
				local migration = config.Migrations[version]
				if migration ~= nil then
					assert(type(migration) == "function", "Migration " .. tostring(version) .. " must be a function")
					local migrated = migration(data, version - 1, version)
					if migrated ~= nil then
						assert(type(migrated) == "table", "Migration must return a table or nil")
						data = migrated
					end
				end
			end

			currentVersion = version
		end
	end

	return data, targetVersion
end

function Profile:_deactivate(reason)
	if not self._active then
		return
	end

	self._active = false
	self._releaseReason = reason or "Released"
	self.Store._profiles[self.UserId] = nil

	self.Released:Fire(self._releaseReason)
	self.Store.ProfileReleased:Fire(self, self._releaseReason)

	self.Changed:Destroy()
	self.Saved:Destroy()
	self.Released:Destroy()
end

function Profile:_markChanged()
	self._revision += 1
	self._dirty = true
end

function Profile:IsActive()
	return self._active
end

function Profile:IsDirty()
	return self._dirty
end

function Profile:Get(key)
	return self.Data[key]
end

function Profile:GetDataCopy()
	return deepCopy(self.Data)
end

function Profile:GetDataTemplate()
	return makeDataTemplate(self.Version, self.Data)
end

function Profile:GetBuffer()
	assert(self._active, "Cannot encode an inactive profile")
	return encodeBuffer(self:GetDataTemplate(), self.Store.Config)
end

Profile.ToBuffer = Profile.GetBuffer

function Profile:GetStorageInfo()
	local rawBytes = self._lastRawBufferBytes
	local storedBytes = self._lastBufferBytes
	local savedBytes = 0

	if type(rawBytes) == "number" and type(storedBytes) == "number" then
		savedBytes = math.max(0, rawBytes - storedBytes)
	end

	local keyInfo = self.Store:GetKeyInfo(self.UserId)

	return {
		Mode = self.Store.Config.StorageMode,
		Version = self.Version,
		PlayerKey = keyInfo.Key,
		PlayerKeyBytes = keyInfo.KeyBytes,
		LegacyPlayerKeyBytes = keyInfo.LegacyKeyBytes,
		PlayerKeySavedBytes = keyInfo.SavedBytes,
		PlayerKeySavingsPercent = keyInfo.SavingsPercent,
		CompactPlayerKeys = keyInfo.Compact,
		KeyMigrationPending = self._legacyKeyToDelete ~= nil,
		LastBufferBytes = storedBytes,
		LastRawBufferBytes = rawBytes,
		LastCompressionSavedBytes = savedBytes,
		LastCompressionSavingsPercent = if type(rawBytes) == "number" and rawBytes > 0
			then savedBytes / rawBytes * 100
			else 0,
		LastBufferCompressed = self._lastBufferCompressed == true,
		LastCompressionMode = self._lastCompressionMode,
		BufferUtilEnabled = self.Store.Config.BufferUtilEnabled == true,
		BufferUtilVersion = if self.Store.Config.BufferUtilEnabled then DataStore.BufferUtilVersion() else "Disabled",
		LastWorkingBufferBytes = self._lastWorkingBufferBytes,
		LastCompactedPayloadBytes = self._lastCompactedPayloadBytes,
		LastUnusedWorkingBytesRemoved = self._lastUnusedWorkingBytesRemoved or 0,
		SchemaBufferEnabled = self.Store.Config.SchemaBufferEnabled == true,
		SchemaFormatVersion = SchemaCodec.VERSION,
		SchemaEligible = self.Store.Config._SchemaCurrent ~= nil,
		SchemaCandidateAvailable = self._lastSchemaCandidateAvailable == true,
		SchemaSelected = self._lastSchemaSelected == true,
		LastSchemaCandidateBytes = self._lastSchemaCandidateBytes,
		LastSchemaCandidateMode = self._lastSchemaCandidateMode,
		LastSchemaRawBytes = self._lastSchemaRawBytes,
		SchemaFieldCount = self._lastSchemaFieldCount or (self.Store.Config._SchemaCurrent and self.Store.Config._SchemaCurrent.FieldCount or nil),
		LastSchemaPresentFields = self._lastSchemaPresentFields,
		LastSchemaDefaultFieldsOmitted = self._lastSchemaDefaultFieldsOmitted,
		SchemaFingerprint = self._lastSchemaFingerprint or (self.Store.Config._SchemaCurrent and self.Store.Config._SchemaCurrent.Fingerprint or nil),
		LastSchemaWorkingBufferBytes = self._lastSchemaWorkingBufferBytes,
		LastSchemaCompactedPayloadBytes = self._lastSchemaCompactedPayloadBytes,
		LastSchemaUnusedWorkingBytesRemoved = self._lastSchemaUnusedWorkingBytesRemoved or 0,
		CompressionEnabled = self.Store.Config.CompressionEnabled,
		CompressionVersion = DataStore.CompressionVersion(),
		StorageFormatVersion = STORAGE_FORMAT_VERSION,
		DataStoreValueContainsOnlyDataTemplate = true,
		SessionLockStorage = if self.Store.Config.SessionLocking then "MemoryStore/CompactBufferV1" else "Disabled",
		SessionLockFormatVersion = SESSION_FORMAT_VERSION,
		SessionCompressionEnabled = self.Store.Config.SessionCompressionEnabled == true,
		SessionStoreDiagnostics = self.Store.Config.SessionStoreDiagnostics == true,
		LastSessionLockBytes = self._lastSessionLockBytes,
		LastSessionRawBytes = self._lastSessionRawBytes,
		LastSessionCompressed = self._lastSessionCompressed == true,
		LastSessionCompressionMode = self._lastSessionCompressionMode,
		LastSessionWorkingBufferBytes = self._lastSessionWorkingBufferBytes,
		LastSessionCompactedPayloadBytes = self._lastSessionCompactedPayloadBytes,
		LastSessionUnusedWorkingBytesRemoved = self._lastSessionUnusedWorkingBytesRemoved or 0,
		Dirty = self._dirty,
		Revision = self._revision,
		LastSavedRevision = self._lastSavedRevision,
		LastSaveClock = self._lastSave,
	}
end

function Profile:MarkDirty()
	assert(self._active, "Cannot modify an inactive profile")
	self:_markChanged()
end

function Profile:Set(key, value)
	assert(self._active, "Cannot modify an inactive profile")

	local oldValue = self.Data[key]
	self.Data[key] = value

	local ok, err = pcall(validateSavable, self.Data, "Data", nil, 0, nil, self.Store.Config)
	if not ok then
		self.Data[key] = oldValue
		error(err, 2)
	end

	self:_markChanged()
	self.Changed:Fire(key, value, oldValue)
	return value
end

function Profile:Update(key, callback)
	assert(self._active, "Cannot modify an inactive profile")
	assert(type(callback) == "function", "Profile:Update expects a function")

	local backup = deepCopy(self.Data)
	local oldValue = self.Data[key]
	local okCallback, newValue = pcall(callback, oldValue)

	if not okCallback then
		self.Data = backup
		error(newValue, 2)
	end

	self.Data[key] = newValue

	local ok, err = pcall(validateSavable, self.Data, "Data", nil, 0, nil, self.Store.Config)
	if not ok then
		self.Data = backup
		error(err, 2)
	end

	self:_markChanged()
	self.Changed:Fire(key, newValue, oldValue)
	return newValue
end

function Profile:Increment(key, amount)
	amount = amount or 1
	assert(type(amount) == "number" and isFiniteNumber(amount), "Profile:Increment amount must be a finite number")

	return self:Update(key, function(value)
		value = value or 0
		assert(type(value) == "number" and isFiniteNumber(value), "Profile:Increment target must be a finite number")
		return value + amount
	end)
end

function Profile:Overwrite(data)
	assert(self._active, "Cannot modify an inactive profile")
	assert(type(data) == "table", "Profile:Overwrite expects a table")

	validateSavable(data, "Data", nil, 0, nil, self.Store.Config)

	local oldData = self.Data
	self.Data = deepCopy(data)

	self:_markChanged()
	self.Changed:Fire(nil, self.Data, oldData)
	return self.Data
end

function Profile:Reconcile()
	assert(self._active, "Cannot reconcile an inactive profile")

	local before = deepCopy(self.Data)
	reconcile(self.Data, self.Store.Config.Template)
	validateSavable(self.Data, "Data", nil, 0, nil, self.Store.Config)

	self:_markChanged()
	self.Changed:Fire(nil, self.Data, before)
	return self.Data
end

function Profile:_waitForOperation()
	while self._saving do
		if not self._active then
			return false
		end
		task.wait()
	end

	return self._active
end

function Profile:_snapshotForSave()
	validateSavable(self.Data, "Data", nil, 0, nil, self.Store.Config)

	local snapshot = deepCopy(self.Data)
	local prepared = prepareStorage(snapshot, self.Version, self.Store.Config)

	return snapshot, prepared, self._revision
end

local function guidHex(value)
	if type(value) ~= "string" then
		return nil
	end

	local compact = string.gsub(value, "-", "")
	if #compact ~= 32 or string.find(compact, "[^0-9a-fA-F]") ~= nil then
		return nil
	end

	return string.lower(compact)
end

local function writeGuidOrString(writer, value)
	local compact = guidHex(value)
	if compact == nil then
		writer:VarUInt(#value)
		writer:RawString(value)
		return false
	end

	for i = 1, 32, 2 do
		local byte = tonumber(string.sub(compact, i, i + 1), 16)
		writer:U8(byte)
	end
	return true
end

local function readGuid(reader)
	local parts = table.create(16)
	for i = 1, 16 do
		parts[i] = string.format("%02x", reader:U8())
	end
	local compact = table.concat(parts)
	return string.sub(compact, 1, 8)
		.. "-" .. string.sub(compact, 9, 12)
		.. "-" .. string.sub(compact, 13, 16)
		.. "-" .. string.sub(compact, 17, 20)
		.. "-" .. string.sub(compact, 21, 32)
end

local function readGuidOrString(reader, isGuid)
	if isGuid then
		return readGuid(reader)
	end
	return reader:RawString(reader:VarUInt())
end

local function sessionIdsEqual(a, b)
	if a == b then
		return true
	end
	local ah = guidHex(a)
	local bh = guidHex(b)
	return ah ~= nil and bh ~= nil and ah == bh
end

local function makeSessionRaw(session, config)
	local id = assert(session.Id, "Session lock requires Id")
	local released = session.Released == true
	local diagnostics = not released and config.SessionStoreDiagnostics == true
	local idGuid = guidHex(id) ~= nil
	local jobId = diagnostics and tostring(session.JobId or "") or ""
	local jobGuid = diagnostics and guidHex(jobId) ~= nil

	local flags = 0
	if released then flags = bit32.bor(flags, SESSION_FLAG_RELEASED) end
	if idGuid then flags = bit32.bor(flags, SESSION_FLAG_ID_GUID) end
	if jobGuid then flags = bit32.bor(flags, SESSION_FLAG_JOB_GUID) end
	if diagnostics then flags = bit32.bor(flags, SESSION_FLAG_DIAGNOSTICS) end

	local writer = Writer.new(config.BufferWriterInitialCapacity or 32)
	writer:U8(SESSION_MAGIC)
	writer:U8(SESSION_FORMAT_VERSION)
	writer:U8(flags)
	writeGuidOrString(writer, id)

	if diagnostics then
		writeGuidOrString(writer, jobId)
		writer:VarUInt(session.PlaceId or 0)
		writer:VarUInt(session.TouchedAt or os.time())
	end

	local raw = writer:Finish()
	return raw, writer:GetCompactionInfo()
end

local function decodeSessionRaw(raw)
	assert(typeof(raw) == "buffer", "Session lock decode expects buffer")
	local reader = Reader.new(raw)
	if reader.Length < 3 then
		error("Session lock buffer is too small", 2)
	end
	if reader:U8() ~= SESSION_MAGIC then
		error("Session lock buffer has invalid magic", 2)
	end

	local version = reader:U8()
	if version ~= SESSION_FORMAT_VERSION then
		error("Unsupported session lock format version " .. tostring(version), 2)
	end

	local flags = reader:U8()
	local released = bit32.band(flags, SESSION_FLAG_RELEASED) ~= 0
	local idGuid = bit32.band(flags, SESSION_FLAG_ID_GUID) ~= 0
	local diagnostics = bit32.band(flags, SESSION_FLAG_DIAGNOSTICS) ~= 0
	local jobGuid = bit32.band(flags, SESSION_FLAG_JOB_GUID) ~= 0

	local session = {
		Id = readGuidOrString(reader, idGuid),
	}

	if released then
		session.Released = true
	elseif diagnostics then
		session.JobId = readGuidOrString(reader, jobGuid)
		session.PlaceId = reader:VarUInt()
		session.TouchedAt = reader:VarUInt()
	end

	if reader.Position ~= reader.Length then
		error("Session lock buffer contains trailing bytes", 2)
	end

	return session
end

local function encodeSessionLock(session, config)
	local raw, rawCompactInfo = makeSessionRaw(session, config)
	local rawBytes = buffer.len(raw)
	local stored = raw
	local compressed = false
	local mode = "CompactRaw"

	if config.SessionCompressionEnabled then
		local codec = getCompression()
		local ok, packed, didCompress = pcall(codec.CompressBufferSmart, raw, compressionOptions(config))
		if ok and typeof(packed) == "buffer" then
			stored = packed
			compressed = didCompress == true
			if compressed then
				mode = "Compression/" .. (type(codec.BufferMode) == "function" and codec.BufferMode(stored) or "Buffer")
			end
		else
			debugWarn(config, "Session compression failed; using compact raw lock:", packed)
		end
	end

	local storedBytes = buffer.len(stored)
	return stored, {
		RawBytes = rawBytes,
		StoredBytes = storedBytes,
		SavedBytes = math.max(0, rawBytes - storedBytes),
		SavingsPercent = rawBytes > 0 and math.max(0, rawBytes - storedBytes) / rawBytes * 100 or 0,
		Compressed = compressed,
		Mode = mode,
		Format = SESSION_FORMAT_VERSION,
		WorkingBufferBytes = rawCompactInfo and rawCompactInfo.WorkingBytes or rawBytes,
		CompactedPayloadBytes = rawCompactInfo and rawCompactInfo.UsedBytes or rawBytes,
		UnusedWorkingBytesRemoved = rawCompactInfo and rawCompactInfo.RemovedBytes or 0,
	}
end

local function decodeSessionLock(value, config)
	if value == nil then
		return nil, "Empty"
	end

	-- v1.7.1 and older stored session locks as normal tables. Keep reading them
	-- so a live rollout does not break ownership between old and new servers.
	if type(value) == "table" then
		if type(value.Id) ~= "string" then
			return nil, "Legacy session lock is missing Id"
		end
		return deepCopy(value), "LegacyTable"
	end

	if typeof(value) ~= "buffer" then
		return nil, "Unsupported session lock type " .. typeof(value)
	end

	local codec = getCompression()
	local okDecompress, raw = pcall(codec.DecompressBuffer, value)
	if not okDecompress or typeof(raw) ~= "buffer" then
		return nil, "Session lock decompression failed: " .. tostring(raw)
	end

	local okDecode, session = pcall(decodeSessionRaw, raw)
	if not okDecode then
		return nil, tostring(session)
	end

	return session, "CompactBufferV1"
end

function DataStore:_lockKey(userId)
	return tostring(userId)
end

function DataStore:_makeLockValue(sessionId, released)
	return encodeSessionLock({
		Id = sessionId,
		JobId = game.JobId,
		PlaceId = game.PlaceId,
		TouchedAt = os.time(),
		Released = released == true,
	}, self.Config)
end

function DataStore:_acquireSessionLock(userId, sessionId, mode)
	if not self.Config.SessionLocking then
		return true, nil, nil
	end

	local key = self:_lockKey(userId)
	local claimed = false
	local observed = nil
	local writeStats = nil

	local ok, result = retryMemoryAsync(self.Config, function()
		return self._lockMap:UpdateAsync(key, function(current)
			local currentSession, decodeError = decodeSessionLock(current, self.Config)
			if current ~= nil and currentSession == nil then
				observed = { Corrupt = true, Error = decodeError }
			else
				observed = currentSession and deepCopy(currentSession) or nil
			end

			local available = current == nil
				or (currentSession ~= nil and currentSession.Released == true)
				or (currentSession ~= nil and sessionIdsEqual(currentSession.Id, sessionId))

			if available or mode == "Steal" then
				claimed = true
				local packed
				packed, writeStats = self:_makeLockValue(sessionId, false)
				return packed
			end

			claimed = false
			return nil
		end, self.Config.SessionLockTimeout)
	end)

	if not ok then
		return false, result, nil
	end

	local resultSession = decodeSessionLock(result, self.Config)
	if claimed and resultSession ~= nil and sessionIdsEqual(resultSession.Id, sessionId) then
		return true, nil, writeStats
	end

	return false, observed or result, nil
end

function DataStore:_refreshSessionLock(profile)
	if not self.Config.SessionLocking then
		return true
	end

	local key = self:_lockKey(profile.UserId)
	local refreshed = false
	local writeStats = nil

	local ok, result = retryMemoryAsync(self.Config, function()
		return self._lockMap:UpdateAsync(key, function(current)
			local currentSession = decodeSessionLock(current, self.Config)
			if currentSession ~= nil and sessionIdsEqual(currentSession.Id, profile.SessionId) then
				refreshed = true
				local packed
				packed, writeStats = self:_makeLockValue(profile.SessionId, false)
				return packed
			end

			refreshed = false
			return nil
		end, self.Config.SessionLockTimeout)
	end)

	if not ok then
		return false, result
	end

	local resultSession = decodeSessionLock(result, self.Config)
	if refreshed and resultSession ~= nil and sessionIdsEqual(resultSession.Id, profile.SessionId) then
		if writeStats then
			profile._lastSessionLockBytes = writeStats.StoredBytes
			profile._lastSessionRawBytes = writeStats.RawBytes
			profile._lastSessionCompressed = writeStats.Compressed == true
			profile._lastSessionCompressionMode = writeStats.Mode
			profile._lastSessionWorkingBufferBytes = writeStats.WorkingBufferBytes
			profile._lastSessionCompactedPayloadBytes = writeStats.CompactedPayloadBytes
			profile._lastSessionUnusedWorkingBytesRemoved = writeStats.UnusedWorkingBytesRemoved or 0
		end
		return true
	end

	return false, "SessionLost"
end

function DataStore:_releaseSessionLock(profile)
	if not self.Config.SessionLocking then
		return true
	end

	local key = self:_lockKey(profile.UserId)
	local released = false

	local ok, result = retryMemoryAsync(self.Config, function()
		return self._lockMap:UpdateAsync(key, function(current)
			local currentSession = decodeSessionLock(current, self.Config)
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

function Profile:SaveAsync()
	if not self._active then
		return false, "ProfileInactive"
	end

	if not self:_waitForOperation() then
		return false, "ProfileInactive"
	end

	self._saving = true

	local lockOk, lockError = self.Store:_refreshSessionLock(self)
	if not lockOk then
		self._saving = false
		self:_deactivate("SessionLost")
		self.Store.Issue:Fire("SessionLost", self, lockError)
		return false, "SessionLost"
	end

	local okSnapshot, snapshot, prepared, revision = pcall(function()
		local data, storage, currentRevision = self:_snapshotForSave()
		return data, storage, currentRevision
	end)

	if not okSnapshot then
		self._saving = false
		return false, snapshot
	end

	local ok, result = retryAsync(self.Store.Config, Enum.DataStoreRequestType.SetIncrementAsync, function()
		return self.Store._store:SetAsync(self.Key, prepared.Value)
	end)

	if not ok then
		self._saving = false
		debugWarn(self.Store.Config, "Save failed for", self.Key, result)
		self.Store.Issue:Fire("SaveFailed", self, result)
		return false, result
	end

	-- v1.8.4: only remove the old player key after the compact-key write succeeds.
	-- A failed cleanup is non-destructive; the compact copy is already durable and
	-- the old key is retried on a later save instead of risking data loss.
	if self._legacyKeyToDelete ~= nil then
		local legacyKey = self._legacyKeyToDelete
		local cleanupOk, cleanupError = retryAsync(self.Store.Config, Enum.DataStoreRequestType.SetIncrementAsync, function()
			return self.Store._store:RemoveAsync(legacyKey)
		end)
		if cleanupOk then
			self._legacyKeyToDelete = nil
			self.MetaData.KeyMigrated = true
		else
			debugWarn(self.Store.Config, "Legacy player-key cleanup failed for", legacyKey, cleanupError)
			self.Store.Issue:Fire("LegacyKeyCleanupFailed", self, legacyKey, cleanupError)
		end
	end

	self._lastSave = os.clock()
	self._lastBufferBytes = prepared.Bytes
	self._lastRawBufferBytes = prepared.RawBytes
	self._lastBufferCompressed = prepared.Compressed == true
	self._lastCompressionMode = prepared.CompressionMode
	self._lastWorkingBufferBytes = prepared.WorkingBufferBytes
	self._lastCompactedPayloadBytes = prepared.CompactedPayloadBytes
	self._lastUnusedWorkingBytesRemoved = prepared.UnusedWorkingBytesRemoved or 0
	self._lastSchemaEligible = prepared.SchemaEligible == true
	self._lastSchemaCandidateAvailable = prepared.SchemaCandidateAvailable == true
	self._lastSchemaSelected = prepared.SchemaSelected == true
	self._lastSchemaCandidateBytes = prepared.SchemaCandidateBytes
	self._lastSchemaCandidateMode = prepared.SchemaCandidateMode
	self._lastSchemaRawBytes = prepared.SchemaRawBytes
	self._lastSchemaFieldCount = prepared.SchemaFieldCount
	self._lastSchemaPresentFields = prepared.SchemaPresentFields
	self._lastSchemaDefaultFieldsOmitted = prepared.SchemaDefaultFieldsOmitted
	self._lastSchemaFingerprint = prepared.SchemaFingerprint
	self._lastSchemaWorkingBufferBytes = prepared.SchemaWorkingBufferBytes
	self._lastSchemaCompactedPayloadBytes = prepared.SchemaCompactedPayloadBytes
	self._lastSchemaUnusedWorkingBytesRemoved = prepared.SchemaUnusedWorkingBytesRemoved or 0
	self._lastSavedRevision = revision

	if self._revision == revision then
		self._dirty = false
	end

	self._saving = false
	self.Saved:Fire(self:GetStorageInfo())
	return true
end

function Profile:ReleaseAsync(reason)
	if not self._active then
		return true
	end

	if not self:_waitForOperation() then
		return true
	end

	local saved, saveError = self:SaveAsync()
	if not saved then
		return false, saveError
	end

	local releasedLock, releaseError = self.Store:_releaseSessionLock(self)
	if not releasedLock then
		debugWarn(self.Store.Config, "MemoryStore session lock release failed for", self.Key, releaseError)
	end

	self:_deactivate(reason or "Released")
	return true
end

function DataStore.new(config)
	assert(RunService:IsServer(), "DataStore can only be used from the server")
	assert(type(config) == "table", "DataStore.new expects a config table")
	assert(type(config.Name) == "string" and #config.Name > 0, "DataStore.new requires Config.Name")

	local merged = mergeConfig(config)

	assert(type(merged.DataTemplate) == "table", "Config.DataTemplate must be a table")
	assert(type(merged.DataTemplate.Data) == "table", "Config.DataTemplate.Data must be a table")
	assert(type(merged.DataVersion) == "number" and merged.DataVersion >= 0 and merged.DataVersion == math.floor(merged.DataVersion), "DataTemplate.Version must be a non-negative integer")
	assert(type(merged.KeyPrefix) == "string", "Config.KeyPrefix must be a string")
	assert(type(merged.CompactPlayerKeys) == "boolean", "Config.CompactPlayerKeys must be a boolean")
	assert(type(merged.CompactKeyPrefix) == "string", "Config.CompactKeyPrefix must be a string")
	assert(type(merged.MigrateLegacyPlayerKeys) == "boolean", "Config.MigrateLegacyPlayerKeys must be a boolean")
	assert(type(merged.DeleteLegacyPlayerKeys) == "boolean", "Config.DeleteLegacyPlayerKeys must be a boolean")
	assert(#merged.CompactKeyPrefix <= 16, "Config.CompactKeyPrefix must be at most 16 bytes")
	assert(merged.StorageMode == "Buffer" or merged.StorageMode == "Table", "Config.StorageMode must be Buffer or Table")
	assert(type(merged.CompressionEnabled) == "boolean", "Config.CompressionEnabled must be a boolean")
	assert(type(merged.BufferUtilEnabled) == "boolean", "Config.BufferUtilEnabled must be a boolean")
	assert(merged.BufferUtilEnabled or (merged.StorageMode == "Table" and not merged.SessionLocking), "BufferUtilEnabled=false is only valid with Table storage and SessionLocking=false")
	assert(type(merged.BufferWriterInitialCapacity) == "number" and merged.BufferWriterInitialCapacity >= 1 and merged.BufferWriterInitialCapacity == math.floor(merged.BufferWriterInitialCapacity), "Config.BufferWriterInitialCapacity must be a positive integer")
	assert(type(merged.SchemaBufferEnabled) == "boolean", "Config.SchemaBufferEnabled must be a boolean")
	assert(type(merged.SchemaBufferCompress) == "boolean", "Config.SchemaBufferCompress must be a boolean")
	assert(type(merged.SchemaFallbackToGeneric) == "boolean", "Config.SchemaFallbackToGeneric must be a boolean")
	assert(merged.SchemaHistory == nil or type(merged.SchemaHistory) == "table", "Config.SchemaHistory must be nil or a table keyed by DataTemplate version")
	assert(
		merged.CompressionTableStrategy == "Auto"
			or merged.CompressionTableStrategy == "Compact"
			or merged.CompressionTableStrategy == "Dynamic",
		"Config.CompressionTableStrategy is invalid"
	)
	assert(
		merged.CompressionStringStrategy == "Auto"
			or merged.CompressionStringStrategy == "Raw"
			or merged.CompressionStringStrategy == "LZ"
			or merged.CompressionStringStrategy == "ASCII7"
			or merged.CompressionStringStrategy == "LowASCII5"
			or merged.CompressionStringStrategy == "Identifier6"
			or merged.CompressionStringStrategy == "Numeric4",
		"Config.CompressionStringStrategy is invalid"
	)
	assert(
		merged.CompressionEntropyStrategy == "Auto"
			or merged.CompressionEntropyStrategy == "Huffman"
			or merged.CompressionEntropyStrategy == "None",
		"Config.CompressionEntropyStrategy is invalid"
	)
	assert(type(merged.CompressionCompareLegacyBuffer) == "boolean", "Config.CompressionCompareLegacyBuffer must be a boolean")
	assert(type(merged.CompressionMinBufferBytes) == "number" and merged.CompressionMinBufferBytes >= 0, "Config.CompressionMinBufferBytes must be >= 0")
	assert(type(merged.CompressionMinSavingsBytes) == "number" and merged.CompressionMinSavingsBytes >= 1, "Config.CompressionMinSavingsBytes must be >= 1")
	assert(
		merged.CompressionBufferStrategy == "Auto"
			or merged.CompressionBufferStrategy == "Raw"
			or merged.CompressionBufferStrategy == "LZ"
			or merged.CompressionBufferStrategy == "Sparse"
			or merged.CompressionBufferStrategy == "Nibble",
		"Config.CompressionBufferStrategy is invalid"
	)
	assert(type(merged.AutoSaveInterval) == "number" and merged.AutoSaveInterval >= 10, "Config.AutoSaveInterval must be at least 10 seconds")
	assert(type(merged.SessionLocking) == "boolean", "Config.SessionLocking must be a boolean")
	assert(type(merged.SessionCompressionEnabled) == "boolean", "Config.SessionCompressionEnabled must be a boolean")
	assert(type(merged.SessionStoreDiagnostics) == "boolean", "Config.SessionStoreDiagnostics must be a boolean")
	assert(type(merged.SessionLockTimeout) == "number" and merged.SessionLockTimeout >= merged.AutoSaveInterval * 2, "SessionLockTimeout must be at least 2x AutoSaveInterval")
	assert(type(merged.LoadTimeout) == "number" and merged.LoadTimeout > 0, "Config.LoadTimeout must be > 0")
	assert(type(merged.RetryAttempts) == "number" and merged.RetryAttempts >= 1, "Config.RetryAttempts must be >= 1")
	assert(type(merged.MaxBufferBytes) == "number" and merged.MaxBufferBytes > 0, "Config.MaxBufferBytes must be > 0")
	assert(type(merged.MaxDepth) == "number" and merged.MaxDepth >= 1, "Config.MaxDepth must be >= 1")
	assert(type(merged.MaxTableEntries) == "number" and merged.MaxTableEntries >= 1, "Config.MaxTableEntries must be >= 1")

	validateSavable(merged.DataTemplate, "DataTemplate", nil, 0, nil, merged)
	SchemaCodec.ensureConfig(merged)
	if merged.SchemaBufferEnabled and merged._SchemaCurrent == nil and merged.SchemaFallbackToGeneric ~= true then
		error("Config.DataTemplate is not eligible for SchemaBuffer: " .. tostring(merged._SchemaReason), 2)
	end

	-- Preload both codecs outside MemoryStore UpdateAsync callbacks. Those callbacks cannot yield.
	-- BufferUtil is also used by the compact session writer, so it must already be cached.
	if merged.BufferUtilEnabled then
		getBufferUtil()
	end
	if merged.SessionLocking or merged.StorageMode == "Buffer" then
		getCompression()
	end

	if merged.StorageMode == "Buffer" then
		local prepared = prepareStorage(merged.Template, merged.DataVersion, merged)
		local decodedTemplate = decodeStoredValue(prepared.Value, merged)
		assert(
			type(decodedTemplate) == "table"
				and type(decodedTemplate.Version) == "number"
				and type(decodedTemplate.Data) == "table",
			"DataTemplate v1.8.4 storage self-test failed"
		)
	end

	local robloxStore
	if merged.Scope ~= nil then
		robloxStore = DataStoreService:GetDataStore(config.Name, merged.Scope)
	else
		robloxStore = DataStoreService:GetDataStore(config.Name)
	end

	local lockName = "SDS16:" .. config.Name
	if merged.Scope ~= nil then
		lockName ..= ":" .. tostring(merged.Scope)
	end
	if #lockName > 120 then
		lockName = string.sub(lockName, 1, 120)
	end

	local self = setmetatable({
		Name = config.Name,
		Config = merged,
		_store = robloxStore,
		_lockMap = MemoryStoreService:GetHashMap(lockName),
		_profiles = {},
		_closed = false,
		_autosaveCursor = 1,

		ProfileLoaded = Signal.new(),
		ProfileReleased = Signal.new(),
		Issue = Signal.new(),
	}, DataStore)

	self._playerRemovingConnection = Players.PlayerRemoving:Connect(function(player)
		local profile = self._profiles[player.UserId]
		if profile then
			profile._releaseRequested = "PlayerRemoving"

			task.spawn(function()
				local ok, err = profile:ReleaseAsync("PlayerRemoving")
				if not ok and profile:IsActive() then
					debugWarn(merged, "PlayerRemoving release will be retried by autosave", profile.Key, err)
				end
			end)
		end
	end)

	if merged.AutoSave then
		task.spawn(function()
			self:_autoSaveLoop()
		end)
	end

	game:BindToClose(function()
		self:CloseAsync()
	end)

	return self
end

function DataStore:_legacyKey(userId)
	return self.Config.KeyPrefix .. tostring(userId)
end

function DataStore:_key(userId)
	if not self.Config.CompactPlayerKeys then
		return self:_legacyKey(userId)
	end
	return self.Config.CompactKeyPrefix .. encodeBase62UInt(userId)
end

function DataStore:GetKeyInfo(subject)
	local userId = resolveUserId(subject)
	local key = self:_key(userId)
	local legacyKey = self:_legacyKey(userId)
	local keyBytes = #key
	local legacyBytes = #legacyKey
	local savedBytes = math.max(0, legacyBytes - keyBytes)

	return {
		UserId = userId,
		Key = key,
		KeyBytes = keyBytes,
		LegacyKey = legacyKey,
		LegacyKeyBytes = legacyBytes,
		SavedBytes = savedBytes,
		SavingsPercent = legacyBytes > 0 and savedBytes / legacyBytes * 100 or 0,
		Compact = self.Config.CompactPlayerKeys == true,
	}
end

function DataStore:GetSchemaInfo()
	SchemaCodec.ensureConfig(self.Config)
	local schema = self.Config._SchemaCurrent
	if schema == nil then
		return {
			Enabled = self.Config.SchemaBufferEnabled == true,
			Eligible = false,
			Reason = self.Config._SchemaReason,
			FormatVersion = SchemaCodec.VERSION,
			DataVersion = self.Config.DataVersion,
		}
	end

	local fields = table.create(schema.FieldCount)
	for index, leaf in ipairs(schema.Leaves) do
		fields[index] = {
			Index = index,
			Path = leaf.PathText,
			Kind = leaf.Kind,
		}
	end

	return {
		Enabled = self.Config.SchemaBufferEnabled == true,
		Eligible = true,
		Reason = nil,
		FormatVersion = SchemaCodec.VERSION,
		DataVersion = schema.Version,
		Fingerprint = schema.Fingerprint,
		FieldCount = schema.FieldCount,
		BitmapBytes = schema.BitmapBytes,
		Fields = fields,
	}
end

function DataStore:_readStoredValue(userId)
	local primaryKey = self:_key(userId)
	local ok, result = retryAsync(self.Config, Enum.DataStoreRequestType.GetAsync, function()
		return self._store:GetAsync(primaryKey)
	end)
	if not ok then
		return false, result, primaryKey, "PrimaryKey"
	end

	if result ~= nil then
		return true, result, primaryKey, self.Config.CompactPlayerKeys and "CompactKey" or "LegacyKey"
	end

	if self.Config.CompactPlayerKeys and self.Config.MigrateLegacyPlayerKeys then
		local legacyKey = self:_legacyKey(userId)
		if legacyKey ~= primaryKey then
			local legacyOk, legacyResult = retryAsync(self.Config, Enum.DataStoreRequestType.GetAsync, function()
				return self._store:GetAsync(legacyKey)
			end)
			if not legacyOk then
				return false, legacyResult, legacyKey, "LegacyKey"
			end
			if legacyResult ~= nil then
				return true, legacyResult, legacyKey, "LegacyKey"
			end
		end
	end

	return true, nil, primaryKey, "New"
end

function DataStore:_autoSaveLoop()
	while not self._closed do
		local profiles = {}

		for _, profile in pairs(self._profiles) do
			if profile._active then
				profiles[#profiles + 1] = profile
			end
		end

		local count = #profiles

		if count == 0 then
			task.wait(1)
		else
			if self._autosaveCursor > count then
				self._autosaveCursor = 1
			end

			local profile = profiles[self._autosaveCursor]
			self._autosaveCursor += 1

			local spacing = math.max(0.5, self.Config.AutoSaveInterval / count)
			task.wait(spacing)

			if not self._closed and profile and profile._active then
				task.spawn(function()
					local ok, err

					if profile._releaseRequested then
						ok, err = profile:ReleaseAsync(profile._releaseRequested)
					else
						ok, err = profile:SaveAsync()
					end

					if not ok and err ~= "ProfileInactive" and err ~= "SessionLost" then
						self.Issue:Fire("AutoSaveFailed", profile, err)
					end
				end)
			end
		end
	end
end

function DataStore:GetProfile(subject)
	local userId = resolveUserId(subject)
	return self._profiles[userId]
end

function DataStore:OpenPlayerAsync(subject, options)
	assert(not self._closed, "DataStore is closed")

	options = options or {}

	local userId, player = resolveUserId(subject)

	local existing = self._profiles[userId]
	if existing and existing._active then
		return existing
	end

	local key = self:_key(userId)
	local sessionId = HttpService:GenerateGUID(false)
	local deadline = os.clock() + self.Config.LoadTimeout
	local lockMode = options.Locked or "Wait"

	assert(lockMode == "Wait" or lockMode == "Cancel" or lockMode == "Steal", "options.Locked must be Wait, Cancel, or Steal")

	while not self._closed do
		local lockOk, lockInfo, lockStats = self:_acquireSessionLock(userId, sessionId, lockMode)

		if lockOk then
			local okRead, stored, loadedKey, keySource = self:_readStoredValue(userId)

			if not okRead then
				local tempProfile = {
					UserId = userId,
					SessionId = sessionId,
				}
				self:_releaseSessionLock(tempProfile)
				self.Issue:Fire("LoadFailed", userId, stored)
				return nil, stored
			end

			local okDecode, dataTemplate, source = pcall(decodeStoredValue, stored, self.Config)
			if not okDecode then
				local tempProfile = {
					UserId = userId,
					SessionId = sessionId,
				}
				self:_releaseSessionLock(tempProfile)
				self.Issue:Fire("DecodeFailed", userId, dataTemplate)
				return nil, dataTemplate
			end

			local data = deepCopy(dataTemplate.Data)
			local version = dataTemplate.Version

			local okMigrate, migratedData, migratedVersion = pcall(applyMigrations, data, version, self.Config)
			if not okMigrate then
				local tempProfile = {
					UserId = userId,
					SessionId = sessionId,
				}
				self:_releaseSessionLock(tempProfile)
				self.Issue:Fire("MigrationFailed", userId, migratedData)
				return nil, migratedData
			end

			data = migratedData
			version = migratedVersion

			if self.Config.Reconcile then
				reconcile(data, self.Config.Template)
			end

			local okValidate, validationError = pcall(validateSavable, data, "Data", nil, 0, nil, self.Config)
			if not okValidate then
				local tempProfile = {
					UserId = userId,
					SessionId = sessionId,
				}
				self:_releaseSessionLock(tempProfile)
				self.Issue:Fire("InvalidLoadedData", userId, validationError)
				return nil, validationError
			end

			local profile = setmetatable({
				Store = self,
				UserId = userId,
				Player = player,
				Key = key,
				SessionId = sessionId,

				Version = version,
				Data = data,

				MetaData = {
					RuntimeOnly = true,
					LoadSource = source,
					KeySource = keySource,
					LoadedKey = loadedKey,
					StorageKey = key,
				},

				Changed = Signal.new(),
				Saved = Signal.new(),
				Released = Signal.new(),

				_active = true,
				_saving = false,
				_dirty = source ~= "New",
				_revision = 0,
				_lastSavedRevision = 0,
				_lastSave = os.clock(),
				_lastBufferBytes = nil,
				_lastRawBufferBytes = nil,
				_lastBufferCompressed = false,
				_lastCompressionMode = nil,
				_lastWorkingBufferBytes = nil,
				_lastCompactedPayloadBytes = nil,
				_lastUnusedWorkingBytesRemoved = 0,
				_lastSchemaEligible = self.Config._SchemaCurrent ~= nil,
				_lastSchemaCandidateAvailable = false,
				_lastSchemaSelected = false,
				_lastSchemaCandidateBytes = nil,
				_lastSchemaCandidateMode = nil,
				_lastSchemaRawBytes = nil,
				_lastSchemaFieldCount = self.Config._SchemaCurrent and self.Config._SchemaCurrent.FieldCount or nil,
				_lastSchemaPresentFields = nil,
				_lastSchemaDefaultFieldsOmitted = nil,
				_lastSchemaFingerprint = self.Config._SchemaCurrent and self.Config._SchemaCurrent.Fingerprint or nil,
				_lastSchemaWorkingBufferBytes = nil,
				_lastSchemaCompactedPayloadBytes = nil,
				_lastSchemaUnusedWorkingBytesRemoved = 0,
				_lastSessionLockBytes = lockStats and lockStats.StoredBytes or nil,
				_lastSessionRawBytes = lockStats and lockStats.RawBytes or nil,
				_lastSessionCompressed = lockStats and lockStats.Compressed == true or false,
				_lastSessionCompressionMode = lockStats and lockStats.Mode or nil,
				_lastSessionWorkingBufferBytes = lockStats and lockStats.WorkingBufferBytes or nil,
				_lastSessionCompactedPayloadBytes = lockStats and lockStats.CompactedPayloadBytes or nil,
				_lastSessionUnusedWorkingBytesRemoved = lockStats and lockStats.UnusedWorkingBytesRemoved or 0,
				_releaseRequested = nil,
				_legacyKeyToDelete = if keySource == "LegacyKey" and loadedKey ~= key and self.Config.DeleteLegacyPlayerKeys then loadedKey else nil,
			}, Profile)

			self._profiles[userId] = profile
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

DataStore.LoadPlayerAsync = DataStore.OpenPlayerAsync

function DataStore:ViewTemplateAsync(subject)
	local userId = resolveUserId(subject)
	local ok, result, _, keySource = self:_readStoredValue(userId)

	if not ok then
		return nil, result
	end

	if result == nil then
		return nil
	end

	local okDecode, dataTemplate, source = pcall(decodeStoredValue, result, self.Config)
	if not okDecode then
		self.Issue:Fire("ViewDecodeFailed", userId, dataTemplate)
		return nil, dataTemplate
	end

	return dataTemplate, source, keySource
end

function DataStore:ViewAsync(subject)
	local dataTemplate, sourceOrError, keySource = self:ViewTemplateAsync(subject)
	if dataTemplate == nil then
		return nil, sourceOrError
	end

	return deepCopy(dataTemplate.Data), dataTemplate.Version, sourceOrError, keySource
end

function DataStore:GetStoredBufferAsync(subject)
	local userId = resolveUserId(subject)
	local ok, result = self:_readStoredValue(userId)

	if not ok then
		return nil, result
	end

	if result == nil then
		return nil
	end

	local okDecode, dataTemplate = pcall(decodeStoredValue, result, self.Config)
	if not okDecode then
		return nil, dataTemplate
	end

	return encodeBuffer(dataTemplate, self.Config)
end

function DataStore:GetStoredPayloadAsync(subject)
	local userId = resolveUserId(subject)
	local ok, result, _, keySource = self:_readStoredValue(userId)

	if not ok then
		return nil, result
	end

	if typeof(result) == "buffer" then
		return cloneBuffer(result), "buffer", keySource
	end

	if type(result) == "table" then
		return deepCopy(result), "table", keySource
	end

	return result, typeof(result), keySource
end

function DataStore:GetSessionLockInfoAsync(subject)
	if not self.Config.SessionLocking then
		return nil, "SessionLockingDisabled"
	end

	local userId = resolveUserId(subject)
	local key = self:_lockKey(userId)
	local ok, result = retryMemoryAsync(self.Config, function()
		return self._lockMap:GetAsync(key)
	end)
	if not ok then
		return nil, result
	end

	local session, source = decodeSessionLock(result, self.Config)
	if result ~= nil and session == nil then
		return nil, source
	end
	return session, source, typeof(result) == "buffer" and buffer.len(result) or nil
end

function DataStore:SavePlayerAsync(subject)
	local profile = self:GetProfile(subject)
	if not profile then
		return false, "ProfileNotLoaded"
	end

	return profile:SaveAsync()
end

function DataStore:ReleasePlayerAsync(subject, reason)
	local profile = self:GetProfile(subject)
	if not profile then
		return true
	end

	return profile:ReleaseAsync(reason)
end

function DataStore:CloseAsync()
	if self._closed then
		return true
	end

	self._closed = true

	if self._playerRemovingConnection then
		self._playerRemovingConnection:Disconnect()
		self._playerRemovingConnection = nil
	end

	local profiles = {}

	for _, profile in pairs(self._profiles) do
		if profile._active then
			profiles[#profiles + 1] = profile
		end
	end

	local remaining = #profiles
	local failures = 0
	local deadline = os.clock() + self.Config.ShutdownTimeout

	for _, profile in ipairs(profiles) do
		task.spawn(function()
			profile._releaseRequested = "ServerClosing"

			local ok = profile:ReleaseAsync("ServerClosing")
			if not ok and profile:IsActive() then
				failures += 1
			end

			remaining -= 1
		end)
	end

	while remaining > 0 and os.clock() < deadline do
		task.wait(0.05)
	end

	if remaining > 0 then
		warn(string.format("[DataStore v%s] Shutdown timed out with %d profile operation(s) still pending", VERSION, remaining))
	elseif failures > 0 then
		warn(string.format("[DataStore v%s] Shutdown finished with %d profile release failure(s)", VERSION, failures))
	end

	return remaining == 0 and failures == 0
end

function DataStore.CompressDataTemplate(dataTemplate, options)
	assert(type(dataTemplate) == "table", "CompressDataTemplate expects a table")

	local config = table.clone(DEFAULTS)
	if type(options) == "table" then
		for key, value in pairs(options) do
			config[key] = value
		end
	end

	validateSavable(dataTemplate, "DataTemplate", nil, 0, nil, config)
	local codec = getCompression()
	return codec.CompressTablePacket(dataTemplate, tableCompressionOptions(config))
end

function DataStore.DecompressDataTemplate(dataBuffer, options)
	assert(typeof(dataBuffer) == "buffer", "DecompressDataTemplate expects a buffer")

	local config = table.clone(DEFAULTS)
	if type(options) == "table" then
		for key, value in pairs(options) do
			config[key] = value
		end
	end

	local decoded = tryDecodeCompressionTable(dataBuffer, config)
	if decoded == nil then
		error("DataStore could not decode Compression v2.6.7 DataTemplate buffer", 2)
	end
	return decoded
end

function DataStore.Encode(data, options)
	local config = table.clone(DEFAULTS)

	if type(options) == "table" then
		for key, value in pairs(options) do
			config[key] = value
		end
	end

	return encodeBuffer(data, config)
end

function DataStore.Decode(dataBuffer, options)
	local config = table.clone(DEFAULTS)

	if type(options) == "table" then
		for key, value in pairs(options) do
			config[key] = value
		end
	end

	return decodeBuffer(dataBuffer, config)
end

function DataStore.CompressStorageBuffer(dataBuffer, options)
	assert(typeof(dataBuffer) == "buffer", "CompressStorageBuffer expects a buffer")

	local config = table.clone(DEFAULTS)

	if type(options) == "table" then
		for key, value in pairs(options) do
			config[key] = value
		end
	end

	return compressStorageBuffer(dataBuffer, config)
end

function DataStore.DecompressStorageBuffer(dataBuffer, options)
	assert(typeof(dataBuffer) == "buffer", "DecompressStorageBuffer expects a buffer")

	local config = table.clone(DEFAULTS)

	if type(options) == "table" then
		for key, value in pairs(options) do
			config[key] = value
		end
	end

	return autoDecompressStorageBuffer(dataBuffer, config)
end

function DataStore.CompactBufferExact(dataBuffer, usedBytes)
	assert(typeof(dataBuffer) == "buffer", "CompactBufferExact expects a buffer")
	local actualUsed = usedBytes
	if actualUsed == nil then
		actualUsed = buffer.len(dataBuffer)
	end
	assert(type(actualUsed) == "number" and actualUsed >= 0 and actualUsed == math.floor(actualUsed), "CompactBufferExact usedBytes must be a non-negative integer")
	assert(actualUsed <= buffer.len(dataBuffer), "CompactBufferExact usedBytes exceeds buffer length")
	return getBufferUtil().compactBytes(dataBuffer, actualUsed)
end

function DataStore.EncodeUserIdKey(userId)
	assert(type(userId) == "number" and userId > 0 and userId <= MAX_SAFE_INTEGER and userId == math.floor(userId), "EncodeUserIdKey expects a positive safe integer")
	return encodeBase62UInt(userId)
end

function DataStore.DecodeUserIdKey(encoded)
	return decodeBase62UInt(encoded)
end

function DataStore.Version()
	return VERSION
end

function DataStore.FormatVersion()
	return STORAGE_FORMAT_VERSION
end

function DataStore.BufferUtilVersion()
	local util = getBufferUtil()
	return tostring(util.VERSION or "Unknown")
end

function DataStore.CompressionVersion()
	local codec = getCompression()
	return type(codec.Version) == "function" and codec.Version() or "Unknown"
end

DataStore.Profile = Profile
DataStore.Signal = Signal
DataStore.BufferEncoding = BUFFER_ENCODING
DataStore.SessionFormatVersion = SESSION_FORMAT_VERSION
DataStore.SchemaFormatVersion = SchemaCodec.VERSION

return DataStore
