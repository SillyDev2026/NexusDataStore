--!native
--!optimize 2

local DataStoreService = game:GetService("DataStoreService")
local MemoryStoreService = game:GetService("MemoryStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Compression = nil

local function getCompression()
	if Compression ~= nil then
		return Compression
	end

	local moduleScript = assert(
		script:WaitForChild("Compression", 10),
		"DataStore v1.7.1 requires a child ModuleScript named Compression v2.6.4"
	)

	local codec = require(moduleScript)
	assert(
		type(codec) == "table"
			and type(codec.Version) == "function"
			and codec.Version() == "2.6.4"
			and type(codec.CompressTablePacket) == "function"
			and type(codec.DecompressTable) == "function"
			and type(codec.CompressBuffer) == "function"
			and type(codec.DecompressBuffer) == "function",
		"DataStore v1.7.1 requires Compression v2.6.4 with table + buffer codecs"
	)

	Compression = codec
	return codec
end

local DataStore = {}
DataStore.__index = DataStore

local Profile = {}
Profile.__index = Profile

local Signal = {}
Signal.__index = Signal

local VERSION = "1.7.1"
local STORAGE_FORMAT_VERSION = 5
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

	RetryAttempts = 5,
	RetryDelay = 0.75,
	MaxRetryDelay = 8,

	ShutdownTimeout = 25,

	BudgetAware = true,
	BudgetWaitTimeout = 10,

	StorageMode = "Buffer",

	CompressionEnabled = true,

	-- v1.7 primary storage codec: Compression v2.6.4 adaptive table compression.
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

function Writer.new(capacity)
	capacity = math.max(64, capacity or 256)
	return setmetatable({
		Data = buffer.create(capacity),
		Capacity = capacity,
		Position = 0,
	}, Writer)
end

function Writer:Ensure(bytes)
	local needed = self.Position + bytes
	if needed <= self.Capacity then
		return
	end

	local newCapacity = self.Capacity
	while newCapacity < needed do
		newCapacity *= 2
	end

	local nextBuffer = buffer.create(newCapacity)
	if self.Position > 0 then
		buffer.copy(nextBuffer, 0, self.Data, 0, self.Position)
	end
	self.Data = nextBuffer
	self.Capacity = newCapacity
end

function Writer:U8(value)
	self:Ensure(1)
	buffer.writeu8(self.Data, self.Position, value)
	self.Position += 1
end

function Writer:U32(value)
	self:Ensure(4)
	buffer.writeu32(self.Data, self.Position, value)
	self.Position += 4
end

function Writer:F64(value)
	self:Ensure(8)
	buffer.writef64(self.Data, self.Position, value)
	self.Position += 8
end

function Writer:RawString(value)
	local length = #value
	self:Ensure(length)
	if length > 0 then
		buffer.writestring(self.Data, self.Position, value)
		self.Position += length
	end
end

function Writer:RawBuffer(value)
	local length = buffer.len(value)
	self:Ensure(length)
	if length > 0 then
		buffer.copy(self.Data, self.Position, value, 0, length)
		self.Position += length
	end
end

function Writer:VarUInt(value)
	assert(value >= 0 and value <= MAX_SAFE_INTEGER and isInteger(value), "VarUInt expects a non-negative safe integer")
	repeat
		local byte = value % 128
		value = math.floor(value / 128)
		if value > 0 then
			byte += 128
		end
		self:U8(byte)
	until value == 0
end

function Writer:VarInt(value)
	local zigzag
	if value >= 0 then
		zigzag = value * 2
	else
		zigzag = -value * 2 - 1
	end
	self:VarUInt(zigzag)
end

function Writer:Finish()
	local out = buffer.create(self.Position)
	if self.Position > 0 then
		buffer.copy(out, 0, self.Data, 0, self.Position)
	end
	return out
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

	local payloadWriter = Writer.new(256)
	writeValue(payloadWriter, value, 0, {}, { Entries = 0 }, codecConfig)
	local payload = payloadWriter:Finish()
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
	return out
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

	-- Keep a valid BufferV1 candidate so v1.7 can never be forced to store a
	-- larger native-table frame than the previous DataStore representation.
	local rawPayload = encodeBuffer(dataTemplate, config)
	local rawBytes = buffer.len(rawPayload)
	local bestPayload = rawPayload
	local bestBytes = rawBytes
	local bestMode = "LegacyRawBuffer"
	local bestCompressed = false

	if not config.CompressionEnabled then
		return bestPayload, {
			RawBytes = rawBytes,
			StoredBytes = bestBytes,
			SavedBytes = 0,
			SavingsPercent = 0,
			Mode = bestMode,
			Compressed = false,
		}
	end

	-- Candidate A: v1.6-compatible SDSB bytes compressed by v2.6.4's latest
	-- adaptive Buffer codec. This is retained as a byte-size safety net.
	if config.CompressionCompareLegacyBuffer ~= false then
		local legacyPayload, legacyCompressed, legacyStats = compressStorageBuffer(rawPayload, config)
		local legacyBytes = buffer.len(legacyPayload)
		if legacyBytes < bestBytes then
			bestPayload = legacyPayload
			bestBytes = legacyBytes
			bestMode = "LegacyBuffer/" .. tostring(legacyStats.Mode)
			bestCompressed = legacyCompressed == true
		end
	end

	-- Candidate B: v2.6.4 sees the real DataTemplate table before serialization,
	-- allowing Compact/Dynamic tables, mapped keys, string dictionaries,
	-- homogeneous/delta/RLE arrays, nested buffer codecs, and entropy coding.
	local codec = getCompression()
	local ok, packet = pcall(codec.CompressTablePacket, dataTemplate, tableCompressionOptions(config))
	if ok
		and type(packet) == "table"
		and typeof(packet.Data) == "buffer" then
		local nativeBytes = buffer.len(packet.Data)
		local nativeSavings = rawBytes - nativeBytes
		if nativeBytes <= config.MaxBufferBytes
			and nativeSavings >= config.CompressionMinSavingsBytes
			and nativeBytes < bestBytes then
			bestPayload = packet.Data
			bestBytes = nativeBytes
			bestMode = type(packet.Codec) == "string" and packet.Codec or "CompressionTable"
			bestCompressed = true
		end
	else
		debugWarn(config, "Compression v2.6.4 native table candidate failed; using the best BufferV1 candidate:", packet)
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
		-- v1.7+: first try Compression v2.6.4's native table frame. This keeps
		-- table structure visible to the compressor and avoids double encoding.
		local compressedTable = tryDecodeCompressionTable(value, config)
		if compressedTable ~= nil then
			if type(compressedTable.Version) == "number" and type(compressedTable.Data) == "table" then
				return {
					Version = compressedTable.Version,
					Data = deepCopy(compressedTable.Data),
				}, "CompressionTableV264"
			end

			return {
				Version = config.DataVersion or 1,
				Data = deepCopy(compressedTable),
			}, "CompressionRawTableV264"
		end

		-- v1.6 and older: BufferV1/SDSB, optionally wrapped in CompressBuffer.
		-- Compression v2.6.4 DecompressBuffer intentionally passes unknown raw
		-- buffers through unchanged, so both old raw and compressed saves work.
		local rawPayload = autoDecompressStorageBuffer(value, config)
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

	return {
		Mode = self.Store.Config.StorageMode,
		Version = self.Version,
		LastBufferBytes = storedBytes,
		LastRawBufferBytes = rawBytes,
		LastCompressionSavedBytes = savedBytes,
		LastCompressionSavingsPercent = if type(rawBytes) == "number" and rawBytes > 0
			then savedBytes / rawBytes * 100
			else 0,
		LastBufferCompressed = self._lastBufferCompressed == true,
		LastCompressionMode = self._lastCompressionMode,
		CompressionEnabled = self.Store.Config.CompressionEnabled,
		CompressionVersion = DataStore.CompressionVersion(),
		StorageFormatVersion = STORAGE_FORMAT_VERSION,
		DataStoreValueContainsOnlyDataTemplate = true,
		SessionLockStorage = if self.Store.Config.SessionLocking then "MemoryStore" else "Disabled",
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

function DataStore:_lockKey(userId)
	return tostring(userId)
end

function DataStore:_makeLockValue(sessionId)
	return {
		Id = sessionId,
		JobId = game.JobId,
		PlaceId = game.PlaceId,
		TouchedAt = os.time(),
	}
end

function DataStore:_acquireSessionLock(userId, sessionId, mode)
	if not self.Config.SessionLocking then
		return true, nil
	end

	local key = self:_lockKey(userId)
	local claimed = false
	local observed = nil

	local ok, result = retryMemoryAsync(self.Config, function()
		return self._lockMap:UpdateAsync(key, function(current)
			observed = if type(current) == "table" then deepCopy(current) else current

			local available = current == nil
				or (type(current) == "table" and current.Released == true)
				or (type(current) == "table" and current.Id == sessionId)

			if available or mode == "Steal" then
				claimed = true
				return self:_makeLockValue(sessionId)
			end

			claimed = false
			return nil
		end, self.Config.SessionLockTimeout)
	end)

	if not ok then
		return false, result
	end

	if claimed and type(result) == "table" and result.Id == sessionId then
		return true, nil
	end

	return false, observed or result
end

function DataStore:_refreshSessionLock(profile)
	if not self.Config.SessionLocking then
		return true
	end

	local key = self:_lockKey(profile.UserId)
	local refreshed = false

	local ok, result = retryMemoryAsync(self.Config, function()
		return self._lockMap:UpdateAsync(key, function(current)
			if type(current) == "table" and current.Id == profile.SessionId then
				refreshed = true
				return self:_makeLockValue(profile.SessionId)
			end

			refreshed = false
			return nil
		end, self.Config.SessionLockTimeout)
	end)

	if not ok then
		return false, result
	end

	if refreshed and type(result) == "table" and result.Id == profile.SessionId then
		return true
	end

	return false, "SessionLost"
end

function DataStore:_releaseSessionLock(profile)
	if not self.Config.SessionLocking then
		return true
	end

	local key = self:_lockKey(profile.UserId)

	local ok, result = retryMemoryAsync(self.Config, function()
		return self._lockMap:UpdateAsync(key, function(current)
			if type(current) == "table" and current.Id == profile.SessionId then
				return {
					Id = profile.SessionId,
					Released = true,
					ReleasedAt = os.time(),
				}
			end

			return nil
		end, 1)
	end)

	if not ok then
		return false, result
	end

	return true
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

	self._saving = false

	if not ok then
		debugWarn(self.Store.Config, "Save failed for", self.Key, result)
		self.Store.Issue:Fire("SaveFailed", self, result)
		return false, result
	end

	self._lastSave = os.clock()
	self._lastBufferBytes = prepared.Bytes
	self._lastRawBufferBytes = prepared.RawBytes
	self._lastBufferCompressed = prepared.Compressed == true
	self._lastCompressionMode = prepared.CompressionMode
	self._lastSavedRevision = revision

	if self._revision == revision then
		self._dirty = false
	end

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
	assert(merged.StorageMode == "Buffer" or merged.StorageMode == "Table", "Config.StorageMode must be Buffer or Table")
	assert(type(merged.CompressionEnabled) == "boolean", "Config.CompressionEnabled must be a boolean")
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
	assert(type(merged.SessionLockTimeout) == "number" and merged.SessionLockTimeout >= merged.AutoSaveInterval * 2, "SessionLockTimeout must be at least 2x AutoSaveInterval")
	assert(type(merged.LoadTimeout) == "number" and merged.LoadTimeout > 0, "Config.LoadTimeout must be > 0")
	assert(type(merged.RetryAttempts) == "number" and merged.RetryAttempts >= 1, "Config.RetryAttempts must be >= 1")
	assert(type(merged.MaxBufferBytes) == "number" and merged.MaxBufferBytes > 0, "Config.MaxBufferBytes must be > 0")
	assert(type(merged.MaxDepth) == "number" and merged.MaxDepth >= 1, "Config.MaxDepth must be >= 1")
	assert(type(merged.MaxTableEntries) == "number" and merged.MaxTableEntries >= 1, "Config.MaxTableEntries must be >= 1")

	validateSavable(merged.DataTemplate, "DataTemplate", nil, 0, nil, merged)

	if merged.StorageMode == "Buffer" then
		local prepared = prepareStorage(merged.Template, merged.DataVersion, merged)
		local decodedTemplate = decodeStoredValue(prepared.Value, merged)
		assert(
			type(decodedTemplate) == "table"
				and type(decodedTemplate.Version) == "number"
				and type(decodedTemplate.Data) == "table",
			"DataTemplate Compression v2.6.4 self-test failed"
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

function DataStore:_key(userId)
	return self.Config.KeyPrefix .. tostring(userId)
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
		local lockOk, lockInfo = self:_acquireSessionLock(userId, sessionId, lockMode)

		if lockOk then
			local okRead, stored = retryAsync(self.Config, Enum.DataStoreRequestType.GetAsync, function()
				return self._store:GetAsync(key)
			end)

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
				_releaseRequested = nil,
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
	local key = self:_key(userId)

	local ok, result = retryAsync(self.Config, Enum.DataStoreRequestType.GetAsync, function()
		return self._store:GetAsync(key)
	end)

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

	return dataTemplate, source
end

function DataStore:ViewAsync(subject)
	local dataTemplate, sourceOrError = self:ViewTemplateAsync(subject)
	if dataTemplate == nil then
		return nil, sourceOrError
	end

	return deepCopy(dataTemplate.Data), dataTemplate.Version, sourceOrError
end

function DataStore:GetStoredBufferAsync(subject)
	local userId = resolveUserId(subject)
	local key = self:_key(userId)

	local ok, result = retryAsync(self.Config, Enum.DataStoreRequestType.GetAsync, function()
		return self._store:GetAsync(key)
	end)

	if not ok then
		return nil, result
	end

	if result == nil then
		return nil
	end

	if typeof(result) == "buffer" then
		local okRaw, rawPayload = pcall(autoDecompressStorageBuffer, result, self.Config)
		if not okRaw then
			return nil, rawPayload
		end
		return rawPayload
	end

	local okDecode, dataTemplate = pcall(decodeStoredValue, result, self.Config)
	if not okDecode then
		return nil, dataTemplate
	end

	return encodeBuffer(dataTemplate, self.Config)
end

function DataStore:GetStoredPayloadAsync(subject)
	local userId = resolveUserId(subject)
	local key = self:_key(userId)

	local ok, result = retryAsync(self.Config, Enum.DataStoreRequestType.GetAsync, function()
		return self._store:GetAsync(key)
	end)

	if not ok then
		return nil, result
	end

	if typeof(result) == "buffer" then
		return cloneBuffer(result), "buffer"
	end

	if type(result) == "table" then
		return deepCopy(result), "table"
	end

	return result, typeof(result)
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
		error("DataStore could not decode Compression v2.6.4 DataTemplate buffer", 2)
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

function DataStore.Version()
	return VERSION
end

function DataStore.FormatVersion()
	return STORAGE_FORMAT_VERSION
end

function DataStore.CompressionVersion()
	local codec = getCompression()
	return type(codec.Version) == "function" and codec.Version() or "Unknown"
end

DataStore.Profile = Profile
DataStore.Signal = Signal
DataStore.BufferEncoding = BUFFER_ENCODING

return DataStore
