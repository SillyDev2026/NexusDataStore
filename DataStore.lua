--!native
--!optimize 2
export type Path = string | number | {string | number}
export type SavePriority = "low" | "normal" | "high" | "critical"
export type Data = {[any]: any}

export type SchemaRule = {
	Type: string?,
	Required: boolean?,
	Integer: boolean?,
	Min: number?,
	Max: number?,
	MinLength: number?,
	MaxLength: number?,
	Bits: number?,
	Encoding: string?,
	Values: {any}?,
	Enum: {any}?,
	Children: {[string]: any}?,
	ArrayOf: any?,
	AllowUnknown: boolean?,
	OmitDefault: boolean?,
	Optional: boolean?,
	Validate: ((value: any, path: string) -> (boolean | string))?,
}

export type DataTemplate = {
	Version: number?,
	Data: Data,
	Strict: boolean?,
	Schema: {[string]: SchemaRule}?,
}

export type CompressionHistoryEntry = {
	Data: Data,
	Schema: {[string]: SchemaRule}?,
	Strict: boolean?,
}

export type StoreConfig = {
	Name: string,
	Scope: string?,
	Template: Data?,
	Schema: {[string]: SchemaRule}?,
	Strict: boolean?,
	DataTemplate: DataTemplate?,
	SchemaVersion: number?,
	Migrations: {[number]: ((data: Data, context: any) -> Data?)}?,
	Compression: boolean?,
	CompressionReports: boolean?,
	CompressionHistory: {[number]: CompressionHistoryEntry}?,
	AutoSave: boolean?,
	AutoSaveInterval: number?,
	LockTimeout: number?,
	HeartbeatInterval: number?,
	RetryAttempts: number?,
	RetryBaseDelay: number?,
	RetryMaxDelay: number?,
	BudgetAware: boolean?,
	BudgetWaitTimeout: number?,
	MinimumSaveInterval: number?,
	MaxDataNodes: number?,
	MaxDataBytes: number?,
	MaxJournalEntries: number?,
	MaxSnapshots: number?,
	LoadTimeout: number?,
	SaveTimeout: number?,
	EnableCrossServer: boolean?,
	CrossServerTopic: string?,
	DetectDirectChanges: boolean?,
	Debug: boolean?,
}

export type CompressionFieldReport = {
	Path: string,
	Bits: number,
	Encoding: any,
}

export type CompressionReport = {
	RawBytes: number,
	RawBits: number,
	EncodedBytes: number,
	EncodedBits: number,
	PayloadBits: number,
	PayloadBytes: number,
	HeaderBytes: number,
	SavedBytes: number,
	SavedBits: number,
	Ratio: number,
	SavingsPercent: number,
	Fields: {CompressionFieldReport},
}

export type SessionObject = {
	Store: any,
	Player: Player,
	Key: string,
	Data: Data,
	Revision: number,
	SchemaVersion: number,
	SessionId: string,
	Active: boolean,
	Dirty: boolean,
	IsActive: (self: any) -> boolean,
	Get: (self: any, path: Path) -> any,
	Set: (self: any, path: Path, value: any) -> (boolean, string?),
	Increment: (self: any, path: Path, amount: number?) -> (boolean, string?),
	Transaction: (self: any, callback: (transaction: any) -> any) -> (boolean, any),
	Save: (self: any, priority: SavePriority?) -> (boolean, string?),
	Release: (self: any) -> (boolean, string?),
}

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local MessagingService = game:GetService("MessagingService")
local RunService = game:GetService("RunService")

local NexusDataStore = {}
NexusDataStore.__index = NexusDataStore
NexusDataStore.Version = "6.2.1"

local Session = {}
Session.__index = Session

local Transaction = {}
Transaction.__index = Transaction

local Signal = {}
Signal.__index = Signal

local Writer = {}
Writer.__index = Writer

local Reader = {}
Reader.__index = Reader

local MAGIC = 0x4E445336
local FORMAT = 61

local TAG_NIL = 0
local TAG_FALSE = 1
local TAG_TRUE = 2
local TAG_NUMBER = 3
local TAG_STRING = 4
local TAG_ARRAY = 5
local TAG_MAP = 6

local PRIORITIES = {
	low = 10,
	normal = 50,
	high = 80,
	critical = 100,
}

local function now()
	return os.clock()
end

local function clone(value, seen)
	if typeof(value) ~= "table" then
		return value
	end

	seen = seen or {}

	if seen[value] then
		error("Circular references are not supported")
	end

	seen[value] = true

	local result = {}

	for key, child in pairs(value) do
		result[clone(key, seen)] = clone(child, seen)
	end

	seen[value] = nil

	return result
end

local function deepEqual(a, b, seen)
	if a == b then
		return true
	end

	if typeof(a) ~= typeof(b) then
		return false
	end

	if typeof(a) ~= "table" then
		return false
	end

	seen = seen or {}
	seen[a] = seen[a] or {}

	if seen[a][b] then
		return true
	end

	seen[a][b] = true

	for key, value in pairs(a) do
		if not deepEqual(value, b[key], seen) then
			return false
		end
	end

	for key, value in pairs(b) do
		if not deepEqual(a[key], value, seen) then
			return false
		end
	end

	return true
end

local function finiteNumber(value)
	return typeof(value) == "number"
		and value == value
		and value ~= math.huge
		and value ~= -math.huge
end

local function normalizePath(path)
	if typeof(path) == "string" or typeof(path) == "number" then
		return {path}
	end

	assert(typeof(path) == "table" and #path > 0, "Path must be a string, number, or non-empty array")

	local result = table.create(#path)

	for index, key in ipairs(path) do
		assert(
			typeof(key) == "string" or typeof(key) == "number",
			"Path components must be strings or numbers"
		)

		result[index] = key
	end

	return result
end

local function pathToString(path)
	local parts = normalizePath(path)
	local output = table.create(#parts)

	for index, key in ipairs(parts) do
		output[index] = tostring(key)
	end

	return table.concat(output, ".")
end

local function getAt(data, path)
	local current = data

	for _, key in ipairs(normalizePath(path)) do
		if typeof(current) ~= "table" then
			return nil
		end

		current = current[key]

		if current == nil then
			return nil
		end
	end

	return current
end

local function setAt(data, path, value)
	local parts = normalizePath(path)
	local current = data

	for index = 1, #parts - 1 do
		local key = parts[index]

		if typeof(current[key]) ~= "table" then
			current[key] = {}
		end

		current = current[key]
	end

	current[parts[#parts]] = value
end

local function deleteAt(data, path)
	local parts = normalizePath(path)
	local current = data

	for index = 1, #parts - 1 do
		current = current[parts[index]]

		if typeof(current) ~= "table" then
			return false
		end
	end

	local key = parts[#parts]

	if current[key] == nil then
		return false
	end

	current[key] = nil

	return true
end

local function countTable(value)
	local count = 0

	if typeof(value) == "table" then
		for _ in pairs(value) do
			count += 1
		end
	end

	return count
end

local function isDenseArray(value)
	if typeof(value) ~= "table" then
		return false, 0
	end

	local maxIndex = 0

	for key in pairs(value) do
		if typeof(key) ~= "number"
			or key < 1
			or key % 1 ~= 0 then
			return false, 0
		end

		maxIndex = math.max(maxIndex, key)
	end

	for index = 1, maxIndex do
		if rawget(value, index) == nil then
			return false, 0
		end
	end

	return true, maxIndex
end

local function sortedKeys(value)
	local keys = {}

	for key in pairs(value) do
		table.insert(keys, key)
	end

	table.sort(keys, function(a, b)
		local typeA = typeof(a)
		local typeB = typeof(b)

		if typeA == typeB then
			return a < b
		end

		return typeA < typeB
	end)

	return keys
end

local function reconcile(data, template)
	if typeof(template) ~= "table" then
		return data
	end

	if typeof(data) ~= "table" then
		data = {}
	end

	for key, defaultValue in pairs(template) do
		if data[key] == nil then
			data[key] = clone(defaultValue)
		elseif typeof(defaultValue) == "table" then
			data[key] = reconcile(data[key], defaultValue)
		end
	end

	return data
end

local function countNodes(value, seen)
	if typeof(value) ~= "table" then
		return 1
	end

	seen = seen or {}

	if seen[value] then
		return 0
	end

	seen[value] = true

	local count = 1

	for key, child in pairs(value) do
		count += countNodes(key, seen)
		count += countNodes(child, seen)
	end

	return count
end

local function diffTables(before, after, path, output)
	output = output or {}
	path = path or {}

	if deepEqual(before, after) then
		return output
	end

	if typeof(before) ~= "table" or typeof(after) ~= "table" then
		table.insert(output, {
			Path = clone(path),
			Before = clone(before),
			After = clone(after),
			Operation = "Replace",
		})

		return output
	end

	local keys = {}

	for key in pairs(before) do
		keys[key] = true
	end

	for key in pairs(after) do
		keys[key] = true
	end

	for key in pairs(keys) do
		local childPath = clone(path)
		table.insert(childPath, key)

		if before[key] == nil then
			table.insert(output, {
				Path = childPath,
				Before = nil,
				After = clone(after[key]),
				Operation = "Add",
			})
		elseif after[key] == nil then
			table.insert(output, {
				Path = childPath,
				Before = clone(before[key]),
				After = nil,
				Operation = "Remove",
			})
		else
			diffTables(before[key], after[key], childPath, output)
		end
	end

	return output
end

local function checksumBuffer(value)
	local hash = 2166136261

	for index = 0, buffer.len(value) - 1 do
		hash = bit32.bxor(hash, buffer.readu8(value, index))
		hash = (hash * 16777619) % 4294967296
	end

	return hash
end

function Writer.new(capacity)
	return setmetatable({
		Buffer = buffer.create(capacity or 4096),
		Position = 0,
	}, Writer)
end

function Writer:Ensure(amount)
	local needed = self.Position + amount

	if needed <= buffer.len(self.Buffer) then
		return
	end

	local newSize = math.max(
		needed,
		math.max(64, buffer.len(self.Buffer) * 2)
	)

	local nextBuffer = buffer.create(newSize)

	buffer.copy(
		nextBuffer,
		0,
		self.Buffer,
		0,
		self.Position
	)

	self.Buffer = nextBuffer
end

function Writer:U8(value)
	self:Ensure(1)
	buffer.writeu8(self.Buffer, self.Position, value)
	self.Position += 1
end

function Writer:U16(value)
	self:Ensure(2)
	buffer.writeu16(self.Buffer, self.Position, value)
	self.Position += 2
end

function Writer:U32(value)
	self:Ensure(4)
	buffer.writeu32(self.Buffer, self.Position, value)
	self.Position += 4
end

function Writer:F64(value)
	self:Ensure(8)
	buffer.writef64(self.Buffer, self.Position, value)
	self.Position += 8
end

function Writer:String(value)
	self:Ensure(#value)
	buffer.writestring(
		self.Buffer,
		self.Position,
		value
	)
	self.Position += #value
end

function Writer:Finish()
	local result = buffer.create(self.Position)

	buffer.copy(
		result,
		0,
		self.Buffer,
		0,
		self.Position
	)

	return result
end

function Reader.new(value)
	return setmetatable({
		Buffer = value,
		Position = 0,
		Length = buffer.len(value),
	}, Reader)
end

function Reader:Need(amount)
	if self.Position + amount > self.Length then
		error("Unexpected end of buffer")
	end
end

function Reader:U8()
	self:Need(1)

	local value = buffer.readu8(
		self.Buffer,
		self.Position
	)

	self.Position += 1

	return value
end

function Reader:U16()
	self:Need(2)

	local value = buffer.readu16(
		self.Buffer,
		self.Position
	)

	self.Position += 2

	return value
end

function Reader:U32()
	self:Need(4)

	local value = buffer.readu32(
		self.Buffer,
		self.Position
	)

	self.Position += 4

	return value
end

function Reader:F64()
	self:Need(8)

	local value = buffer.readf64(
		self.Buffer,
		self.Position
	)

	self.Position += 8

	return value
end

function Reader:String(length)
	self:Need(length)

	local value = buffer.readstring(
		self.Buffer,
		self.Position,
		length
	)

	self.Position += length

	return value
end

local function encodeValue(writer, value)
	local kind = typeof(value)

	if value == nil then
		writer:U8(TAG_NIL)

		return
	end

	if kind == "boolean" then
		writer:U8(
			value
				and TAG_TRUE
				or TAG_FALSE
		)

		return
	end

	if kind == "number" then
		assert(
			finiteNumber(value),
			"Only finite numbers can be saved"
		)

		writer:U8(TAG_NUMBER)
		writer:F64(value)

		return
	end

	if kind == "string" then
		assert(
			utf8.len(value) ~= nil,
			"Strings must contain valid UTF-8"
		)

		writer:U8(TAG_STRING)
		writer:U32(#value)
		writer:String(value)

		return
	end

	if kind == "table" then
		local array, count = isDenseArray(value)

		if array then
			writer:U8(TAG_ARRAY)
			writer:U32(count)

			for index = 1, count do
				encodeValue(writer, value[index])
			end

			return
		end

		writer:U8(TAG_MAP)

		local keys = sortedKeys(value)

		writer:U32(#keys)

		for _, key in ipairs(keys) do
			local keyType = typeof(key)

			assert(
				keyType == "string"
					or keyType == "number",
				"Table keys must be strings or numbers"
			)

			encodeValue(writer, key)
			encodeValue(writer, value[key])
		end

		return
	end

	error(
		"Unsupported persistent value type: "
			.. kind
	)
end

local function decodeValue(reader)
	local tag = reader:U8()

	if tag == TAG_NIL then
		return nil
	end

	if tag == TAG_FALSE then
		return false
	end

	if tag == TAG_TRUE then
		return true
	end

	if tag == TAG_NUMBER then
		return reader:F64()
	end

	if tag == TAG_STRING then
		local length = reader:U32()

		return reader:String(length)
	end

	if tag == TAG_ARRAY then
		local count = reader:U32()
		local result = table.create(count)

		for index = 1, count do
			result[index] = decodeValue(reader)
		end

		return result
	end

	if tag == TAG_MAP then
		local count = reader:U32()
		local result = {}

		for _ = 1, count do
			local key = decodeValue(reader)
			local value = decodeValue(reader)

			result[key] = value
		end

		return result
	end

	error("Unknown NexusDataStore value tag")
end

local function encodeRecord(record)
	local payloadWriter = Writer.new(4096)

	encodeValue(
		payloadWriter,
		record
	)

	local payload = payloadWriter:Finish()
	local checksum = checksumBuffer(payload)

	local headerWriter = Writer.new(32)

	headerWriter:U32(MAGIC)
	headerWriter:U16(FORMAT)
	headerWriter:U32(buffer.len(payload))
	headerWriter:U32(checksum)

	local result = buffer.create(
		headerWriter.Position
			+ buffer.len(payload)
	)

	buffer.copy(
		result,
		0,
		headerWriter.Buffer,
		0,
		headerWriter.Position
	)

	buffer.copy(
		result,
		headerWriter.Position,
		payload,
		0,
		buffer.len(payload)
	)

	return result
end

local function decodeRecord(raw)
	if raw == nil then
		return nil
	end

	assert(
		typeof(raw) == "buffer",
		"Stored record is not a NexusDataStore buffer"
	)

	local reader = Reader.new(raw)

	assert(
		reader.Length >= 14,
		"Stored buffer is too small"
	)

	assert(
		reader:U32() == MAGIC,
		"Invalid NexusDataStore magic"
	)

	assert(
		reader:U16() == FORMAT,
		"Unsupported NexusDataStore format"
	)

	local payloadLength = reader:U32()
	local expectedChecksum = reader:U32()

	assert(
		payloadLength
			== reader.Length - reader.Position,
		"Invalid NexusDataStore payload length"
	)

	local payload = buffer.create(payloadLength)

	buffer.copy(
		payload,
		0,
		raw,
		reader.Position,
		payloadLength
	)

	assert(
		checksumBuffer(payload)
			== expectedChecksum,
		"NexusDataStore checksum mismatch"
	)

	local payloadReader = Reader.new(payload)
	local record = decodeValue(payloadReader)

	assert(
		payloadReader.Position
			== payloadReader.Length,
		"Trailing NexusDataStore payload"
	)

	return record
end

local function estimateEncodedBytes(value)
	local writer = Writer.new(1024)

	local ok = pcall(function()
		encodeValue(writer, value)
	end)

	if not ok then
		return math.huge
	end

	return writer.Position
end

local function errorText(value)
	return string.lower(tostring(value))
end

local function transientError(value)
	local message = errorText(value)

	return string.find(message, "thrott", 1, true)
		or string.find(message, "429", 1, true)
		or string.find(message, "timeout", 1, true)
		or string.find(message, "timed out", 1, true)
		or string.find(message, "502", 1, true)
		or string.find(message, "503", 1, true)
		or string.find(message, "504", 1, true)
end

function Signal.new()
	return setmetatable({
		Connections = {},
		Destroyed = false,
	}, Signal)
end

function Signal:Connect(callback)
	assert(
		typeof(callback) == "function",
		"Signal callback must be a function"
	)

	assert(
		not self.Destroyed,
		"Signal is destroyed"
	)

	local item = {
		Callback = callback,
		Connected = true,
	}

	table.insert(
		self.Connections,
		item
	)

	local connection = {
		Connected = true,
	}

	function connection:Disconnect()
		if not item.Connected then
			return
		end

		item.Connected = false
		connection.Connected = false
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
	if self.Destroyed then
		return
	end

	local arguments = table.pack(...)

	for index = #self.Connections, 1, -1 do
		local item = self.Connections[index]

		if not item.Connected then
			table.remove(
				self.Connections,
				index
			)
		else
			task.spawn(
				item.Callback,
				table.unpack(
					arguments,
					1,
					arguments.n
				)
			)
		end
	end
end

function Signal:Destroy()
	if self.Destroyed then
		return
	end

	self.Destroyed = true

	table.clear(
		self.Connections
	)
end

local Schema = {}

function Schema.Validate(value, rule, path, errors, strict)
	errors = errors or {}
	path = path or "$"

	if rule == nil then
		return errors
	end

	if value == nil then
		if rule.Required ~= false then
			table.insert(
				errors,
				path .. ": required value missing"
			)
		end

		return errors
	end

	local actualType = typeof(value)

	if rule.Type
		and actualType ~= rule.Type then
		table.insert(
			errors,
			("%s: expected %s, got %s"):format(
				path,
				rule.Type,
				actualType
			)
		)

		return errors
	end

	if actualType == "number" then
		if not finiteNumber(value) then
			table.insert(
				errors,
				path .. ": must be finite"
			)
		end

		if rule.Integer
			and value % 1 ~= 0 then
			table.insert(
				errors,
				path .. ": must be an integer"
			)
		end

		if rule.Min ~= nil
			and value < rule.Min then
			table.insert(
				errors,
				path .. ": below minimum"
			)
		end

		if rule.Max ~= nil
			and value > rule.Max then
			table.insert(
				errors,
				path .. ": above maximum"
			)
		end
	end

	if actualType == "string" then
		if rule.MinLength
			and #value < rule.MinLength then
			table.insert(
				errors,
				path .. ": below minimum length"
			)
		end

		if rule.MaxLength
			and #value > rule.MaxLength then
			table.insert(
				errors,
				path .. ": above maximum length"
			)
		end
	end

	if rule.Enum then
		local accepted = false

		for _, allowed in ipairs(rule.Enum) do
			if deepEqual(value, allowed) then
				accepted = true
				break
			end
		end

		if not accepted then
			table.insert(
				errors,
				path .. ": not in enum"
			)
		end
	end

	if actualType == "table" then
		if rule.ArrayOf then
			local array, count = isDenseArray(value)

			if not array then
				table.insert(
					errors,
					path .. ": expected dense array"
				)
			else
				for index = 1, count do
					Schema.Validate(
						value[index],
						rule.ArrayOf,
						path
							.. "["
							.. index
							.. "]",
						errors,
						strict
					)
				end
			end
		end

		if rule.Children then
			for key, childRule in pairs(rule.Children) do
				Schema.Validate(
					value[key],
					childRule,
					path
						.. "."
						.. tostring(key),
					errors,
					strict
				)
			end

			if strict
				or rule.AllowUnknown == false then
				for key in pairs(value) do
					if rule.Children[key] == nil then
						table.insert(
							errors,
							path
								.. "."
								.. tostring(key)
								.. ": unknown field"
						)
					end
				end
			end
		end
	end

	if rule.Validate then
		local ok, result = pcall(
			rule.Validate,
			value,
			path
		)

		if not ok then
			table.insert(
				errors,
				path
					.. ": validator error: "
					.. tostring(result)
			)
		elseif result == false then
			table.insert(
				errors,
				path .. ": validation failed"
			)
		elseif typeof(result) == "string" then
			table.insert(
				errors,
				path
					.. ": "
					.. result
			)
		end
	end

	return errors
end

local function validateData(
	data,
	schema,
	strict,
	maxNodes,
	maxBytes
)
	if typeof(data) ~= "table" then
		return false, "Data must be a table"
	end

	local errors = {}

	if schema then
		Schema.Validate(
			data,
			{
				Type = "table",
				Required = true,
				Children = schema,
			},
			"$",
			errors,
			strict
		)
	end

	local nodes = countNodes(data)

	if nodes > maxNodes then
		table.insert(
			errors,
			("Data node limit exceeded: %d > %d"):format(
				nodes,
				maxNodes
			)
		)
	end

	local bytes = estimateEncodedBytes(data)

	if bytes > maxBytes then
		table.insert(
			errors,
			("Encoded size limit exceeded: %d > %d"):format(
				bytes,
				maxBytes
			)
		)
	end

	if #errors > 0 then
		return false, table.concat(errors, "\n"), {
			Nodes = nodes,
			Bytes = bytes,
			Errors = errors,
		}
	end

	return true, nil, {
		Nodes = nodes,
		Bytes = bytes,
		Errors = {},
	}
end

local function makeSessionId()
	return HttpService:GenerateGUID(false)
end

local function makePlayerKey(player)
	return "Player_" .. tostring(player.UserId)
end

function Transaction.new(store, session)
	return setmetatable({
		Store = store,
		Session = session,
		Data = clone(session.Data),
		Original = clone(session.Data),
		Id = HttpService:GenerateGUID(false),
		StartedAt = now(),
		Closed = false,
	}, Transaction)
end

function Transaction:_Assert()
	assert(
		not self.Closed,
		"Transaction is closed"
	)

	assert(
		self.Session:IsActive(),
		"Session is inactive"
	)
end

function Transaction:Get(path)
	self:_Assert()

	return clone(
		getAt(
			self.Data,
			path
		)
	)
end

function Transaction:Set(path, value)
	self:_Assert()

	setAt(
		self.Data,
		path,
		clone(value)
	)

	return self
end

function Transaction:Delete(path)
	self:_Assert()

	deleteAt(
		self.Data,
		path
	)

	return self
end

function Transaction:Increment(path, amount)
	self:_Assert()

	amount = amount or 1

	assert(
		finiteNumber(amount),
		"Increment amount must be finite"
	)

	local current = getAt(
		self.Data,
		path
	)

	assert(
		finiteNumber(current),
		"Increment target must be a number"
	)

	setAt(
		self.Data,
		path,
		current + amount
	)

	return self
end

function Transaction:IncrementClamped(
	path,
	amount,
	minimum,
	maximum
)
	self:_Assert()

	local current = getAt(
		self.Data,
		path
	)

	assert(
		finiteNumber(current),
		"Increment target must be a number"
	)

	local nextValue = current + (amount or 1)

	if minimum ~= nil then
		nextValue = math.max(
			minimum,
			nextValue
		)
	end

	if maximum ~= nil then
		nextValue = math.min(
			maximum,
			nextValue
		)
	end

	setAt(
		self.Data,
		path,
		nextValue
	)

	return self
end

function Transaction:Insert(path, value)
	self:_Assert()

	local list = getAt(
		self.Data,
		path
	)

	assert(
		typeof(list) == "table",
		"Insert target must be a table"
	)

	table.insert(
		list,
		clone(value)
	)

	return self
end

function Transaction:RemoveAt(path, index)
	self:_Assert()

	local list = getAt(
		self.Data,
		path
	)

	assert(
		typeof(list) == "table",
		"RemoveAt target must be a table"
	)

	if index < 1
		or index > #list then
		return false, "INDEX_OUT_OF_RANGE"
	end

	table.remove(
		list,
		index
	)

	return true
end

function Transaction:Require(path, expected)
	self:_Assert()

	local current = getAt(
		self.Data,
		path
	)

	if typeof(expected) == "function" then
		local ok, result = pcall(
			expected,
			current
		)

		if not ok then
			error(result)
		end

		if not result then
			error("TRANSACTION_PRECONDITION_FAILED")
		end

		return current
	end

	if not deepEqual(
		current,
		expected
		) then
		error("TRANSACTION_PRECONDITION_FAILED")
	end

	return current
end

function Transaction:CompareAndSet(
	path,
	expected,
	value
)
	self:_Assert()

	if not deepEqual(
		getAt(self.Data, path),
		expected
		) then
		return false, "COMPARE_FAILED"
	end

	setAt(
		self.Data,
		path,
		clone(value)
	)

	return true
end

function Transaction:Savepoint()
	self:_Assert()

	return clone(self.Data)
end

function Transaction:RollbackTo(snapshot)
	self:_Assert()

	assert(
		typeof(snapshot) == "table",
		"Savepoint must be a table"
	)

	self.Data = clone(snapshot)

	return true
end

function Transaction:Diff()
	self:_Assert()

	return diffTables(
		self.Original,
		self.Data
	)
end

function Transaction:Validate()
	self:_Assert()

	return self.Store:_ValidateData(
		self.Data
	)
end

function Transaction:Commit()
	self:_Assert()

	self.Closed = true

	return true
end

function Transaction:Rollback()
	self:_Assert()

	self.Closed = true

	return true
end

function Session._NewV620(
	store,
	player,
	key,
	data,
	revision,
	schemaVersion,
	sessionId
)
	return setmetatable({
		Store = store,
		Player = player,
		Key = key,
		Data = data,
		Revision = revision,
		SchemaVersion = schemaVersion,
		SessionId = sessionId,
		Active = true,
		Dirty = false,
		Released = false,
		OpenedAt = now(),
		LastTouchedAt = now(),
		LastSavedAt = 0,
		LastHeartbeatAt = now(),
		LastSaveError = nil,
		MutationId = 0,
		Journal = {},
		Bindings = {},
		ScopedConnections = {},
		LastPersistedSnapshot = clone(data),
	}, Session)
end

function Session:IsActive()
	return self.Active
		and not self.Released
end

function Session:Get(path)
	return clone(
		getAt(
			self.Data,
			path
		)
	)
end

function Session:Has(path)
	return getAt(
		self.Data,
		path
	) ~= nil
end

function Session:Set(path, value)
	return self.Store:Set(
		self,
		path,
		value
	)
end

function Session:Delete(path)
	return self.Store:Delete(
		self,
		path
	)
end

function Session:Increment(path, amount)
	return self.Store:Increment(
		self,
		path,
		amount
	)
end

function Session:IncrementClamped(
	path,
	amount,
	minimum,
	maximum
)
	return self.Store:IncrementClamped(
		self,
		path,
		amount,
		minimum,
		maximum
	)
end

function Session:Insert(path, value)
	return self.Store:Insert(
		self,
		path,
		value
	)
end

function Session:RemoveAt(path, index)
	return self.Store:RemoveAt(
		self,
		path,
		index
	)
end

function Session:Update(callback)
	return self.Store:Update(
		self,
		callback
	)
end

function Session:Transaction(callback)
	return self.Store:Transaction(
		self,
		callback
	)
end

function Session:Patch(patches)
	return self.Store:Patch(
		self,
		patches
	)
end

function Session:Snapshot(label)
	return self.Store:CreateSnapshot(
		self,
		label
	)
end

function Session:Restore(snapshot)
	return self.Store:RestoreSnapshot(
		self,
		snapshot
	)
end

function Session:Save(priority)
	return self.Store:SaveAsync(
		self,
		priority
	)
end

function Session:Release()
	return self.Store:ReleaseAsync(
		self
	)
end

function Session:Abort(options)
	return self.Store:AbortSession(
		self,
		options
	)
end

function Session:Diff(otherData)
	return diffTables(
		self.Data,
		otherData
	)
end

function Session:DiffFromPersisted()
	return diffTables(
		self.LastPersistedSnapshot,
		self.Data
	)
end

function Session:GetJournal()
	return clone(self.Journal)
end

function Session:ClearJournal()
	table.clear(
		self.Journal
	)

	return true
end

function Session:GetStatus()
	return self.Store:GetSessionStatus(
		self
	)
end

function Session:GetStats()
	return self.Store:GetDataStats(
		self
	)
end

function Session:GetKey()
	return self.Key
end

function Session:GetSessionId()
	return self.SessionId
end

function Session:GetAge()
	return now() - self.OpenedAt
end

function Session:GetLastSaveAge()
	if self.LastSavedAt <= 0 then
		return math.huge
	end

	return now() - self.LastSavedAt
end

function Session:MarkDirty()
	self.Dirty = true
	self.LastTouchedAt = now()

	return true
end

function Session:IsDirty()
	return self.Dirty
end

function Session:BindValue(
	path,
	valueObject,
	options
)
	return self.Store:BindValue(
		self,
		path,
		valueObject,
		options
	)
end

function Session:_TrackConnection(connection)
	table.insert(
		self.ScopedConnections,
		connection
	)

	return connection
end

function Session:_DestroyConnections()
	for _, connection in ipairs(self.ScopedConnections) do
		pcall(function()
			connection:Disconnect()
		end)
	end

	table.clear(
		self.ScopedConnections
	)

	for _, binding in pairs(self.Bindings) do
		pcall(function()
			binding:Destroy()
		end)
	end

	table.clear(
		self.Bindings
	)
end

function NexusDataStore._NewV61(config)
	assert(
		RunService:IsServer(),
		"NexusDataStore must run on the server"
	)

	assert(
		typeof(config) == "table",
		"Configuration table required"
	)

	assert(
		typeof(config.Name) == "string"
			and #config.Name > 0,
		"Name is required"
	)

	local dataTemplate = config.DataTemplate
	local template
	local schema
	local strict
	local schemaVersion

	if dataTemplate then
		assert(
			typeof(dataTemplate.Data) == "table",
			"DataTemplate.Data must be a table"
		)

		template = clone(
			dataTemplate.Data
		)

		schema = dataTemplate.Schema
		strict = dataTemplate.Strict == true
		schemaVersion = dataTemplate.Version
			or config.SchemaVersion
			or 1
	else
		assert(
			typeof(config.Template) == "table",
			"Template or DataTemplate required"
		)

		template = clone(
			config.Template
		)

		schema = config.Schema
		strict = config.Strict == true
		schemaVersion = config.SchemaVersion
			or 1
	end

	local self = setmetatable(
		{},
		NexusDataStore
	)

	self.Config = {
		Name = config.Name,
		Scope = config.Scope or "Global",
		Template = template,
		Schema = schema,
		Strict = strict,
		SchemaVersion = schemaVersion,
		Migrations = config.Migrations or {},
		AutoSave = config.AutoSave ~= false,
		AutoSaveInterval = math.max(
			10,
			config.AutoSaveInterval or 30
		),
		LockTimeout = math.max(
			45,
			config.LockTimeout or 120
		),
		HeartbeatInterval = math.max(
			15,
			config.HeartbeatInterval
				or math.floor(
					(config.LockTimeout or 120) / 3
				)
		),
		RetryAttempts = math.max(
			1,
			config.RetryAttempts or 6
		),
		RetryBaseDelay = config.RetryBaseDelay
			or 0.5,
		RetryMaxDelay = config.RetryMaxDelay
			or 10,
		BudgetAware = config.BudgetAware ~= false,
		BudgetWaitTimeout = config.BudgetWaitTimeout
			or 10,
		MinimumSaveInterval = config.MinimumSaveInterval
			or 3,
		MaxDataNodes = config.MaxDataNodes
			or 50000,
		MaxDataBytes = config.MaxDataBytes
			or 3900000,
		MaxJournalEntries = config.MaxJournalEntries
			or 1000,
		MaxSnapshots = config.MaxSnapshots
			or 10,
		LoadTimeout = config.LoadTimeout
			or 30,
		SaveTimeout = config.SaveTimeout
			or 30,
		EnableCrossServer = config.EnableCrossServer == true,
		CrossServerTopic = config.CrossServerTopic
			or ("NexusDataStore:" .. config.Name),
		Debug = config.Debug == true,
	}

	self.Template = template
	self.Schema = schema
	self.Strict = strict
	self.SchemaVersion = schemaVersion

	self.DataStore = DataStoreService:GetDataStore(
		self.Config.Name,
		self.Config.Scope
	)

	self.JobId = game.JobId ~= ""
		and game.JobId
		or HttpService:GenerateGUID(false)

	self.Sessions = {}
	self.SessionByKey = {}
	self.SessionById = {}
	self.Events = {}
	self.SaveQueue = {}
	self.SaveQueued = {}
	self.Snapshots = {}
	self.Closed = false
	self.Closing = false
	self.LifecycleAttached = false
	self.BoundToClose = false
	self.SaveWorkerRunning = false
	self.CrossServerSubscription = nil

	self.Metrics = {
		Opened = 0,
		Released = 0,
		LoadsFailed = 0,
		Saved = 0,
		SaveFailed = 0,
		Retries = 0,
		Mutations = 0,
		Transactions = 0,
		Rollbacks = 0,
		Heartbeats = 0,
		LocksRecovered = 0,
		SessionLost = 0,
		TypeErrors = 0,
		BytesEncoded = 0,
		LoadTime = 0,
		SaveTime = 0,
	}

	if self.Config.EnableCrossServer then
		local ok, subscription = pcall(function()
			return MessagingService:SubscribeAsync(
				self.Config.CrossServerTopic,
				function(message)
					self:_Fire(
						"CrossServer",
						message.Data
					)
				end
			)
		end)

		if ok then
			self.CrossServerSubscription = subscription
		else
			self:_Debug(
				"Cross-server subscription failed",
				subscription
			)
		end
	end

	task.spawn(function()
		self:_AutoSaveLoop()
	end)

	task.spawn(function()
		self:_HeartbeatLoop()
	end)

	return self
end

function NexusDataStore:_Debug(...)
	if not self.Config.Debug then
		return
	end

	print(
		"[NexusDataStore]",
		...
	)
end

function NexusDataStore:_GetSignal(name)
	local signal = self.Events[name]

	if not signal then
		signal = Signal.new()
		self.Events[name] = signal
	end

	return signal
end

function NexusDataStore:On(name, callback)
	return self:_GetSignal(
		name
	):Connect(callback)
end

function NexusDataStore:Once(name, callback)
	return self:_GetSignal(
		name
	):Once(callback)
end

function NexusDataStore:_Fire(name, ...)
	local signal = self.Events[name]

	if signal then
		signal:Fire(...)
	end
end

function NexusDataStore:_WaitForBudget(requestType)
	if not self.Config.BudgetAware then
		return true
	end

	local deadline = now()
		+ self.Config.BudgetWaitTimeout

	while now() < deadline
		and not self.Closed do
		local ok, budget = pcall(function()
			return DataStoreService:GetRequestBudgetForRequestType(
				requestType
			)
		end)

		if ok
			and budget > 0 then
			return true
		end

		task.wait(0.25)
	end

	return false
end

function NexusDataStore:_Retry(callback)
	local lastError

	for attempt = 1, self.Config.RetryAttempts do
		local ok, result = pcall(
			callback,
			attempt
		)

		if ok then
			return true, result, attempt
		end

		lastError = result

		if attempt >= self.Config.RetryAttempts
			or not transientError(result) then
			break
		end

		self.Metrics.Retries += 1

		local delay = math.min(
			self.Config.RetryMaxDelay,
			self.Config.RetryBaseDelay
				* (2 ^ (attempt - 1))
		)

		delay *= 0.75
			+ math.random() * 0.5

		task.wait(delay)
	end

	return false, lastError
end

function NexusDataStore:_ValidateDataV620(data)
	local ok, err, details = validateData(
		data,
		self.Schema,
		self.Strict,
		self.Config.MaxDataNodes,
		self.Config.MaxDataBytes
	)

	if not ok then
		self.Metrics.TypeErrors += 1
	end

	return ok, err, details
end

function NexusDataStore:Validate(dataOrSession)
	if typeof(dataOrSession) == "table"
		and dataOrSession.Store == self then
		return self:_ValidateData(
			dataOrSession.Data
		)
	end

	return self:_ValidateData(
		dataOrSession
	)
end

function NexusDataStore:_ApplyMigrations(
	data,
	fromVersion
)
	local current = fromVersion or 1
	local output = clone(data)

	while current < self.SchemaVersion do
		local nextVersion = current + 1
		local migration = self.Config.Migrations[nextVersion]

		if migration then
			self:_Fire(
				"MigrationStarted",
				current,
				nextVersion,
				output
			)

			local ok, result = pcall(
				migration,
				output,
				{
					FromVersion = current,
					ToVersion = nextVersion,
					Store = self,
				}
			)

			if not ok then
				return nil,
					("Migration %d failed: %s"):format(
						nextVersion,
						tostring(result)
					)
			end

			if result ~= nil then
				output = result
			end

			self:_Fire(
				"MigrationCompleted",
				current,
				nextVersion,
				output
			)
		end

		current = nextVersion
	end

	output = reconcile(
		output,
		self.Template
	)

	local valid, err = self:_ValidateData(output)

	if not valid then
		return nil, err
	end

	return output
end

function NexusDataStore:_DecodeStoredV61(raw)
	if raw == nil then
		return nil
	end

	local ok, record = pcall(
		decodeRecord,
		raw
	)

	if not ok then
		return nil,
			"DECODE_FAILED:"
			.. tostring(record)
	end

	if typeof(record) ~= "table" then
		return nil,
			"INVALID_RECORD"
	end

	return record
end

function NexusDataStore:_EncodeStoredV61(record)
	local ok, encoded = pcall(
		encodeRecord,
		record
	)

	if not ok then
		return nil,
			"ENCODE_FAILED:"
			.. tostring(encoded)
	end

	self.Metrics.BytesEncoded += buffer.len(encoded)

	return encoded
end

function NexusDataStore:_BuildRecord(
	session,
	release
)
	local record = {
		Format = FORMAT,
		SchemaVersion = self.SchemaVersion,
		Revision = session.Revision + 1,
		UpdatedAt = os.time(),
		CreatedAt = session.CreatedAt
			or os.time(),
		Data = session.Data,
		Session = release
			and nil
			or {
				JobId = self.JobId,
				SessionId = session.SessionId,
				PlayerId = session.Player.UserId,
				ExpiresAt = os.time()
				+ self.Config.LockTimeout,
			},
	}

	return record
end

function NexusDataStore:_RegisterSession(session)
	self.Sessions[session.Player] = session
	self.SessionByKey[session.Key] = session
	self.SessionById[session.SessionId] = session

	self.Metrics.Opened += 1

	self:_Fire(
		"SessionOpened",
		session
	)

	self:_Fire(
		"PlayerLoaded",
		session.Player,
		session
	)
end

function NexusDataStore:_UnregisterSession(session)
	self.Sessions[session.Player] = nil
	self.SessionByKey[session.Key] = nil
	self.SessionById[session.SessionId] = nil

	session.Active = false
	session.Released = true

	session:_DestroyConnections()

	self.Metrics.Released += 1

	self:_Fire(
		"SessionReleased",
		session
	)
end

function NexusDataStore:_OpenPlayerAsyncV620(player)
	assert(
		player
			and player:IsA("Player"),
		"Player required"
	)

	if self.Closed
		or self.Closing then
		return nil,
			"STORE_CLOSED"
	end

	local existing = self.Sessions[player]

	if existing
		and existing:IsActive() then
		return existing
	end

	local key = makePlayerKey(player)
	local started = now()
	local loaded
	local lockedBy
	local decodeFailure

	local budgetOK = self:_WaitForBudget(
		Enum.DataStoreRequestType.UpdateAsync
	)

	if not budgetOK then
		return nil,
			"BUDGET_TIMEOUT"
	end

	local success, err = self:_Retry(function()
		self.DataStore:UpdateAsync(
			key,
			function(old)
				local record

				if old ~= nil then
					local decoded, decodeErr = self:_DecodeStored(old)

					if not decoded then
						decodeFailure = decodeErr

						return old
					end

					record = decoded
				end

				local currentTime = os.time()

				if record
					and record.Session then
					local sameServer = record.Session.JobId
						== self.JobId

					local expired = (record.Session.ExpiresAt or 0)
						<= currentTime

					if not sameServer
						and not expired then
						lockedBy = record.Session.JobId

						return old
					end

					if expired
						and not sameServer then
						self.Metrics.LocksRecovered += 1

						self:_Fire(
							"StaleSessionRecovered",
							key,
							record.Session
						)
					end
				end

				local data = record
					and record.Data
					or clone(self.Template)

				local storedVersion = record
					and record.SchemaVersion
					or self.SchemaVersion

				local migrated, migrationErr = self:_ApplyMigrations(
					data,
					storedVersion
				)

				if not migrated then
					decodeFailure = migrationErr

					return old
				end

				local revision = (record
					and record.Revision
					or 0) + 1

				local sessionId = makeSessionId()

				loaded = {
					Data = clone(migrated),
					Revision = revision,
					SessionId = sessionId,
					CreatedAt = record
						and record.CreatedAt
						or currentTime,
				}

				local temporarySession = {
					Revision = revision - 1,
					Data = migrated,
					SessionId = sessionId,
					Player = player,
					CreatedAt = loaded.CreatedAt,
				}

				local nextRecord = self:_BuildRecord(
					temporarySession,
					false
				)

				nextRecord.Revision = revision

				local encoded, encodeErr = self:_EncodeStored(
					nextRecord
				)

				if not encoded then
					decodeFailure = encodeErr

					return old
				end

				return encoded
			end
		)
	end)

	self.Metrics.LoadTime += now() - started

	if not success then
		self.Metrics.LoadsFailed += 1

		self:_Fire(
			"PlayerLoadFailed",
			player,
			err
		)

		return nil, tostring(err)
	end

	if decodeFailure then
		self.Metrics.LoadsFailed += 1

		self:_Fire(
			"PlayerLoadFailed",
			player,
			decodeFailure
		)

		return nil, decodeFailure
	end

	if lockedBy then
		self.Metrics.LoadsFailed += 1

		return nil,
			"SESSION_LOCKED:"
			.. tostring(lockedBy)
	end

	if not loaded then
		self.Metrics.LoadsFailed += 1

		return nil,
			"OPEN_FAILED"
	end

	local session = Session.new(
		self,
		player,
		key,
		loaded.Data,
		loaded.Revision,
		self.SchemaVersion,
		loaded.SessionId
	)

	session.CreatedAt = loaded.CreatedAt

	self:_RegisterSession(session)

	return session
end

function NexusDataStore:GetSession(playerOrKey)
	if typeof(playerOrKey) == "Instance"
		and playerOrKey:IsA("Player") then
		return self.Sessions[playerOrKey]
	end

	if typeof(playerOrKey) == "string" then
		return self.SessionByKey[playerOrKey]
			or self.SessionById[playerOrKey]
	end

	return nil
end

function NexusDataStore:GetSessionById(sessionId)
	return self.SessionById[sessionId]
end

function NexusDataStore:GetActiveSessions()
	local result = {}

	for _, session in pairs(self.Sessions) do
		if session:IsActive() then
			table.insert(
				result,
				session
			)
		end
	end

	return result
end

function NexusDataStore:CountSessions()
	local count = 0

	for _, session in pairs(self.Sessions) do
		if session:IsActive() then
			count += 1
		end
	end

	return count
end

function NexusDataStore:WaitForSession(
	player,
	timeout
)
	local deadline = now()
		+ (timeout or self.Config.LoadTimeout)

	repeat
		local session = self.Sessions[player]

		if session
			and session:IsActive() then
			return session
		end

		if not player.Parent then
			return nil,
				"PLAYER_LEFT"
		end

		task.wait()
	until now() >= deadline

	return nil,
		"SESSION_TIMEOUT"
end

function NexusDataStore:_TouchV620(
	session,
	operation,
	path,
	before,
	after
)
	session.Dirty = true
	session.LastTouchedAt = now()
	session.MutationId += 1

	local entry = {
		Id = session.MutationId,
		Operation = operation,
		Path = pathToString(path),
		Before = clone(before),
		After = clone(after),
		Timestamp = os.time(),
	}

	table.insert(
		session.Journal,
		entry
	)

	while #session.Journal
		> self.Config.MaxJournalEntries do
		table.remove(
			session.Journal,
			1
		)
	end

	self.Metrics.Mutations += 1

	self:_Fire(
		"DataChanged",
		session,
		entry.Path,
		before,
		after,
		entry
	)
end

function NexusDataStore:Set(
	session,
	path,
	value
)
	assert(
		session
			and session:IsActive(),
		"Active session required"
	)

	local beforeData = clone(
		session.Data
	)

	local before = clone(
		getAt(
			session.Data,
			path
		)
	)

	setAt(
		session.Data,
		path,
		clone(value)
	)

	local valid, err = self:_ValidateData(
		session.Data
	)

	if not valid then
		session.Data = beforeData

		return false, err
	end

	self:_Touch(
		session,
		"Set",
		path,
		before,
		value
	)

	return true
end

function NexusDataStore:Delete(
	session,
	path
)
	assert(
		session
			and session:IsActive(),
		"Active session required"
	)

	local beforeData = clone(
		session.Data
	)

	local before = clone(
		getAt(
			session.Data,
			path
		)
	)

	local changed = deleteAt(
		session.Data,
		path
	)

	if not changed then
		return false,
			"PATH_NOT_FOUND"
	end

	local valid, err = self:_ValidateData(
		session.Data
	)

	if not valid then
		session.Data = beforeData

		return false, err
	end

	self:_Touch(
		session,
		"Delete",
		path,
		before,
		nil
	)

	return true
end

function NexusDataStore:Increment(
	session,
	path,
	amount
)
	assert(
		session
			and session:IsActive(),
		"Active session required"
	)

	amount = amount or 1

	assert(
		finiteNumber(amount),
		"Increment amount must be finite"
	)

	local current = getAt(
		session.Data,
		path
	)

	if not finiteNumber(current) then
		return false,
			"NOT_NUMBER"
	end

	return self:Set(
		session,
		path,
		current + amount
	)
end

function NexusDataStore:IncrementClamped(
	session,
	path,
	amount,
	minimum,
	maximum
)
	local current = getAt(
		session.Data,
		path
	)

	if not finiteNumber(current) then
		return false,
			"NOT_NUMBER"
	end

	local nextValue = current + (amount or 1)

	if minimum ~= nil then
		nextValue = math.max(
			minimum,
			nextValue
		)
	end

	if maximum ~= nil then
		nextValue = math.min(
			maximum,
			nextValue
		)
	end

	return self:Set(
		session,
		path,
		nextValue
	)
end

function NexusDataStore:Insert(
	session,
	path,
	value
)
	assert(
		session
			and session:IsActive(),
		"Active session required"
	)

	local beforeData = clone(
		session.Data
	)

	local list = getAt(
		session.Data,
		path
	)

	if typeof(list) ~= "table" then
		return false,
			"NOT_TABLE"
	end

	table.insert(
		list,
		clone(value)
	)

	local valid, err = self:_ValidateData(
		session.Data
	)

	if not valid then
		session.Data = beforeData

		return false, err
	end

	self:_Touch(
		session,
		"Insert",
		path,
		nil,
		value
	)

	return true, #list
end

function NexusDataStore:RemoveAt(
	session,
	path,
	index
)
	assert(
		session
			and session:IsActive(),
		"Active session required"
	)

	local list = getAt(
		session.Data,
		path
	)

	if typeof(list) ~= "table" then
		return false,
			"NOT_TABLE"
	end

	if index < 1
		or index > #list then
		return false,
			"INDEX_OUT_OF_RANGE"
	end

	local beforeData = clone(
		session.Data
	)

	local removed = table.remove(
		list,
		index
	)

	local valid, err = self:_ValidateData(
		session.Data
	)

	if not valid then
		session.Data = beforeData

		return false, err
	end

	self:_Touch(
		session,
		"RemoveAt",
		path,
		removed,
		nil
	)

	return true, removed
end

function NexusDataStore:Update(
	session,
	callback
)
	assert(
		session
			and session:IsActive(),
		"Active session required"
	)

	assert(
		typeof(callback) == "function",
		"Update callback required"
	)

	local before = clone(
		session.Data
	)

	local working = clone(
		session.Data
	)

	local ok, result = pcall(
		callback,
		working,
		session
	)

	if not ok then
		self:_Fire(
			"UpdateFailed",
			session,
			result
		)

		return false, result
	end

	local valid, err = self:_ValidateData(
		working
	)

	if not valid then
		self:_Fire(
			"UpdateFailed",
			session,
			err
		)

		return false, err
	end

	session.Data = working

	self:_Touch(
		session,
		"Update",
		{"$"},
		before,
		session.Data
	)

	return true, result
end

function NexusDataStore:Transaction(
	session,
	callback
)
	assert(
		session
			and session:IsActive(),
		"Active session required"
	)

	assert(
		typeof(callback) == "function",
		"Transaction callback required"
	)

	local transaction = Transaction.new(
		self,
		session
	)

	self:_Fire(
		"TransactionStarted",
		session,
		transaction
	)

	local ok, result = pcall(
		callback,
		transaction
	)

	if not ok
		or result == false then
		transaction:Rollback()

		self.Metrics.Rollbacks += 1

		self:_Fire(
			"TransactionRolledBack",
			session,
			transaction,
			ok
				and "TRANSACTION_REJECTED"
				or result
		)

		return false,
			ok
			and "TRANSACTION_REJECTED"
			or result
	end

	local valid, err = self:_ValidateData(
		transaction.Data
	)

	if not valid then
		transaction:Rollback()

		self.Metrics.Rollbacks += 1

		self:_Fire(
			"TransactionRolledBack",
			session,
			transaction,
			err
		)

		return false, err
	end

	local before = session.Data
	local changes = diffTables(
		before,
		transaction.Data
	)

	transaction:Commit()

	if #changes == 0 then
		self:_Fire(
			"TransactionCommitted",
			session,
			transaction,
			changes
		)

		return true, result
	end

	session.Data = transaction.Data

	self:_Touch(
		session,
		"Transaction",
		{"$"},
		before,
		session.Data
	)

	self.Metrics.Transactions += 1

	self:_Fire(
		"TransactionCommitted",
		session,
		transaction,
		changes
	)

	return true, result
end

function NexusDataStore:Patch(
	session,
	patches
)
	assert(
		typeof(patches) == "table",
		"Patches must be a table"
	)

	return self:Transaction(
		session,
		function(transaction)
			for _, patch in ipairs(patches) do
				local operation = patch.Op
					or patch.Operation

				if operation == "Set"
					or operation == "Replace"
					or operation == "Add" then
					transaction:Set(
						patch.Path,
						patch.Value
					)
				elseif operation == "Delete"
					or operation == "Remove" then
					transaction:Delete(
						patch.Path
					)
				elseif operation == "Increment" then
					transaction:Increment(
						patch.Path,
						patch.Amount or 1
					)
				elseif operation == "Insert" then
					transaction:Insert(
						patch.Path,
						patch.Value
					)
				else
					error(
						"Unknown patch operation: "
							.. tostring(operation)
					)
				end
			end
		end
	)
end

function NexusDataStore:CreateSnapshot(
	session,
	label
)
	assert(
		session
			and session:IsActive(),
		"Active session required"
	)

	local snapshot = {
		Id = HttpService:GenerateGUID(false),
		Label = label or "Snapshot",
		CreatedAt = os.time(),
		Revision = session.Revision,
		SchemaVersion = session.SchemaVersion,
		Data = clone(session.Data),
	}

	local list = self.Snapshots[session.Key]

	if not list then
		list = {}
		self.Snapshots[session.Key] = list
	end

	table.insert(
		list,
		1,
		snapshot
	)

	while #list
		> self.Config.MaxSnapshots do
		table.remove(
			list
		)
	end

	self:_Fire(
		"SnapshotCreated",
		session,
		snapshot
	)

	return clone(snapshot)
end

function NexusDataStore:GetSnapshots(session)
	return clone(
		self.Snapshots[session.Key]
			or {}
	)
end

function NexusDataStore:RestoreSnapshot(
	session,
	snapshot
)
	assert(
		session
			and session:IsActive(),
		"Active session required"
	)

	if typeof(snapshot) == "string" then
		local found

		for _, candidate in ipairs(
			self.Snapshots[session.Key]
				or {}
			) do
			if candidate.Id == snapshot
				or candidate.Label == snapshot then
				found = candidate
				break
			end
		end

		if not found then
			return false,
				"SNAPSHOT_NOT_FOUND"
		end

		snapshot = found
	end

	assert(
		typeof(snapshot) == "table"
			and typeof(snapshot.Data) == "table",
		"Invalid snapshot"
	)

	local valid, err = self:_ValidateData(
		snapshot.Data
	)

	if not valid then
		return false, err
	end

	local before = session.Data

	session.Data = clone(
		snapshot.Data
	)

	self:_Touch(
		session,
		"RestoreSnapshot",
		{"$"},
		before,
		session.Data
	)

	self:_Fire(
		"SnapshotRestored",
		session,
		snapshot
	)

	return true
end

function NexusDataStore:BindValue(
	session,
	path,
	valueObject,
	options
)
	assert(
		session
			and session:IsActive(),
		"Active session required"
	)

	assert(
		typeof(valueObject) == "Instance"
			and valueObject:IsA("ValueBase"),
		"ValueObject must be a ValueBase"
	)

	options = options or {}

	local key = HttpService:GenerateGUID(false)
	local destroyed = false
	local syncing = false

	local function pushSessionToValue()
		if destroyed
			or not session:IsActive() then
			return
		end

		local value = getAt(
			session.Data,
			path
		)

		if valueObject.Value ~= value then
			syncing = true
			valueObject.Value = value
			syncing = false
		end
	end

	local dataConnection = self:On(
		"DataChanged",
		function(
			changedSession,
			changedPath
		)
			if changedSession ~= session then
				return
			end

			if changedPath
				== pathToString(path) then
				pushSessionToValue()
			end
		end
	)

	local valueConnection

	if options.TwoWay ~= false then
		valueConnection = valueObject:GetPropertyChangedSignal(
			"Value"
		):Connect(function()
			if destroyed
				or syncing
				or not session:IsActive() then
				return
			end

			local ok, err = session:Set(
				path,
				valueObject.Value
			)

			if not ok then
				self:_Fire(
					"BindingRejected",
					session,
					pathToString(path),
					err
				)

				pushSessionToValue()
			end
		end)
	end

	pushSessionToValue()

	local binding = {}

	function binding:Destroy()
		if destroyed then
			return
		end

		destroyed = true

		dataConnection:Disconnect()

		if valueConnection then
			valueConnection:Disconnect()
		end

		session.Bindings[key] = nil
	end

	session.Bindings[key] = binding

	return binding
end

function NexusDataStore:_PriorityValue(priority)
	if typeof(priority) == "number" then
		return priority
	end

	return PRIORITIES[priority or "normal"]
		or PRIORITIES.normal
end

function NexusDataStore:_QueueSave(
	session,
	priority,
	reason,
	release
)
	if not session:IsActive() then
		return false,
			"SESSION_INACTIVE"
	end

	local key = session.Key
	local existing = self.SaveQueued[key]
	local priorityValue = self:_PriorityValue(
		priority
	)

	if existing then
		existing.Priority = math.max(
			existing.Priority,
			priorityValue
		)

		if release then
			existing.Release = true
		end

		return true
	end

	local item = {
		Session = session,
		Priority = priorityValue,
		Reason = reason or "manual",
		Release = release == true,
		Sequence = os.clock(),
	}

	self.SaveQueued[key] = item

	table.insert(
		self.SaveQueue,
		item
	)

	self:_Fire(
		"SaveQueued",
		session,
		item
	)

	self:_StartSaveWorker()

	return true
end

function NexusDataStore:_PopSave()
	if #self.SaveQueue == 0 then
		return nil
	end

	table.sort(
		self.SaveQueue,
		function(a, b)
			if a.Priority == b.Priority then
				return a.Sequence < b.Sequence
			end

			return a.Priority > b.Priority
		end
	)

	local item = table.remove(
		self.SaveQueue,
		1
	)

	if item then
		self.SaveQueued[item.Session.Key] = nil
	end

	return item
end

function NexusDataStore:_StartSaveWorker()
	if self.SaveWorkerRunning then
		return
	end

	self.SaveWorkerRunning = true

	task.spawn(function()
		while not self.Closed do
			local item = self:_PopSave()

			if not item then
				break
			end

			local session = item.Session

			if session:IsActive()
				and (
					session.Dirty
						or item.Release
				) then
				local ok, err = self:_Commit(
					session,
					item.Release,
					item.Reason
				)

				if not ok then
					session.LastSaveError = err

					self:_Fire(
						"SaveFailed",
						session,
						err,
						item
					)

					if session:IsActive()
						and not self.Closing then
						task.delay(
							1,
							function()
								self:_QueueSave(
									session,
									item.Priority,
									"retry",
									item.Release
								)
							end
						)
					end
				end
			end

			task.wait()
		end

		self.SaveWorkerRunning = false

		if #self.SaveQueue > 0
			and not self.Closed then
			self:_StartSaveWorker()
		end
	end)
end

function NexusDataStore:_CommitV620(
	session,
	release,
	reason
)
	if not session:IsActive() then
		return false,
			"SESSION_INACTIVE"
	end

	local valid, validationErr = self:_ValidateData(
		session.Data
	)

	if not valid then
		return false,
			"VALIDATION_FAILED:"
			.. tostring(validationErr)
	end

	if not release
		and not session.Dirty then
		return true
	end

	local elapsed = now()
	- session.LastSavedAt

	if not release
		and session.LastSavedAt > 0
		and elapsed < self.Config.MinimumSaveInterval then
		task.delay(
			self.Config.MinimumSaveInterval - elapsed,
			function()
				if session:IsActive()
					and session.Dirty
					and not self.Closed then
					self:_QueueSave(
						session,
						"normal",
						"coalesced"
					)
				end
			end
		)

		return true,
			"COALESCED"
	end

	local budgetOK = self:_WaitForBudget(
		Enum.DataStoreRequestType.UpdateAsync
	)

	if not budgetOK then
		return false,
			"BUDGET_TIMEOUT"
	end

	local started = now()
	local committed = false
	local ownershipLost = false
	local snapshot = clone(session.Data)
	local expectedRevision = session.Revision

	self:_Fire(
		"SaveStarted",
		session,
		reason
	)

	local success, err = self:_Retry(function()
		self.DataStore:UpdateAsync(
			session.Key,
			function(old)
				local record
				local decodeErr

				if old ~= nil then
					record, decodeErr = self:_DecodeStored(old)

					if not record then
						error(
							decodeErr
						)
					end
				end

				if not record
					or not record.Session then
					if release then
						ownershipLost = true

						return old
					end
				elseif record.Session.JobId ~= self.JobId
					or record.Session.SessionId ~= session.SessionId then
					ownershipLost = true

					return old
				end

				local recordSession = {
					Data = snapshot,
					Revision = expectedRevision,
					SessionId = session.SessionId,
					Player = session.Player,
					CreatedAt = session.CreatedAt,
				}

				local nextRecord = self:_BuildRecord(
					recordSession,
					release
				)

				nextRecord.Revision = expectedRevision + 1

				local encoded, encodeErr = self:_EncodeStored(
					nextRecord
				)

				if not encoded then
					error(encodeErr)
				end

				committed = true

				return encoded
			end
		)
	end)

	self.Metrics.SaveTime += now() - started

	if not success then
		self.Metrics.SaveFailed += 1

		return false, tostring(err)
	end

	if ownershipLost then
		self:_LoseSession(
			session,
			"SESSION_OWNERSHIP_LOST"
		)

		return false,
			"SESSION_OWNERSHIP_LOST"
	end

	if not committed then
		return false,
			"COMMIT_CANCELLED"
	end

	session.Revision = expectedRevision + 1
	session.Dirty = false
	session.LastSavedAt = now()
	session.LastSaveError = nil
	session.LastPersistedSnapshot = clone(snapshot)

	self.Metrics.Saved += 1

	self:_Fire(
		"SaveCompleted",
		session,
		reason
	)

	if release then
		self:_UnregisterSession(
			session
		)
	end

	return true
end

function NexusDataStore:_SaveAsyncV620(
	session,
	priority
)
	if not session
		or not session:IsActive() then
		return false,
			"SESSION_INACTIVE"
	end

	if not session.Dirty then
		return true
	end

	local queued, err = self:_QueueSave(
		session,
		priority or "high",
		"manual"
	)

	if not queued then
		return false, err
	end

	local deadline = now()
		+ self.Config.SaveTimeout

	while now() < deadline do
		if not session:IsActive() then
			return false,
				"SESSION_INACTIVE"
		end

		if not session.Dirty then
			return true
		end

		task.wait(0.05)
	end

	return false,
		"SAVE_TIMEOUT"
end

function NexusDataStore:ReleaseAsync(session)
	if not session
		or not session:IsActive() then
		return true
	end

	return self:_Commit(
		session,
		true,
		"release"
	)
end

function NexusDataStore:AbortSession(
	session,
	options
)
	if not session
		or not session:IsActive() then
		return true
	end

	options = options or {}

	assert(
		options.Confirmed == true,
		"AbortSession requires Confirmed = true"
	)

	local budgetOK = self:_WaitForBudget(
		Enum.DataStoreRequestType.UpdateAsync
	)

	if not budgetOK then
		return false,
			"BUDGET_TIMEOUT"
	end

	local released = false
	local lost = false

	local success, err = self:_Retry(function()
		self.DataStore:UpdateAsync(
			session.Key,
			function(old)
				if old == nil then
					lost = true
					return nil
				end

				local record, decodeErr = self:_DecodeStored(old)

				if not record then
					error(decodeErr)
				end

				if not record.Session
					or record.Session.JobId ~= self.JobId
					or record.Session.SessionId ~= session.SessionId then
					lost = true

					return old
				end

				record.Session = nil
				record.UpdatedAt = os.time()

				local encoded, encodeErr = self:_EncodeStored(
					record
				)

				if not encoded then
					error(encodeErr)
				end

				released = true

				return encoded
			end
		)
	end)

	if not success then
		return false, tostring(err)
	end

	if lost then
		self:_LoseSession(
			session,
			"SESSION_OWNERSHIP_LOST"
		)

		return false,
			"SESSION_OWNERSHIP_LOST"
	end

	if not released then
		return false,
			"ABORT_FAILED"
	end

	self:_UnregisterSession(
		session
	)

	self:_Fire(
		"SessionAborted",
		session
	)

	return true
end

function NexusDataStore:_LoseSession(
	session,
	reason
)
	if not session:IsActive() then
		return
	end

	self.Metrics.SessionLost += 1

	self:_UnregisterSession(
		session
	)

	self:_Fire(
		"SessionLost",
		session,
		reason
	)
end

function NexusDataStore:_HeartbeatSession(session)
	if not session:IsActive() then
		return
	end

	local budgetOK = self:_WaitForBudget(
		Enum.DataStoreRequestType.UpdateAsync
	)

	if not budgetOK then
		self:_Fire(
			"HeartbeatDeferred",
			session,
			"BUDGET_TIMEOUT"
		)

		return
	end

	local refreshed = false
	local ownershipLost = false

	local success, err = self:_Retry(function()
		self.DataStore:UpdateAsync(
			session.Key,
			function(old)
				if old == nil then
					ownershipLost = true
					return nil
				end

				local record, decodeErr = self:_DecodeStored(old)

				if not record then
					error(decodeErr)
				end

				if not record.Session
					or record.Session.JobId ~= self.JobId
					or record.Session.SessionId ~= session.SessionId then
					ownershipLost = true

					return old
				end

				record.Session.ExpiresAt = os.time()
					+ self.Config.LockTimeout

				local encoded, encodeErr = self:_EncodeStored(
					record
				)

				if not encoded then
					error(encodeErr)
				end

				refreshed = true

				return encoded
			end
		)
	end)

	if ownershipLost then
		self:_LoseSession(
			session,
			"SESSION_OWNERSHIP_LOST"
		)

		return
	end

	if success
		and refreshed then
		session.LastHeartbeatAt = now()

		self.Metrics.Heartbeats += 1

		self:_Fire(
			"SessionHeartbeat",
			session
		)
	else
		self:_Fire(
			"HeartbeatFailed",
			session,
			err
		)
	end
end

function NexusDataStore:_HeartbeatLoop()
	while not self.Closed do
		task.wait(
			self.Config.HeartbeatInterval
		)

		if self.Closed then
			break
		end

		for _, session in pairs(self.Sessions) do
			if session:IsActive() then
				local sinceSave = session.LastSavedAt > 0
					and now() - session.LastSavedAt
					or math.huge

				if sinceSave
					>= self.Config.HeartbeatInterval then
					self:_HeartbeatSession(
						session
					)
				end
			end
		end
	end
end

function NexusDataStore:_AutoSaveLoopV620()
	while not self.Closed do
		task.wait(
			self.Config.AutoSaveInterval
		)

		if self.Closed then
			break
		end

		if self.Config.AutoSave then
			for _, session in pairs(self.Sessions) do
				if session:IsActive()
					and session.Dirty then
					self:_QueueSave(
						session,
						"normal",
						"autosave"
					)
				end
			end
		end
	end
end

function NexusDataStore:GetSessionStatus(session)
	if not session then
		return {
			Exists = false,
			Active = false,
		}
	end

	return {
		Exists = true,
		Active = session:IsActive(),
		Key = session.Key,
		SessionId = session.SessionId,
		Revision = session.Revision,
		SchemaVersion = session.SchemaVersion,
		Dirty = session.Dirty,
		MutationId = session.MutationId,
		Age = now() - session.OpenedAt,
		LastTouchedAge = now() - session.LastTouchedAt,
		LastSaveAge = session.LastSavedAt > 0
			and now() - session.LastSavedAt
			or math.huge,
		LastHeartbeatAge = now() - session.LastHeartbeatAt,
		LastSaveError = session.LastSaveError,
		JournalSize = #session.Journal,
		Bindings = countTable(session.Bindings),
	}
end

function NexusDataStore:GetDataStats(session)
	local valid, err, details = self:_ValidateData(
		session.Data
	)

	return {
		Valid = valid,
		Error = err,
		Nodes = details
			and details.Nodes
			or countNodes(session.Data),
		Bytes = details
			and details.Bytes
			or estimateEncodedBytes(session.Data),
		Revision = session.Revision,
		SchemaVersion = session.SchemaVersion,
		Dirty = session.Dirty,
		Mutations = session.MutationId,
	}
end

function NexusDataStore:GetMetrics()
	local metrics = clone(
		self.Metrics
	)

	metrics.ActiveSessions = self:CountSessions()
	metrics.QueuedSaves = #self.SaveQueue
	metrics.SaveWorkerRunning = self.SaveWorkerRunning

	if metrics.Opened > 0 then
		metrics.AverageLoadTime = metrics.LoadTime
			/ metrics.Opened
	end

	if metrics.Saved > 0 then
		metrics.AverageSaveTime = metrics.SaveTime
			/ metrics.Saved
	end

	return metrics
end

function NexusDataStore:GetHealth()
	local budget = 0

	pcall(function()
		budget = DataStoreService:GetRequestBudgetForRequestType(
			Enum.DataStoreRequestType.UpdateAsync
		)
	end)

	local dirty = 0

	for _, session in pairs(self.Sessions) do
		if session:IsActive()
			and session.Dirty then
			dirty += 1
		end
	end

	return {
		Version = NexusDataStore.Version,
		Closed = self.Closed,
		Closing = self.Closing,
		JobId = self.JobId,
		ActiveSessions = self:CountSessions(),
		DirtySessions = dirty,
		QueuedSaves = #self.SaveQueue,
		UpdateBudget = budget,
		Metrics = self:GetMetrics(),
	}
end

function NexusDataStore:GetTemplate()
	return clone(
		self.Template
	)
end

function NexusDataStore:GetSchema()
	return clone(
		self.Schema
	)
end

function NexusDataStore:GetVersion()
	return NexusDataStore.Version
end

function NexusDataStore:FlushAsync(timeout)
	local deadline = now()
		+ (timeout or self.Config.SaveTimeout)

	for _, session in pairs(self.Sessions) do
		if session:IsActive()
			and session.Dirty then
			self:_QueueSave(
				session,
				"critical",
				"flush"
			)
		end
	end

	while now() < deadline do
		local dirty = false

		for _, session in pairs(self.Sessions) do
			if session:IsActive()
				and session.Dirty then
				dirty = true
				break
			end
		end

		if not dirty
			and #self.SaveQueue == 0
			and not self.SaveWorkerRunning then
			return true
		end

		task.wait(0.05)
	end

	return false,
		"FLUSH_TIMEOUT"
end

function NexusDataStore:ReleaseAllAsync()
	local sessions = self:GetActiveSessions()
	local results = {}

	for _, session in ipairs(sessions) do
		local ok, err = self:ReleaseAsync(
			session
		)

		results[session.Key] = {
			Success = ok,
			Error = err,
		}
	end

	return results
end

function NexusDataStore:Publish(
	eventName,
	payload
)
	if not self.Config.EnableCrossServer then
		return false,
			"CROSS_SERVER_DISABLED"
	end

	return pcall(function()
		MessagingService:PublishAsync(
			self.Config.CrossServerTopic,
			{
				Id = HttpService:GenerateGUID(false),
				JobId = self.JobId,
				Event = eventName,
				Payload = clone(payload),
				Timestamp = os.time(),
			}
		)
	end)
end

function NexusDataStore:AttachPlayerLifecycle(
	loadFailureMessage
)
	if self.LifecycleAttached then
		return false,
			"LIFECYCLE_ALREADY_ATTACHED"
	end

	self.LifecycleAttached = true

	Players.PlayerAdded:Connect(function(player)
		local session, err = self:OpenPlayerAsync(
			player
		)

		if not session
			and player.Parent then
			player:Kick(
				loadFailureMessage
					or "Your data could not be loaded. Please rejoin."
			)

			self:_Fire(
				"PlayerLoadFailed",
				player,
				err
			)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		local session = self:GetSession(
			player
		)

		if not session then
			return
		end

		local ok, err = self:ReleaseAsync(
			session
		)

		if not ok then
			self:_Fire(
				"SaveFailed",
				session,
				err
			)
		end
	end)

	return true
end

function NexusDataStore:BindToClose()
	if self.BoundToClose then
		return false,
			"ALREADY_BOUND"
	end

	self.BoundToClose = true

	game:BindToClose(function()
		self:Close()
	end)

	return true
end

function NexusDataStore:Close()
	if self.Closed
		or self.Closing then
		return true
	end

	self.Closing = true

	self:_Fire(
		"ShutdownStarted"
	)

	local flushOK, flushErr = self:FlushAsync(
		25
	)

	local sessions = self:GetActiveSessions()

	for _, session in ipairs(sessions) do
		if session:IsActive() then
			self:ReleaseAsync(
				session
			)
		end
	end

	self.Closed = true
	self.Closing = false

	if self.CrossServerSubscription then
		pcall(function()
			self.CrossServerSubscription:Disconnect()
		end)
	end

	for _, signal in pairs(self.Events) do
		signal:Destroy()
	end

	table.clear(
		self.Events
	)

	return flushOK, flushErr
end

NexusDataStore.Session = Session
NexusDataStore.Transaction = Transaction
NexusDataStore.Schema = Schema

local BitWriter = {}
BitWriter.__index = BitWriter

local BitReader = {}
BitReader.__index = BitReader

local CODEC_MAGIC = 0x4E443632
local CODEC_VERSION = 62

local CODEC_BOOL = 1
local CODEC_UINT = 2
local CODEC_SINT = 3
local CODEC_RANGE = 4
local CODEC_FLOAT32 = 5
local CODEC_FLOAT64 = 6
local CODEC_QUANTIZED = 7
local CODEC_ENUM = 8
local CODEC_STRING = 9
local CODEC_ARRAY = 10
local CODEC_MAP = 11
local CODEC_OPTIONAL = 12
local CODEC_ANY = 13

local function ceilLog2(value)
	if value <= 1 then
		return 0
	end

	return math.ceil(
		math.log(value, 2)
	)
end

local function zigZagEncode(value)
	if value >= 0 then
		return value * 2
	end

	return (-value * 2) - 1
end

local function zigZagDecode(value)
	if value % 2 == 0 then
		return value / 2
	end

	return -((value + 1) / 2)
end

local function typeCodeFromName(name)
	if name == "Bool"
		or name == "Boolean"
		or name == "Bit" then
		return CODEC_BOOL
	end

	if name == "UInt"
		or name == "VarUInt" then
		return CODEC_UINT
	end

	if name == "SInt"
		or name == "VarInt"
		or name == "ZigZag" then
		return CODEC_SINT
	end

	if name == "UIntRange"
		or name == "Range" then
		return CODEC_RANGE
	end

	if name == "Float32" then
		return CODEC_FLOAT32
	end

	if name == "Float64"
		or name == "Number" then
		return CODEC_FLOAT64
	end

	if name == "Quantized"
		or name == "QuantizedFloat" then
		return CODEC_QUANTIZED
	end

	if name == "Enum" then
		return CODEC_ENUM
	end

	if name == "String"
		or name == "RawString" then
		return CODEC_STRING
	end

	if name == "Array" then
		return CODEC_ARRAY
	end

	if name == "Map" then
		return CODEC_MAP
	end

	if name == "Optional" then
		return CODEC_OPTIONAL
	end

	return CODEC_ANY
end

function BitWriter.new(initialBytes)
	return setmetatable({
		Buffer = buffer.create(initialBytes or 128),
		BitPosition = 0,
	}, BitWriter)
end

function BitWriter:_Ensure(bits)
	local neededBits = self.BitPosition + bits
	local neededBytes = math.ceil(neededBits / 8)

	if neededBytes <= buffer.len(self.Buffer) then
		return
	end

	local nextBytes = math.max(
		neededBytes,
		math.max(
			16,
			buffer.len(self.Buffer) * 2
		)
	)

	local nextBuffer = buffer.create(nextBytes)

	buffer.copy(
		nextBuffer,
		0,
		self.Buffer,
		0,
		math.ceil(self.BitPosition / 8)
	)

	self.Buffer = nextBuffer
end

function BitWriter:WriteBit(value)
	self:_Ensure(1)

	local byteIndex = math.floor(
		self.BitPosition / 8
	)

	local bitIndex = self.BitPosition % 8

	if value then
		local current = buffer.readu8(
			self.Buffer,
			byteIndex
		)

		buffer.writeu8(
			self.Buffer,
			byteIndex,
			bit32.bor(
				current,
				bit32.lshift(
					1,
					bitIndex
				)
			)
		)
	end

	self.BitPosition += 1
end

function BitWriter:WriteBits(value, bits)
	assert(
		bits >= 0
			and bits <= 53,
		"WriteBits supports 0-53 bits"
	)

	for bit = 0, bits - 1 do
		local divisor = 2 ^ bit
		local state = math.floor(
			value / divisor
		) % 2 == 1

		self:WriteBit(state)
	end
end

function BitWriter:AlignByte()
	local remainder = self.BitPosition % 8

	if remainder ~= 0 then
		self.BitPosition += 8 - remainder
	end
end

function BitWriter:WriteU8(value)
	self:AlignByte()
	self:_Ensure(8)

	buffer.writeu8(
		self.Buffer,
		math.floor(self.BitPosition / 8),
		value
	)

	self.BitPosition += 8
end

function BitWriter:WriteU16(value)
	self:AlignByte()
	self:_Ensure(16)

	buffer.writeu16(
		self.Buffer,
		math.floor(self.BitPosition / 8),
		value
	)

	self.BitPosition += 16
end

function BitWriter:WriteU32(value)
	self:AlignByte()
	self:_Ensure(32)

	buffer.writeu32(
		self.Buffer,
		math.floor(self.BitPosition / 8),
		value
	)

	self.BitPosition += 32
end

function BitWriter:WriteF32(value)
	self:AlignByte()
	self:_Ensure(32)

	buffer.writef32(
		self.Buffer,
		math.floor(self.BitPosition / 8),
		value
	)

	self.BitPosition += 32
end

function BitWriter:WriteF64(value)
	self:AlignByte()
	self:_Ensure(64)

	buffer.writef64(
		self.Buffer,
		math.floor(self.BitPosition / 8),
		value
	)

	self.BitPosition += 64
end

function BitWriter:WriteVarUInt(value)
	assert(
		finiteNumber(value)
			and value >= 0
			and value % 1 == 0,
		"VarUInt requires a non-negative integer"
	)

	self:AlignByte()

	repeat
		local byte = value % 128
		value = math.floor(value / 128)

		if value > 0 then
			byte += 128
		end

		self:WriteU8(byte)
	until value == 0
end

function BitWriter:WriteVarInt(value)
	assert(
		finiteNumber(value)
			and value % 1 == 0,
		"VarInt requires an integer"
	)

	self:WriteVarUInt(
		zigZagEncode(value)
	)
end

function BitWriter:WriteString(value)
	assert(
		typeof(value) == "string",
		"WriteString requires a string"
	)

	assert(
		utf8.len(value) ~= nil,
		"String must contain valid UTF-8"
	)

	self:WriteVarUInt(#value)
	self:AlignByte()
	self:_Ensure(#value * 8)

	buffer.writestring(
		self.Buffer,
		math.floor(self.BitPosition / 8),
		value
	)

	self.BitPosition += #value * 8
end

function BitWriter:Finish()
	local byteLength = math.ceil(
		self.BitPosition / 8
	)

	local output = buffer.create(byteLength)

	buffer.copy(
		output,
		0,
		self.Buffer,
		0,
		byteLength
	)

	return output, self.BitPosition
end

function BitReader.new(value, bitLength)
	return setmetatable({
		Buffer = value,
		BitPosition = 0,
		BitLength = bitLength or buffer.len(value) * 8,
	}, BitReader)
end

function BitReader:_Need(bits)
	if self.BitPosition + bits > self.BitLength then
		error("Unexpected end of bitstream")
	end
end

function BitReader:ReadBit()
	self:_Need(1)

	local byteIndex = math.floor(
		self.BitPosition / 8
	)

	local bitIndex = self.BitPosition % 8
	local current = buffer.readu8(
		self.Buffer,
		byteIndex
	)

	self.BitPosition += 1

	return bit32.band(
		current,
		bit32.lshift(
			1,
			bitIndex
		)
	) ~= 0
end

function BitReader:ReadBits(bits)
	self:_Need(bits)

	local value = 0

	for bit = 0, bits - 1 do
		if self:ReadBit() then
			value += 2 ^ bit
		end
	end

	return value
end

function BitReader:AlignByte()
	local remainder = self.BitPosition % 8

	if remainder ~= 0 then
		self.BitPosition += 8 - remainder
	end
end

function BitReader:ReadU8()
	self:AlignByte()
	self:_Need(8)

	local value = buffer.readu8(
		self.Buffer,
		math.floor(self.BitPosition / 8)
	)

	self.BitPosition += 8

	return value
end

function BitReader:ReadU16()
	self:AlignByte()
	self:_Need(16)

	local value = buffer.readu16(
		self.Buffer,
		math.floor(self.BitPosition / 8)
	)

	self.BitPosition += 16

	return value
end

function BitReader:ReadU32()
	self:AlignByte()
	self:_Need(32)

	local value = buffer.readu32(
		self.Buffer,
		math.floor(self.BitPosition / 8)
	)

	self.BitPosition += 32

	return value
end

function BitReader:ReadF32()
	self:AlignByte()
	self:_Need(32)

	local value = buffer.readf32(
		self.Buffer,
		math.floor(self.BitPosition / 8)
	)

	self.BitPosition += 32

	return value
end

function BitReader:ReadF64()
	self:AlignByte()
	self:_Need(64)

	local value = buffer.readf64(
		self.Buffer,
		math.floor(self.BitPosition / 8)
	)

	self.BitPosition += 64

	return value
end

function BitReader:ReadVarUInt()
	self:AlignByte()

	local result = 0
	local shift = 0

	while true do
		local byte = self:ReadU8()
		local payload = byte % 128

		result += payload * (2 ^ shift)

		if byte < 128 then
			break
		end

		shift += 7

		if shift > 56 then
			error("VarUInt is too large")
		end
	end

	return result
end

function BitReader:ReadVarInt()
	return zigZagDecode(
		self:ReadVarUInt()
	)
end

function BitReader:ReadString()
	local length = self:ReadVarUInt()

	self:AlignByte()
	self:_Need(length * 8)

	local value = buffer.readstring(
		self.Buffer,
		math.floor(self.BitPosition / 8),
		length
	)

	self.BitPosition += length * 8

	return value
end

local CompressionSchema = {}

local function chooseDefaultEncoding(rule, defaultValue)
	if rule
		and rule.Encoding then
		return typeCodeFromName(
			rule.Encoding
		)
	end

	local valueType = rule
		and rule.Type
		or typeof(defaultValue)

	if valueType == "boolean" then
		return CODEC_BOOL
	end

	if valueType == "number" then
		if rule
			and rule.Min ~= nil
			and rule.Max ~= nil
			and rule.Integer then
			return CODEC_RANGE
		end

		if rule
			and rule.Integer
			and rule.Min ~= nil
			and rule.Min >= 0 then
			return CODEC_UINT
		end

		if rule
			and rule.Integer then
			return CODEC_SINT
		end

		return CODEC_FLOAT64
	end

	if valueType == "string" then
		if rule
			and rule.Values then
			return CODEC_ENUM
		end

		return CODEC_STRING
	end

	if valueType == "table" then
		local array = isDenseArray(defaultValue)

		if array
			or (
				rule
					and rule.ArrayOf
			) then
			return CODEC_ARRAY
		end

		return CODEC_MAP
	end

	return CODEC_ANY
end

local function buildSchemaNode(
	key,
	defaultValue,
	rule
)
	rule = rule or {}

	local node = {
		Key = key,
		Type = rule.Type or typeof(defaultValue),
		Encoding = chooseDefaultEncoding(
			rule,
			defaultValue
		),
		Required = rule.Required ~= false,
		Default = clone(defaultValue),
		Min = rule.Min,
		Max = rule.Max,
		Bits = rule.Bits,
		Values = rule.Values,
		Children = nil,
		ArrayOf = nil,
		OmitDefault = rule.OmitDefault == true,
		Optional = rule.Optional == true
			or rule.Required == false,
	}

	if rule.Children
		or (
			typeof(defaultValue) == "table"
				and not isDenseArray(defaultValue)
		) then
		local childrenRules = rule.Children or {}
		local keys = {}

		if typeof(defaultValue) == "table" then
			for childKey in pairs(defaultValue) do
				keys[childKey] = true
			end
		end

		for childKey in pairs(childrenRules) do
			keys[childKey] = true
		end

		local ordered = {}

		for childKey in pairs(keys) do
			table.insert(
				ordered,
				childKey
			)
		end

		table.sort(
			ordered,
			function(a, b)
				return tostring(a) < tostring(b)
			end
		)

		node.Children = {}

		for _, childKey in ipairs(ordered) do
			node.Children[childKey] = buildSchemaNode(
				childKey,
				typeof(defaultValue) == "table"
					and defaultValue[childKey]
					or nil,
				childrenRules[childKey]
			)
		end
	end

	if rule.ArrayOf then
		node.ArrayOf = buildSchemaNode(
			nil,
			nil,
			rule.ArrayOf
		)
	end

	return node
end

function CompressionSchema.Build(
	template,
	schema
)
	local root = {
		Type = "table",
		Encoding = CODEC_MAP,
		Children = {},
		Default = clone(template),
	}

	local keys = {}

	for key in pairs(template) do
		keys[key] = true
	end

	if schema then
		for key in pairs(schema) do
			keys[key] = true
		end
	end

	local ordered = {}

	for key in pairs(keys) do
		table.insert(
			ordered,
			key
		)
	end

	table.sort(
		ordered,
		function(a, b)
			return tostring(a)
				< tostring(b)
		end
	)

	for _, key in ipairs(ordered) do
		root.Children[key] = buildSchemaNode(
			key,
			template[key],
			schema
				and schema[key]
				or nil
		)
	end

	return root
end

local function writeAny(
	writer,
	value,
	report,
	path
)
	local valueType = typeof(value)

	if value == nil then
		writer:WriteU8(0)

		return
	end

	if valueType == "boolean" then
		writer:WriteU8(1)
		writer:WriteBit(value)

		return
	end

	if valueType == "number" then
		writer:WriteU8(2)
		writer:WriteF64(value)

		return
	end

	if valueType == "string" then
		writer:WriteU8(3)
		writer:WriteString(value)

		return
	end

	if valueType == "table" then
		local array, count = isDenseArray(value)

		if array then
			writer:WriteU8(4)
			writer:WriteVarUInt(count)

			for index = 1, count do
				writeAny(
					writer,
					value[index],
					report,
					path
				)
			end

			return
		end

		writer:WriteU8(5)

		local keys = sortedKeys(value)

		writer:WriteVarUInt(#keys)

		for _, key in ipairs(keys) do
			writeAny(
				writer,
				key,
				report,
				path
			)

			writeAny(
				writer,
				value[key],
				report,
				path
			)
		end

		return
	end

	error(
		"Unsupported value type in Any codec: "
			.. valueType
	)
end

local function readAny(reader)
	local tag = reader:ReadU8()

	if tag == 0 then
		return nil
	end

	if tag == 1 then
		return reader:ReadBit()
	end

	if tag == 2 then
		return reader:ReadF64()
	end

	if tag == 3 then
		return reader:ReadString()
	end

	if tag == 4 then
		local count = reader:ReadVarUInt()
		local result = table.create(count)

		for index = 1, count do
			result[index] = readAny(reader)
		end

		return result
	end

	if tag == 5 then
		local count = reader:ReadVarUInt()
		local result = {}

		for _ = 1, count do
			local key = readAny(reader)
			local value = readAny(reader)

			result[key] = value
		end

		return result
	end

	error("Unknown Any codec tag")
end

local function addFieldReport(
	report,
	path,
	startBits,
	endBits,
	encoding
)
	if not report then
		return
	end

	table.insert(
		report.Fields,
		{
			Path = path,
			Bits = endBits - startBits,
			Encoding = encoding,
		}
	)
end

local encodeNode
local decodeNode

encodeNode = function(
	writer,
	node,
	value,
	report,
	path
)
	local startBits = writer.BitPosition
	local encoding = node.Encoding

	if node.Optional then
		local present = value ~= nil

		writer:WriteBit(present)

		if not present then
			addFieldReport(
				report,
				path,
				startBits,
				writer.BitPosition,
				"Optional"
			)

			return
		end
	end

	if node.OmitDefault then
		local differs = not deepEqual(
			value,
			node.Default
		)

		writer:WriteBit(differs)

		if not differs then
			addFieldReport(
				report,
				path,
				startBits,
				writer.BitPosition,
				"DefaultOmitted"
			)

			return
		end
	end

	if encoding == CODEC_BOOL then
		writer:WriteBit(
			value == true
		)
	elseif encoding == CODEC_UINT then
		writer:WriteVarUInt(value)
	elseif encoding == CODEC_SINT then
		writer:WriteVarInt(value)
	elseif encoding == CODEC_RANGE then
		local minimum = node.Min or 0
		local maximum = node.Max or minimum
		local range = maximum - minimum
		local bits = node.Bits
			or ceilLog2(range + 1)

		local normalized = value - minimum

		writer:WriteBits(
			normalized,
			bits
		)
	elseif encoding == CODEC_FLOAT32 then
		writer:WriteF32(value)
	elseif encoding == CODEC_FLOAT64 then
		writer:WriteF64(value)
	elseif encoding == CODEC_QUANTIZED then
		local minimum = node.Min or 0
		local maximum = node.Max or 1
		local bits = node.Bits or 8
		local steps = (2 ^ bits) - 1
		local alpha

		if maximum == minimum then
			alpha = 0
		else
			alpha = (
				value - minimum
			) / (
				maximum - minimum
			)
		end

		alpha = math.clamp(
			alpha,
			0,
			1
		)

		local encoded = math.floor(
			alpha * steps + 0.5
		)

		writer:WriteBits(
			encoded,
			bits
		)
	elseif encoding == CODEC_ENUM then
		local values = node.Values
			or {}

		local index

		for candidateIndex, candidate in ipairs(values) do
			if candidate == value then
				index = candidateIndex - 1
				break
			end
		end

		assert(
			index ~= nil,
			"Enum value not found for "
				.. path
		)

		local bits = ceilLog2(
			math.max(
				1,
				#values
			)
		)

		writer:WriteBits(
			index,
			bits
		)
	elseif encoding == CODEC_STRING then
		writer:WriteString(value)
	elseif encoding == CODEC_ARRAY then
		local count = #value

		writer:WriteVarUInt(count)

		for index = 1, count do
			local childNode = node.ArrayOf

			if childNode then
				encodeNode(
					writer,
					childNode,
					value[index],
					report,
					path
						.. "["
						.. index
						.. "]"
				)
			else
				writeAny(
					writer,
					value[index],
					report,
					path
				)
			end
		end
	elseif encoding == CODEC_MAP then
		if node.Children then
			local keys = {}

			for key in pairs(node.Children) do
				table.insert(
					keys,
					key
				)
			end

			table.sort(
				keys,
				function(a, b)
					return tostring(a)
						< tostring(b)
				end
			)

			for _, key in ipairs(keys) do
				local childPath

				if path == "$" then
					childPath = tostring(key)
				else
					childPath = path
						.. "."
						.. tostring(key)
				end

				encodeNode(
					writer,
					node.Children[key],
					value
						and value[key]
						or nil,
					report,
					childPath
				)
			end
		else
			local keys = sortedKeys(value)

			writer:WriteVarUInt(#keys)

			for _, key in ipairs(keys) do
				writeAny(
					writer,
					key,
					report,
					path
				)

				writeAny(
					writer,
					value[key],
					report,
					path
				)
			end
		end
	else
		writeAny(
			writer,
			value,
			report,
			path
		)
	end

	addFieldReport(
		report,
		path,
		startBits,
		writer.BitPosition,
		encoding
	)
end

decodeNode = function(
	reader,
	node
)
	if node.Optional then
		local present = reader:ReadBit()

		if not present then
			return nil
		end
	end

	if node.OmitDefault then
		local differs = reader:ReadBit()

		if not differs then
			return clone(node.Default)
		end
	end

	local encoding = node.Encoding

	if encoding == CODEC_BOOL then
		return reader:ReadBit()
	end

	if encoding == CODEC_UINT then
		return reader:ReadVarUInt()
	end

	if encoding == CODEC_SINT then
		return reader:ReadVarInt()
	end

	if encoding == CODEC_RANGE then
		local minimum = node.Min or 0
		local maximum = node.Max or minimum
		local range = maximum - minimum
		local bits = node.Bits
			or ceilLog2(range + 1)

		return minimum
			+ reader:ReadBits(bits)
	end

	if encoding == CODEC_FLOAT32 then
		return reader:ReadF32()
	end

	if encoding == CODEC_FLOAT64 then
		return reader:ReadF64()
	end

	if encoding == CODEC_QUANTIZED then
		local minimum = node.Min or 0
		local maximum = node.Max or 1
		local bits = node.Bits or 8
		local steps = (2 ^ bits) - 1
		local encoded = reader:ReadBits(bits)

		if steps == 0 then
			return minimum
		end

		local alpha = encoded / steps

		return minimum
			+ (
				maximum - minimum
			) * alpha
	end

	if encoding == CODEC_ENUM then
		local values = node.Values
			or {}

		local bits = ceilLog2(
			math.max(
				1,
				#values
			)
		)

		local index = reader:ReadBits(bits) + 1

		return values[index]
	end

	if encoding == CODEC_STRING then
		return reader:ReadString()
	end

	if encoding == CODEC_ARRAY then
		local count = reader:ReadVarUInt()
		local result = table.create(count)

		for index = 1, count do
			if node.ArrayOf then
				result[index] = decodeNode(
					reader,
					node.ArrayOf
				)
			else
				result[index] = readAny(
					reader
				)
			end
		end

		return result
	end

	if encoding == CODEC_MAP then
		if node.Children then
			local result = {}
			local keys = {}

			for key in pairs(node.Children) do
				table.insert(
					keys,
					key
				)
			end

			table.sort(
				keys,
				function(a, b)
					return tostring(a)
						< tostring(b)
				end
			)

			for _, key in ipairs(keys) do
				result[key] = decodeNode(
					reader,
					node.Children[key]
				)
			end

			return result
		end

		local count = reader:ReadVarUInt()
		local result = {}

		for _ = 1, count do
			local key = readAny(reader)
			local value = readAny(reader)

			result[key] = value
		end

		return result
	end

	return readAny(reader)
end

local function encodeCompressedPayload(
	rootSchema,
	data,
	withReport
)
	local writer = BitWriter.new(256)
	local report

	if withReport then
		report = {
			Fields = {},
			UsefulBits = 0,
			PhysicalBits = 0,
			Bytes = 0,
		}
	end

	encodeNode(
		writer,
		rootSchema,
		data,
		report,
		"$"
	)

	local payload, bits = writer:Finish()

	if report then
		report.UsefulBits = bits
		report.PhysicalBits = buffer.len(payload) * 8
		report.Bytes = buffer.len(payload)
	end

	return payload, bits, report
end

local function decodeCompressedPayload(
	rootSchema,
	payload,
	bitLength
)
	local reader = BitReader.new(
		payload,
		bitLength
	)

	return decodeNode(
		reader,
		rootSchema
	)
end

local function encodeCompressionRecord(
	store,
	session,
	release,
	withReport
)
	local payload, bitLength, report = encodeCompressedPayload(
		store.CompressionSchema,
		session.Data,
		withReport
	)

	local checksum = checksumBuffer(payload)

	local metadataWriter = Writer.new(128)

	metadataWriter:U32(CODEC_MAGIC)
	metadataWriter:U16(CODEC_VERSION)
	metadataWriter:U16(store.SchemaVersion)
	metadataWriter:U32(session.Revision + 1)
	metadataWriter:U32(bitLength)
	metadataWriter:U32(buffer.len(payload))
	metadataWriter:U32(checksum)
	metadataWriter:U32(os.time())

	local sessionBlock = {
		JobId = store.JobId,
		SessionId = session.SessionId,
		PlayerId = session.Player.UserId,
		ExpiresAt = os.time()
			+ store.Config.LockTimeout,
	}

	local sessionRaw = release
		and ""
		or HttpService:JSONEncode(
			sessionBlock
		)

	metadataWriter:U16(#sessionRaw)
	metadataWriter:String(sessionRaw)

	local metadata = metadataWriter:Finish()
	local output = buffer.create(
		buffer.len(metadata)
			+ buffer.len(payload)
	)

	buffer.copy(
		output,
		0,
		metadata,
		0,
		buffer.len(metadata)
	)

	buffer.copy(
		output,
		buffer.len(metadata),
		payload,
		0,
		buffer.len(payload)
	)

	if report then
		report.HeaderBytes = buffer.len(metadata)
		report.TotalBytes = buffer.len(output)
		report.TotalBits = buffer.len(output) * 8
		report.PayloadBits = bitLength
		report.PayloadBytes = buffer.len(payload)
		report.CompressionMode = "SchemaBitPacked"
	end

	return output, report
end

local function decodeCompressionRecord(
	store,
	raw
)
	local reader = Reader.new(raw)

	assert(
		reader:U32() == CODEC_MAGIC,
		"Invalid V6.2 codec magic"
	)

	assert(
		reader:U16() == CODEC_VERSION,
		"Unsupported V6.2 codec version"
	)

	local schemaVersion = reader:U16()
	local revision = reader:U32()
	local bitLength = reader:U32()
	local payloadBytes = reader:U32()
	local expectedChecksum = reader:U32()
	local updatedAt = reader:U32()
	local sessionLength = reader:U16()
	local sessionRaw = reader:String(
		sessionLength
	)

	local payload = buffer.create(
		payloadBytes
	)

	buffer.copy(
		payload,
		0,
		raw,
		reader.Position,
		payloadBytes
	)

	assert(
		checksumBuffer(payload)
			== expectedChecksum,
		"V6.2 codec checksum mismatch"
	)

	local data = decodeCompressedPayload(
		store.CompressionSchema,
		payload,
		bitLength
	)

	local session

	if sessionLength > 0 then
		session = HttpService:JSONDecode(
			sessionRaw
		)
	end

	return {
		Format = CODEC_VERSION,
		SchemaVersion = schemaVersion,
		Revision = revision,
		UpdatedAt = updatedAt,
		Data = data,
		Session = session,
	}
end

local function compareReports(
	rawBytes,
	compressedReport
)
	local rawBits = rawBytes * 8
	local encodedBits = compressedReport.TotalBits

	return {
		RawBytes = rawBytes,
		RawBits = rawBits,
		EncodedBytes = compressedReport.TotalBytes,
		EncodedBits = encodedBits,
		PayloadBits = compressedReport.PayloadBits,
		PayloadBytes = compressedReport.PayloadBytes,
		HeaderBytes = compressedReport.HeaderBytes,
		SavedBytes = math.max(
			0,
			rawBytes - compressedReport.TotalBytes
		),
		SavedBits = math.max(
			0,
			rawBits - encodedBits
		),
		Ratio = rawBytes > 0
			and compressedReport.TotalBytes / rawBytes
			or 1,
		SavingsPercent = rawBytes > 0
			and (
				1
				- compressedReport.TotalBytes / rawBytes
			) * 100
			or 0,
		Fields = compressedReport.Fields,
	}
end

function NexusDataStore:_BuildCompressionSchemaV620()
	self.CompressionSchema = CompressionSchema.Build(
		self.Template,
		self.Schema
	)

	return self.CompressionSchema
end

function NexusDataStore:GetCompressionSchema()
	return clone(
		self.CompressionSchema
	)
end

function NexusDataStore:_EncodeCompressedV620(
	data,
	withReport
)
	local valid, err = self:_ValidateData(data)

	if not valid then
		return nil, err
	end

	local fakeSession = {
		Data = data,
		Revision = 0,
		SessionId = "ENCODE",
		Player = {
			UserId = 0,
		},
	}

	local encoded, report = encodeCompressionRecord(
		self,
		fakeSession,
		true,
		withReport == true
	)

	return encoded, report
end

function NexusDataStore:_DecodeCompressedV620(
	raw
)
	local ok, record = pcall(
		decodeCompressionRecord,
		self,
		raw
	)

	if not ok then
		return nil, tostring(record)
	end

	return record.Data, record
end

function NexusDataStore:_GetCompressionReportV620(
	dataOrSession
)
	local data

	if typeof(dataOrSession) == "table"
		and dataOrSession.Store == self then
		data = dataOrSession.Data
	else
		data = dataOrSession
	end

	local valid, err = self:_ValidateData(data)

	if not valid then
		return nil, err
	end

	local rawRecord = {
		Format = FORMAT,
		SchemaVersion = self.SchemaVersion,
		Revision = 1,
		UpdatedAt = os.time(),
		CreatedAt = os.time(),
		Data = data,
		Session = nil,
	}

	local rawEncoded = encodeRecord(
		rawRecord
	)

	local fakeSession = {
		Data = data,
		Revision = 0,
		SessionId = "REPORT",
		Player = {
			UserId = 0,
		},
	}

	local _, compressedReport = encodeCompressionRecord(
		self,
		fakeSession,
		true,
		true
	)

	return compareReports(
		buffer.len(rawEncoded),
		compressedReport
	)
end

function NexusDataStore:_PrintCompressionReportV620(
	dataOrSession
)
	local report, err = self:GetCompressionReport(
		dataOrSession
	)

	if not report then
		warn(
			"[NexusDataStore] Compression report failed:",
			err
		)

		return nil, err
	end

	print(
		"NexusDataStore V6.2 Compression Report"
	)

	print(
		"Raw bytes:",
		report.RawBytes
	)

	print(
		"Encoded bytes:",
		report.EncodedBytes
	)

	print(
		"Raw bits:",
		report.RawBits
	)

	print(
		"Encoded bits:",
		report.EncodedBits
	)

	print(
		"Payload bits:",
		report.PayloadBits
	)

	print(
		"Savings:",
		string.format(
			"%.2f%%",
			report.SavingsPercent
		)
	)

	for _, field in ipairs(report.Fields or {}) do
		print(
			field.Path,
			field.Bits,
			field.Encoding
		)
	end

	return report
end

function NexusDataStore:_MeasureCompressedDataV620(
	data
)
	local report, err = self:GetCompressionReport(data)

	if not report then
		return nil, err
	end

	return {
		RecordBytes = report.EncodedBytes,
		RecordBits = report.EncodedBits,
		PayloadBytes = report.PayloadBytes,
		PayloadBits = report.PayloadBits,
		RawBytes = report.RawBytes,
		RawBits = report.RawBits,
		SavingsPercent = report.SavingsPercent,
		Ratio = report.Ratio,
		RemainingBytes = math.max(
			0,
			4194304 - report.EncodedBytes
		),
		PercentOfKeyLimit = (
			report.EncodedBytes / 4194304
		) * 100,
		Fields = report.Fields,
	}
end

function NexusDataStore._NewV620(config)
	local store = NexusDataStore._NewV61(config)

	store.Config.Compression = config.Compression ~= false
	store.Config.CompressionReports = config.CompressionReports == true

	store:_BuildCompressionSchema()

	return store
end

function NexusDataStore:_DecodeStoredV620(raw)
	if raw == nil then
		return nil
	end

	if self.Config.Compression then
		local ok, record = pcall(
			decodeCompressionRecord,
			self,
			raw
		)

		if ok then
			return record
		end
	end

	return self:_DecodeStoredV61(raw)
end

function NexusDataStore:_EncodeStoredV620(record)
	if not self.Config.Compression then
		return self:_EncodeStoredV61(record)
	end

	if not record
		or not record.Data then
		return nil,
			"INVALID_RECORD"
	end

	local fakePlayerId = record.Session
		and record.Session.PlayerId
		or 0

	local fakeSession = {
		Data = record.Data,
		Revision = (record.Revision or 1) - 1,
		SessionId = record.Session
			and record.Session.SessionId
			or "ENCODE",
		Player = {
			UserId = fakePlayerId,
		},
	}

	local release = record.Session == nil

	local ok, encoded, report = pcall(function()
		local output, compressionReport = encodeCompressionRecord(
			self,
			fakeSession,
			release,
			self.Config.CompressionReports
		)

		return output, compressionReport
	end)

	if not ok then
		return nil,
			"COMPRESSED_ENCODE_FAILED:"
			.. tostring(encoded)
	end

	self.Metrics.BytesEncoded += buffer.len(encoded)

	if report then
		self:_Fire(
			"CompressionReport",
			report
		)
	end

	return encoded
end

local CODEC_VERSION_V621 = 621
local MAX_SAFE_INTEGER_V621 = 9007199254740991

local function writeVarUIntToWriter(writer, value)
	assert(
		finiteNumber(value)
			and value >= 0
			and value % 1 == 0
			and value <= MAX_SAFE_INTEGER_V621,
		"VarUInt requires a safe non-negative integer"
	)

	repeat
		local byte = value % 128
		value = math.floor(value / 128)

		if value > 0 then
			byte += 128
		end

		writer:U8(byte)
	until value == 0
end

local function readVarUIntFromReader(reader)
	local result = 0
	local shift = 0

	while true do
		local byte = reader:U8()
		result += (byte % 128) * (2 ^ shift)

		if byte < 128 then
			break
		end

		shift += 7

		if shift > 56 then
			error("VarUInt exceeds supported range")
		end
	end

	return result
end

local function compactIdBytes(value)
	if typeof(value) ~= "string" then
		return nil
	end

	local compact = string.gsub(
		value,
		"-",
		""
	)

	if #compact ~= 32
		or not string.match(
			compact,
			"^[%da-fA-F]+$"
		) then
		return nil
	end

	local bytes = table.create(16)

	for index = 1, 32, 2 do
		bytes[#bytes + 1] = tonumber(
			string.sub(
				compact,
				index,
				index + 1
			),
			16
		)
	end

	return bytes
end

local function writeCompactId(writer, value)
	local bytes = compactIdBytes(value)

	if bytes then
		writer:U8(1)

		for _, byte in ipairs(bytes) do
			writer:U8(byte)
		end

		return
	end

	writer:U8(0)
	writeVarUIntToWriter(
		writer,
		#value
	)
	writer:String(value)
end

local function readCompactId(reader)
	local packed = reader:U8() == 1

	if not packed then
		local length = readVarUIntFromReader(
			reader
		)

		return reader:String(length)
	end

	local parts = table.create(16)

	for index = 1, 16 do
		parts[index] = string.format(
			"%02x",
			reader:U8()
		)
	end

	local compact = table.concat(parts)

	return table.concat({
		string.sub(compact, 1, 8),
		string.sub(compact, 9, 12),
		string.sub(compact, 13, 16),
		string.sub(compact, 17, 20),
		string.sub(compact, 21, 32),
	}, "-")
end

function BitWriter:WritePackedVarUInt(value)
	assert(
		finiteNumber(value)
			and value >= 0
			and value % 1 == 0
			and value <= MAX_SAFE_INTEGER_V621,
		"Packed VarUInt requires a safe non-negative integer"
	)

	repeat
		local byte = value % 128
		value = math.floor(value / 128)

		if value > 0 then
			byte += 128
		end

		self:WriteBits(
			byte,
			8
		)
	until value == 0
end

function BitWriter:WritePackedVarInt(value)
	assert(
		finiteNumber(value)
			and value % 1 == 0,
		"Packed VarInt requires an integer"
	)

	self:WritePackedVarUInt(
		zigZagEncode(value)
	)
end

function BitWriter:WritePackedString(value)
	assert(
		typeof(value) == "string"
			and utf8.len(value) ~= nil,
		"Packed string requires valid UTF-8"
	)

	self:WritePackedVarUInt(
		#value
	)

	self:AlignByte()
	self:_Ensure(#value * 8)

	buffer.writestring(
		self.Buffer,
		math.floor(self.BitPosition / 8),
		value
	)

	self.BitPosition += #value * 8
end

function BitReader:ReadPackedVarUInt()
	local result = 0
	local shift = 0

	while true do
		local byte = self:ReadBits(8)
		result += (byte % 128) * (2 ^ shift)

		if byte < 128 then
			break
		end

		shift += 7

		if shift > 56 then
			error("Packed VarUInt exceeds supported range")
		end
	end

	return result
end

function BitReader:ReadPackedVarInt()
	return zigZagDecode(
		self:ReadPackedVarUInt()
	)
end

function BitReader:ReadPackedString()
	local length = self:ReadPackedVarUInt()

	self:AlignByte()
	self:_Need(length * 8)

	local value = buffer.readstring(
		self.Buffer,
		math.floor(self.BitPosition / 8),
		length
	)

	self.BitPosition += length * 8

	return value
end

local function chooseDefaultEncodingV621(
	rule,
	defaultValue
)
	if rule
		and rule.Encoding then
		return typeCodeFromName(
			rule.Encoding
		)
	end

	if rule
		and rule.ArrayOf then
		return CODEC_ARRAY
	end

	if rule
		and rule.Children then
		return CODEC_MAP
	end

	local valueType = rule
		and rule.Type
		or typeof(defaultValue)

	if valueType == "boolean" then
		return CODEC_BOOL
	end

	if valueType == "number" then
		if rule
			and rule.Min ~= nil
			and rule.Max ~= nil
			and rule.Integer then
			return CODEC_RANGE
		end

		if rule
			and rule.Integer
			and (
				rule.Min == nil
					or rule.Min >= 0
			) then
			return CODEC_UINT
		end

		if rule
			and rule.Integer then
			return CODEC_SINT
		end

		return CODEC_FLOAT64
	end

	if valueType == "string" then
		if rule
			and (
				rule.Values
					or rule.Enum
			) then
			return CODEC_ENUM
		end

		return CODEC_STRING
	end

	if valueType == "table" then
		local array, count = isDenseArray(
			defaultValue
		)

		if array
			and count > 0 then
			return CODEC_ARRAY
		end

		return CODEC_MAP
	end

	return CODEC_ANY
end

local function buildSchemaNodeV621(
	key,
	defaultValue,
	rule,
	strict
)
	rule = rule or {}

	local node = {
		Key = key,
		Type = rule.Type
			or typeof(defaultValue),
		Encoding = chooseDefaultEncodingV621(
			rule,
			defaultValue
		),
		Required = rule.Required ~= false,
		Default = clone(defaultValue),
		Min = rule.Min,
		Max = rule.Max,
		Bits = rule.Bits,
		Values = rule.Values
			or rule.Enum,
		Children = nil,
		ArrayOf = nil,
		OmitDefault = rule.OmitDefault == true,
		Optional = rule.Optional == true
			or rule.Required == false,
		PreserveUnknown = rule.AllowUnknown ~= false
			and not strict,
	}

	if rule.Children
		or (
			typeof(defaultValue) == "table"
				and node.Encoding == CODEC_MAP
		) then
		local childRules = rule.Children or {}
		local childKeys = {}

		if typeof(defaultValue) == "table" then
			for childKey in pairs(defaultValue) do
				childKeys[childKey] = true
			end
		end

		for childKey in pairs(childRules) do
			childKeys[childKey] = true
		end

		local ordered = {}

		for childKey in pairs(childKeys) do
			table.insert(
				ordered,
				childKey
			)
		end

		table.sort(
			ordered,
			function(a, b)
				return tostring(a)
					< tostring(b)
			end
		)

		node.Children = {}

		for _, childKey in ipairs(ordered) do
			node.Children[childKey] = buildSchemaNodeV621(
				childKey,
				typeof(defaultValue) == "table"
					and defaultValue[childKey]
					or nil,
				childRules[childKey],
				strict
			)
		end
	end

	if rule.ArrayOf then
		node.ArrayOf = buildSchemaNodeV621(
			nil,
			nil,
			rule.ArrayOf,
			strict
		)
	end

	return node
end

local function buildCompressionSchemaV621(
	template,
	schema,
	strict
)
	local root = {
		Type = "table",
		Encoding = CODEC_MAP,
		Children = {},
		Default = clone(template),
		PreserveUnknown = not strict,
		Required = true,
		Optional = false,
		OmitDefault = false,
	}

	local keys = {}

	for key in pairs(template) do
		keys[key] = true
	end

	if schema then
		for key in pairs(schema) do
			keys[key] = true
		end
	end

	local ordered = {}

	for key in pairs(keys) do
		table.insert(
			ordered,
			key
		)
	end

	table.sort(
		ordered,
		function(a, b)
			return tostring(a)
				< tostring(b)
		end
	)

	for _, key in ipairs(ordered) do
		root.Children[key] = buildSchemaNodeV621(
			key,
			template[key],
			schema
				and schema[key]
				or nil,
			strict
		)
	end

	return root
end

local function schemaDescriptorV621(node)
	local descriptor = {
		Key = node.Key,
		Type = node.Type,
		Encoding = node.Encoding,
		Required = node.Required,
		Min = node.Min,
		Max = node.Max,
		Bits = node.Bits,
		Values = clone(node.Values),
		Optional = node.Optional,
		OmitDefault = node.OmitDefault,
		PreserveUnknown = node.PreserveUnknown,
		Default = node.OmitDefault
			and clone(node.Default)
			or nil,
	}

	if node.ArrayOf then
		descriptor.ArrayOf = schemaDescriptorV621(
			node.ArrayOf
		)
	end

	if node.Children then
		descriptor.Children = {}

		local keys = sortedKeys(
			node.Children
		)

		for _, key in ipairs(keys) do
			table.insert(
				descriptor.Children,
				{
					KeyType = typeof(key),
					Key = key,
					Node = schemaDescriptorV621(
						node.Children[key]
					),
				}
			)
		end
	end

	return descriptor
end

local function schemaHashV621(node)
	local encoded = encodeRecord(
		schemaDescriptorV621(node)
	)

	return checksumBuffer(encoded)
end

local function validateCompressionNodeV621(
	node,
	value,
	path,
	errors
)
	errors = errors or {}
	path = path or "$"

	if value == nil then
		if node.Optional
			or not node.Required then
			return errors
		end

		table.insert(
			errors,
			path .. ": required compressed value missing"
		)

		return errors
	end

	local encoding = node.Encoding

	if encoding == CODEC_BOOL then
		if typeof(value) ~= "boolean" then
			table.insert(
				errors,
				path .. ": Bit encoding requires boolean"
			)
		end
	elseif encoding == CODEC_UINT then
		if not finiteNumber(value)
			or value < 0
			or value % 1 ~= 0
			or value > MAX_SAFE_INTEGER_V621 then
			table.insert(
				errors,
				path .. ": VarUInt requires a safe non-negative integer"
			)
		end
	elseif encoding == CODEC_SINT then
		if not finiteNumber(value)
			or value % 1 ~= 0
			or math.abs(value) > MAX_SAFE_INTEGER_V621 / 2 then
			table.insert(
				errors,
				path .. ": VarInt requires a safe integer"
			)
		end
	elseif encoding == CODEC_RANGE then
		if node.Min == nil
			or node.Max == nil
			or node.Max < node.Min then
			table.insert(
				errors,
				path .. ": UIntRange requires valid Min and Max"
			)
		elseif not finiteNumber(value)
			or value % 1 ~= 0
			or value < node.Min
			or value > node.Max then
			table.insert(
				errors,
				path .. ": value is outside UIntRange"
			)
		else
			local needed = ceilLog2(
				node.Max - node.Min + 1
			)

			local bits = node.Bits
				or needed

			if bits < needed
				or bits > 53 then
				table.insert(
					errors,
					path .. ": UIntRange Bits cannot represent range"
				)
			end
		end
	elseif encoding == CODEC_FLOAT32
		or encoding == CODEC_FLOAT64 then
		if not finiteNumber(value) then
			table.insert(
				errors,
				path .. ": floating encoding requires finite number"
			)
		end
	elseif encoding == CODEC_QUANTIZED then
		local bits = node.Bits or 8

		if not finiteNumber(value)
			or node.Min == nil
			or node.Max == nil
			or node.Max < node.Min
			or value < node.Min
			or value > node.Max
			or bits < 1
			or bits > 53 then
			table.insert(
				errors,
				path .. ": invalid Quantized value or configuration"
			)
		end
	elseif encoding == CODEC_ENUM then
		local values = node.Values or {}
		local found = false

		for _, candidate in ipairs(values) do
			if deepEqual(
				candidate,
				value
				) then
				found = true
				break
			end
		end

		if #values == 0
			or not found then
			table.insert(
				errors,
				path .. ": value is not in Enum Values"
			)
		end
	elseif encoding == CODEC_STRING then
		if typeof(value) ~= "string"
			or utf8.len(value) == nil then
			table.insert(
				errors,
				path .. ": String encoding requires valid UTF-8"
			)
		end
	elseif encoding == CODEC_ARRAY then
		local array, count = isDenseArray(value)

		if not array then
			table.insert(
				errors,
				path .. ": Array encoding requires a dense array"
			)
		elseif node.ArrayOf then
			for index = 1, count do
				validateCompressionNodeV621(
					node.ArrayOf,
					value[index],
					path
						.. "["
						.. index
						.. "]",
					errors
				)
			end
		end
	elseif encoding == CODEC_MAP then
		if typeof(value) ~= "table" then
			table.insert(
				errors,
				path .. ": Map encoding requires table"
			)
		elseif node.Children then
			for key, childNode in pairs(node.Children) do
				local childPath = path == "$"
					and tostring(key)
					or path
					.. "."
					.. tostring(key)

				validateCompressionNodeV621(
					childNode,
					value[key],
					childPath,
					errors
				)
			end
		end
	end

	return errors
end

local function encodeNodeV621(
	writer,
	node,
	value,
	report,
	path
)
	local startBits = writer.BitPosition
	local encoding = node.Encoding

	if node.Optional then
		local present = value ~= nil

		writer:WriteBit(present)

		if not present then
			addFieldReport(
				report,
				path,
				startBits,
				writer.BitPosition,
				"Optional"
			)

			return
		end
	end

	if node.OmitDefault then
		local differs = not deepEqual(
			value,
			node.Default
		)

		writer:WriteBit(differs)

		if not differs then
			addFieldReport(
				report,
				path,
				startBits,
				writer.BitPosition,
				"DefaultOmitted"
			)

			return
		end
	end

	if encoding == CODEC_BOOL then
		writer:WriteBit(
			value == true
		)
	elseif encoding == CODEC_UINT then
		writer:WritePackedVarUInt(value)
	elseif encoding == CODEC_SINT then
		writer:WritePackedVarInt(value)
	elseif encoding == CODEC_RANGE then
		local bits = node.Bits
			or ceilLog2(
				node.Max - node.Min + 1
			)

		writer:WriteBits(
			value - node.Min,
			bits
		)
	elseif encoding == CODEC_FLOAT32 then
		writer:WriteF32(value)
	elseif encoding == CODEC_FLOAT64 then
		writer:WriteF64(value)
	elseif encoding == CODEC_QUANTIZED then
		local bits = node.Bits or 8
		local steps = (2 ^ bits) - 1
		local alpha = node.Max == node.Min
			and 0
			or (
				value - node.Min
			) / (
			node.Max - node.Min
		)

		local encoded = math.floor(
			math.clamp(alpha, 0, 1)
				* steps
				+ 0.5
		)

		writer:WriteBits(
			encoded,
			bits
		)
	elseif encoding == CODEC_ENUM then
		local index

		for candidateIndex, candidate in ipairs(node.Values or {}) do
			if deepEqual(
				candidate,
				value
				) then
				index = candidateIndex - 1
				break
			end
		end

		assert(
			index ~= nil,
			"Enum value not found at "
				.. path
		)

		writer:WriteBits(
			index,
			ceilLog2(
				math.max(
					1,
					#node.Values
				)
			)
		)
	elseif encoding == CODEC_STRING then
		writer:WritePackedString(value)
	elseif encoding == CODEC_ARRAY then
		writer:WritePackedVarUInt(#value)

		for index = 1, #value do
			if node.ArrayOf then
				encodeNodeV621(
					writer,
					node.ArrayOf,
					value[index],
					report,
					path
						.. "["
						.. index
						.. "]"
				)
			else
				writeAny(
					writer,
					value[index],
					report,
					path
				)
			end
		end
	elseif encoding == CODEC_MAP then
		if node.Children then
			local keys = sortedKeys(
				node.Children
			)

			for _, key in ipairs(keys) do
				local childPath = path == "$"
					and tostring(key)
					or path
					.. "."
					.. tostring(key)

				encodeNodeV621(
					writer,
					node.Children[key],
					value
						and value[key]
						or nil,
					report,
					childPath
				)
			end

			local extraKeys = {}

			if node.PreserveUnknown
				and typeof(value) == "table" then
				for key in pairs(value) do
					if node.Children[key] == nil then
						table.insert(
							extraKeys,
							key
						)
					end
				end

				table.sort(
					extraKeys,
					function(a, b)
						return tostring(a)
							< tostring(b)
					end
				)
			end

			writer:WritePackedVarUInt(
				#extraKeys
			)

			for _, key in ipairs(extraKeys) do
				writeAny(
					writer,
					key,
					report,
					path
				)

				writeAny(
					writer,
					value[key],
					report,
					path
				)
			end
		else
			local keys = sortedKeys(value)

			writer:WritePackedVarUInt(#keys)

			for _, key in ipairs(keys) do
				writeAny(
					writer,
					key,
					report,
					path
				)

				writeAny(
					writer,
					value[key],
					report,
					path
				)
			end
		end
	else
		writeAny(
			writer,
			value,
			report,
			path
		)
	end

	addFieldReport(
		report,
		path,
		startBits,
		writer.BitPosition,
		encoding
	)
end

local function decodeNodeV621(
	reader,
	node
)
	if node.Optional then
		if not reader:ReadBit() then
			return nil
		end
	end

	if node.OmitDefault then
		if not reader:ReadBit() then
			return clone(node.Default)
		end
	end

	local encoding = node.Encoding

	if encoding == CODEC_BOOL then
		return reader:ReadBit()
	end

	if encoding == CODEC_UINT then
		return reader:ReadPackedVarUInt()
	end

	if encoding == CODEC_SINT then
		return reader:ReadPackedVarInt()
	end

	if encoding == CODEC_RANGE then
		local bits = node.Bits
			or ceilLog2(
				node.Max - node.Min + 1
			)

		return node.Min
			+ reader:ReadBits(bits)
	end

	if encoding == CODEC_FLOAT32 then
		return reader:ReadF32()
	end

	if encoding == CODEC_FLOAT64 then
		return reader:ReadF64()
	end

	if encoding == CODEC_QUANTIZED then
		local bits = node.Bits or 8
		local steps = (2 ^ bits) - 1
		local encoded = reader:ReadBits(bits)

		if steps == 0 then
			return node.Min
		end

		return node.Min
			+ (
				node.Max - node.Min
			) * (
			encoded / steps
		)
	end

	if encoding == CODEC_ENUM then
		local index = reader:ReadBits(
			ceilLog2(
				math.max(
					1,
					#node.Values
				)
			)
		) + 1

		return node.Values[index]
	end

	if encoding == CODEC_STRING then
		return reader:ReadPackedString()
	end

	if encoding == CODEC_ARRAY then
		local count = reader:ReadPackedVarUInt()
		local result = table.create(count)

		for index = 1, count do
			if node.ArrayOf then
				result[index] = decodeNodeV621(
					reader,
					node.ArrayOf
				)
			else
				result[index] = readAny(
					reader
				)
			end
		end

		return result
	end

	if encoding == CODEC_MAP then
		if node.Children then
			local result = {}
			local keys = sortedKeys(
				node.Children
			)

			for _, key in ipairs(keys) do
				result[key] = decodeNodeV621(
					reader,
					node.Children[key]
				)
			end

			local extraCount = reader:ReadPackedVarUInt()

			for _ = 1, extraCount do
				local key = readAny(reader)
				local child = readAny(reader)

				result[key] = child
			end

			return result
		end

		local count = reader:ReadPackedVarUInt()
		local result = {}

		for _ = 1, count do
			local key = readAny(reader)
			local child = readAny(reader)

			result[key] = child
		end

		return result
	end

	return readAny(reader)
end

local function encodeCompressedPayloadV621(
	rootSchema,
	data,
	withReport
)
	local writer = BitWriter.new(256)
	local report

	if withReport then
		report = {
			Fields = {},
			UsefulBits = 0,
			PhysicalBits = 0,
			Bytes = 0,
		}
	end

	encodeNodeV621(
		writer,
		rootSchema,
		data,
		report,
		"$"
	)

	local payload, bits = writer:Finish()

	if report then
		report.UsefulBits = bits
		report.PhysicalBits = buffer.len(payload) * 8
		report.Bytes = buffer.len(payload)
	end

	return payload, bits, report
end

local function decodeCompressedPayloadV621(
	rootSchema,
	payload,
	bitLength
)
	return decodeNodeV621(
		BitReader.new(
			payload,
			bitLength
		),
		rootSchema
	)
end

local function encodeCompressionRecordV621(
	store,
	session,
	release,
	withReport
)
	local payload, bitLength, report = encodeCompressedPayloadV621(
		store.CompressionSchema,
		session.Data,
		withReport
	)

	local checksum = checksumBuffer(payload)
	local writer = Writer.new(128)

	writer:U32(CODEC_MAGIC)
	writer:U16(CODEC_VERSION_V621)
	writer:U16(store.SchemaVersion)
	writer:U32(store.CompressionSchemaHash)
	writer:U32(session.Revision + 1)
	writer:U32(bitLength)
	writer:U32(buffer.len(payload))
	writer:U32(checksum)
	writer:U32(os.time())
	writer:U32(
		session.CreatedAt
			or os.time()
	)

	if release then
		writer:U8(0)
	else
		writer:U8(1)
		writeCompactId(
			writer,
			store.JobId
		)
		writeCompactId(
			writer,
			session.SessionId
		)
		writeVarUIntToWriter(
			writer,
			session.Player.UserId
		)
		writer:U32(
			os.time()
				+ store.Config.LockTimeout
		)
	end

	local metadata = writer:Finish()
	local output = buffer.create(
		buffer.len(metadata)
			+ buffer.len(payload)
	)

	buffer.copy(
		output,
		0,
		metadata,
		0,
		buffer.len(metadata)
	)

	buffer.copy(
		output,
		buffer.len(metadata),
		payload,
		0,
		buffer.len(payload)
	)

	if report then
		report.HeaderBytes = buffer.len(metadata)
		report.TotalBytes = buffer.len(output)
		report.TotalBits = buffer.len(output) * 8
		report.PayloadBits = bitLength
		report.PayloadBytes = buffer.len(payload)
		report.CompressionMode = "SchemaBitPackedV621"
		report.SchemaHash = store.CompressionSchemaHash
	end

	return output, report
end

local function selectCompressionSchemaV621(
	store,
	schemaVersion,
	schemaHash
)
	local entry = store.CompressionSchemas[schemaVersion]

	if not entry then
		error(
			"MISSING_COMPRESSION_SCHEMA_VERSION:"
				.. tostring(schemaVersion)
		)
	end

	if schemaHash ~= nil
		and entry.Hash ~= schemaHash then
		error(
			"COMPRESSION_SCHEMA_HASH_MISMATCH:"
				.. tostring(schemaVersion)
		)
	end

	return entry.Schema
end

local function decodeCompressionRecordV621(
	store,
	raw
)
	local reader = Reader.new(raw)

	assert(
		reader:U32() == CODEC_MAGIC,
		"Invalid V6.2.1 codec magic"
	)

	assert(
		reader:U16() == CODEC_VERSION_V621,
		"Unsupported V6.2.1 codec version"
	)

	local schemaVersion = reader:U16()
	local schemaHash = reader:U32()
	local revision = reader:U32()
	local bitLength = reader:U32()
	local payloadBytes = reader:U32()
	local expectedChecksum = reader:U32()
	local updatedAt = reader:U32()
	local createdAt = reader:U32()
	local hasSession = reader:U8() == 1
	local session

	if hasSession then
		session = {
			JobId = readCompactId(reader),
			SessionId = readCompactId(reader),
			PlayerId = readVarUIntFromReader(reader),
			ExpiresAt = reader:U32(),
		}
	end

	local payload = buffer.create(
		payloadBytes
	)

	buffer.copy(
		payload,
		0,
		raw,
		reader.Position,
		payloadBytes
	)

	assert(
		checksumBuffer(payload)
			== expectedChecksum,
		"V6.2.1 codec checksum mismatch"
	)

	local compressionSchema = selectCompressionSchemaV621(
		store,
		schemaVersion,
		schemaHash
	)

	local data = decodeCompressedPayloadV621(
		compressionSchema,
		payload,
		bitLength
	)

	return {
		Format = CODEC_VERSION_V621,
		SchemaVersion = schemaVersion,
		SchemaHash = schemaHash,
		Revision = revision,
		UpdatedAt = updatedAt,
		CreatedAt = createdAt,
		Data = data,
		Session = session,
	}
end

local function decodeCompressionRecordV620Compat(
	store,
	raw
)
	local reader = Reader.new(raw)

	assert(
		reader:U32() == CODEC_MAGIC,
		"Invalid V6.2 codec magic"
	)

	assert(
		reader:U16() == CODEC_VERSION,
		"Unsupported V6.2 codec version"
	)

	local schemaVersion = reader:U16()
	local revision = reader:U32()
	local bitLength = reader:U32()
	local payloadBytes = reader:U32()
	local expectedChecksum = reader:U32()
	local updatedAt = reader:U32()
	local sessionLength = reader:U16()
	local sessionRaw = reader:String(
		sessionLength
	)

	local payload = buffer.create(
		payloadBytes
	)

	buffer.copy(
		payload,
		0,
		raw,
		reader.Position,
		payloadBytes
	)

	assert(
		checksumBuffer(payload)
			== expectedChecksum,
		"V6.2 codec checksum mismatch"
	)

	local entry = store.CompressionSchemas[schemaVersion]

	if not entry then
		error(
			"MISSING_COMPRESSION_SCHEMA_VERSION:"
				.. tostring(schemaVersion)
		)
	end

	local data = decodeCompressedPayload(
		entry.SchemaV620,
		payload,
		bitLength
	)

	local session

	if sessionLength > 0 then
		session = HttpService:JSONDecode(
			sessionRaw
		)
	end

	return {
		Format = CODEC_VERSION,
		SchemaVersion = schemaVersion,
		Revision = revision,
		UpdatedAt = updatedAt,
		Data = data,
		Session = session,
	}
end

function Session.new(
	store,
	player,
	key,
	data,
	revision,
	schemaVersion,
	sessionId
)
	local session = Session._NewV620(
		store,
		player,
		key,
		data,
		revision,
		schemaVersion,
		sessionId
	)

	session.ObservedSnapshot = clone(data)

	return session
end

function NexusDataStore:_BuildCompressionSchema()
	self.CompressionSchemas = {}

	local currentSchema = buildCompressionSchemaV621(
		self.Template,
		self.Schema,
		self.Strict
	)

	local currentHash = schemaHashV621(
		currentSchema
	)

	self.CompressionSchema = currentSchema
	self.CompressionSchemaHash = currentHash

	self.CompressionSchemas[self.SchemaVersion] = {
		Schema = currentSchema,
		SchemaV620 = CompressionSchema.Build(
			self.Template,
			self.Schema
		),
		Hash = currentHash,
		Strict = self.Strict,
	}

	for version, history in pairs(
		self.Config.CompressionHistory or {}
		) do
		assert(
			typeof(version) == "number"
				and version >= 1
				and version % 1 == 0,
			"CompressionHistory keys must be positive integer versions"
		)

		assert(
			typeof(history) == "table"
				and typeof(history.Data) == "table",
			"CompressionHistory entries require Data"
		)

		local historySchema = buildCompressionSchemaV621(
			history.Data,
			history.Schema,
			history.Strict == true
		)

		self.CompressionSchemas[version] = {
			Schema = historySchema,
			SchemaV620 = CompressionSchema.Build(
				history.Data,
				history.Schema
			),
			Hash = schemaHashV621(
				historySchema
			),
			Strict = history.Strict == true,
		}
	end

	return self.CompressionSchema
end

function NexusDataStore:_ValidateData(data)
	local ok, err, details = self:_ValidateDataV620(
		data
	)

	if not ok then
		return ok, err, details
	end

	if self.Config
		and self.Config.Compression
		and self.CompressionSchema then
		local compressionErrors = validateCompressionNodeV621(
			self.CompressionSchema,
			data,
			"$",
			{}
		)

		if #compressionErrors > 0 then
			self.Metrics.TypeErrors += 1

			return false,
				table.concat(
					compressionErrors,
					"\n"
				),
				{
					Nodes = details
					and details.Nodes
					or countNodes(data),
					Bytes = details
					and details.Bytes
					or estimateEncodedBytes(data),
					Errors = compressionErrors,
				}
		end
	end

	return true, nil, details
end

function NexusDataStore:_Touch(
	session,
	operation,
	path,
	before,
	after
)
	self:_TouchV620(
		session,
		operation,
		path,
		before,
		after
	)

	session.ObservedSnapshot = clone(
		session.Data
	)
end

function NexusDataStore:_DetectDirectChanges(
	session
)
	if not self.Config.DetectDirectChanges
		or not session:IsActive() then
		return false
	end

	local observed = session.ObservedSnapshot
		or session.LastPersistedSnapshot
		or clone(session.Data)

	if deepEqual(
		observed,
		session.Data
		) then
		return false
	end

	local current = clone(
		session.Data
	)

	local valid, err = self:_ValidateData(
		current
	)

	if not valid then
		session.Data = clone(observed)
		session.ObservedSnapshot = clone(observed)

		self:_Fire(
			"DirectMutationRejected",
			session,
			err
		)

		return false, err
	end

	local changes = diffTables(
		observed,
		current
	)

	session.Dirty = true
	session.LastTouchedAt = now()
	session.MutationId += 1

	local entry = {
		Id = session.MutationId,
		Operation = "DirectMutation",
		Path = "$",
		Before = clone(observed),
		After = clone(current),
		Changes = changes,
		Timestamp = os.time(),
	}

	table.insert(
		session.Journal,
		entry
	)

	while #session.Journal
		> self.Config.MaxJournalEntries do
		table.remove(
			session.Journal,
			1
		)
	end

	session.ObservedSnapshot = clone(current)

	self.Metrics.Mutations += 1

	self:_Fire(
		"DirectMutationDetected",
		session,
		changes,
		entry
	)

	for _, change in ipairs(changes) do
		local changePath = #change.Path > 0
			and pathToString(
				change.Path
			)
			or "$"

		self:_Fire(
			"DataChanged",
			session,
			changePath,
			change.Before,
			change.After,
			entry
		)
	end

	return true, changes
end

function NexusDataStore:_ResolveSession(
	playerOrSession
)
	if typeof(playerOrSession) == "table"
		and playerOrSession.Store == self then
		return playerOrSession
	end

	return self:GetSession(
		playerOrSession
	)
end

function NexusDataStore:OpenPlayerAsync(player)
	assert(
		player
			and player:IsA("Player"),
		"Player required"
	)

	if self.Closed
		or self.Closing then
		return nil,
			"STORE_CLOSED"
	end

	local existing = self.Sessions[player]

	if existing
		and existing:IsActive() then
		return existing
	end

	local key = makePlayerKey(player)
	local existingByKey = self.SessionByKey[key]

	if existingByKey
		and existingByKey:IsActive() then
		return existingByKey
	end

	local started = now()
	local loaded
	local lockedBy
	local decodeFailure

	local budgetOK = self:_WaitForBudget(
		Enum.DataStoreRequestType.UpdateAsync
	)

	if not budgetOK then
		return nil,
			"BUDGET_TIMEOUT"
	end

	local success, err = self:_Retry(function()
		self.DataStore:UpdateAsync(
			key,
			function(old)
				local record

				if old ~= nil then
					local decoded, decodeErr = self:_DecodeStored(old)

					if not decoded then
						decodeFailure = decodeErr

						return old
					end

					record = decoded
				end

				local currentTime = os.time()

				if record
					and record.Session then
					local expired = (record.Session.ExpiresAt or 0)
						<= currentTime

					if not expired then
						lockedBy = tostring(
							record.Session.JobId
						) .. ":"
							.. tostring(
								record.Session.SessionId
							)

						return old
					end

					self.Metrics.LocksRecovered += 1

					self:_Fire(
						"StaleSessionRecovered",
						key,
						record.Session
					)
				end

				local data = record
					and record.Data
					or clone(self.Template)

				local storedVersion = record
					and record.SchemaVersion
					or self.SchemaVersion

				local migrated, migrationErr = self:_ApplyMigrations(
					data,
					storedVersion
				)

				if not migrated then
					decodeFailure = migrationErr

					return old
				end

				local revision = (record
					and record.Revision
					or 0) + 1

				local sessionId = makeSessionId()

				loaded = {
					Data = clone(migrated),
					Revision = revision,
					SessionId = sessionId,
					CreatedAt = record
						and record.CreatedAt
						or currentTime,
				}

				local temporarySession = {
					Revision = revision - 1,
					Data = migrated,
					SessionId = sessionId,
					Player = player,
					CreatedAt = loaded.CreatedAt,
				}

				local nextRecord = self:_BuildRecord(
					temporarySession,
					false
				)

				nextRecord.Revision = revision

				local encoded, encodeErr = self:_EncodeStored(
					nextRecord
				)

				if not encoded then
					decodeFailure = encodeErr

					return old
				end

				return encoded
			end
		)
	end)

	self.Metrics.LoadTime += now() - started

	if not success then
		self.Metrics.LoadsFailed += 1

		self:_Fire(
			"PlayerLoadFailed",
			player,
			err
		)

		return nil, tostring(err)
	end

	if decodeFailure then
		self.Metrics.LoadsFailed += 1

		self:_Fire(
			"PlayerLoadFailed",
			player,
			decodeFailure
		)

		return nil, decodeFailure
	end

	if lockedBy then
		self.Metrics.LoadsFailed += 1

		return nil,
			"SESSION_LOCKED:"
			.. lockedBy
	end

	if not loaded then
		self.Metrics.LoadsFailed += 1

		return nil,
			"OPEN_FAILED"
	end

	local session = Session.new(
		self,
		player,
		key,
		loaded.Data,
		loaded.Revision,
		self.SchemaVersion,
		loaded.SessionId
	)

	session.CreatedAt = loaded.CreatedAt

	self:_RegisterSession(session)

	return session
end

function NexusDataStore:_AutoSaveLoop()
	while not self.Closed do
		task.wait(
			self.Config.AutoSaveInterval
		)

		if self.Closed then
			break
		end

		if self.Config.AutoSave then
			for _, session in pairs(self.Sessions) do
				if session:IsActive() then
					self:_DetectDirectChanges(
						session
					)

					if session.Dirty then
						self:_QueueSave(
							session,
							"normal",
							"autosave"
						)
					end
				end
			end
		end
	end
end


function NexusDataStore:_Commit(
	session,
	release,
	reason
)
	if session
		and session:IsActive() then
		self:_DetectDirectChanges(
			session
		)
	end

	local ok, err = self:_CommitV620(
		session,
		release,
		reason
	)

	if ok
		and not release
		and session
		and session:IsActive() then
		if not deepEqual(
			session.Data,
			session.LastPersistedSnapshot
			) then
			session.Dirty = true
			session.ObservedSnapshot = clone(
				session.Data
			)

			self:_QueueSave(
				session,
				"high",
				"changed-during-save"
			)
		else
			session.ObservedSnapshot = clone(
				session.Data
			)
		end
	end

	return ok, err
end

function NexusDataStore:SaveAsync(
	session,
	priority
)
	session = self:_ResolveSession(
		session
	)

	if not session
		or not session:IsActive() then
		return false,
			"SESSION_INACTIVE"
	end

	self:_DetectDirectChanges(
		session
	)

	if not session.Dirty then
		return true
	end

	local queued, err = self:_QueueSave(
		session,
		priority or "high",
		"manual"
	)

	if not queued then
		return false, err
	end

	local deadline = now()
		+ self.Config.SaveTimeout

	while now() < deadline do
		if not session:IsActive() then
			return false,
				"SESSION_INACTIVE"
		end

		if not session.Dirty then
			return true
		end

		task.wait(0.05)
	end

	return false,
		"SAVE_TIMEOUT"
end

function NexusDataStore:_DecodeStored(raw)
	if raw == nil then
		return nil
	end

	if typeof(raw) == "buffer"
		and buffer.len(raw) >= 6
		and buffer.readu32(raw, 0) == CODEC_MAGIC then
		local version = buffer.readu16(
			raw,
			4
		)

		local ok, record

		if version == CODEC_VERSION_V621 then
			ok, record = pcall(
				decodeCompressionRecordV621,
				self,
				raw
			)
		elseif version == CODEC_VERSION then
			ok, record = pcall(
				decodeCompressionRecordV620Compat,
				self,
				raw
			)
		else
			return nil,
				"UNSUPPORTED_COMPRESSION_VERSION:"
				.. tostring(version)
		end

		if ok then
			return record
		end

		return nil,
			"COMPRESSED_DECODE_FAILED:"
			.. tostring(record)
	end

	return self:_DecodeStoredV61(
		raw
	)
end

function NexusDataStore:_EncodeStored(record)
	if not self.Config.Compression then
		return self:_EncodeStoredV61(
			record
		)
	end

	if not record
		or not record.Data then
		return nil,
			"INVALID_RECORD"
	end

	local fakeSession = {
		Data = record.Data,
		Revision = (record.Revision or 1) - 1,
		CreatedAt = record.CreatedAt,
		SessionId = record.Session
			and record.Session.SessionId
			or "ENCODE",
		Player = {
			UserId = record.Session
				and record.Session.PlayerId
				or 0,
		},
	}

	local release = record.Session == nil

	local ok, encoded, report = pcall(function()
		local output, compressionReport = encodeCompressionRecordV621(
			self,
			fakeSession,
			release,
			self.Config.CompressionReports
		)

		return output, compressionReport
	end)

	if not ok then
		return nil,
			"COMPRESSED_ENCODE_FAILED:"
			.. tostring(encoded)
	end

	self.Metrics.BytesEncoded += buffer.len(
		encoded
	)

	if report then
		self:_Fire(
			"CompressionReport",
			report
		)
	end

	return encoded
end

function NexusDataStore:EncodeCompressed(
	data,
	withReport
)
	local valid, err = self:_ValidateData(
		data
	)

	if not valid then
		return nil, err
	end

	local fakeSession = {
		Data = data,
		Revision = 0,
		CreatedAt = os.time(),
		SessionId = "ENCODE",
		Player = {
			UserId = 0,
		},
	}

	local encoded, report = encodeCompressionRecordV621(
		self,
		fakeSession,
		true,
		withReport == true
	)

	return encoded, report
end

function NexusDataStore:DecodeCompressed(raw)
	local ok, record = pcall(
		decodeCompressionRecordV621,
		self,
		raw
	)

	if not ok then
		local fallbackOK, fallbackRecord = pcall(
			decodeCompressionRecordV620Compat,
			self,
			raw
		)

		if not fallbackOK then
			return nil,
				tostring(record)
		end

		record = fallbackRecord
	end

	return record.Data,
		record
end

function NexusDataStore:GetCompressionReport(
	dataOrSession
)
	local data

	if typeof(dataOrSession) == "table"
		and dataOrSession.Store == self then
		data = dataOrSession.Data
	else
		data = dataOrSession
	end

	local valid, err = self:_ValidateData(
		data
	)

	if not valid then
		return nil, err
	end

	local rawRecord = {
		Format = FORMAT,
		SchemaVersion = self.SchemaVersion,
		Revision = 1,
		UpdatedAt = os.time(),
		CreatedAt = os.time(),
		Data = data,
		Session = nil,
	}

	local rawEncoded = encodeRecord(
		rawRecord
	)

	local fakeSession = {
		Data = data,
		Revision = 0,
		CreatedAt = os.time(),
		SessionId = "REPORT",
		Player = {
			UserId = 0,
		},
	}

	local _, compressedReport = encodeCompressionRecordV621(
		self,
		fakeSession,
		true,
		true
	)

	return compareReports(
		buffer.len(rawEncoded),
		compressedReport
	)
end

function NexusDataStore:PrintCompressionReport(
	dataOrSession
)
	local report, err = self:GetCompressionReport(
		dataOrSession
	)

	if not report then
		warn(
			"[NexusDataStore] Compression report failed:",
			err
		)

		return nil, err
	end

	print(
		"NexusDataStore V6.2.1 Compression Report"
	)

	print(
		"Raw bytes:",
		report.RawBytes
	)

	print(
		"Encoded bytes:",
		report.EncodedBytes
	)

	print(
		"Raw bits:",
		report.RawBits
	)

	print(
		"Encoded bits:",
		report.EncodedBits
	)

	print(
		"Payload bits:",
		report.PayloadBits
	)

	print(
		"Savings:",
		string.format(
			"%.2f%%",
			report.SavingsPercent
		)
	)

	for _, field in ipairs(report.Fields or {}) do
		print(
			field.Path,
			field.Bits,
			field.Encoding
		)
	end

	return report
end

function NexusDataStore:MeasureCompressedData(
	data
)
	local report, err = self:GetCompressionReport(
		data
	)

	if not report then
		return nil, err
	end

	return {
		RecordBytes = report.EncodedBytes,
		RecordBits = report.EncodedBits,
		PayloadBytes = report.PayloadBytes,
		PayloadBits = report.PayloadBits,
		RawBytes = report.RawBytes,
		RawBits = report.RawBits,
		SavingsPercent = report.SavingsPercent,
		Ratio = report.Ratio,
		RemainingBytes = math.max(
			0,
			4194304 - report.EncodedBytes
		),
		PercentOfKeyLimit = (
			report.EncodedBytes / 4194304
		) * 100,
		Fields = report.Fields,
	}
end

function NexusDataStore.new(config: StoreConfig)
	assert(
		typeof(config) == "table",
		"Configuration table required"
	)

	if config.CompressionHistory ~= nil then
		assert(
			typeof(config.CompressionHistory) == "table",
			"CompressionHistory must be a table"
		)
	end

	local store = NexusDataStore._NewV620(
		config
	)

	store.Config.Compression = config.Compression ~= false
	store.Config.CompressionReports = config.CompressionReports == true
	store.Config.CompressionHistory = config.CompressionHistory or {}
	store.Config.DetectDirectChanges = config.DetectDirectChanges ~= false

	store:_BuildCompressionSchema()

	local templateOK, templateErr = store:_ValidateData(
		store.Template
	)

	assert(
		templateOK,
		"Invalid NexusDataStore template: "
			.. tostring(templateErr)
	)

	return store
end

function NexusDataStore:Open(player)
	return self:OpenPlayerAsync(
		player
	)
end

function NexusDataStore:Get(player)
	return self:GetSession(
		player
	)
end

function NexusDataStore:Wait(
	player,
	timeout
)
	return self:WaitForSession(
		player,
		timeout
	)
end

function NexusDataStore:Read(
	playerOrSession,
	path
)
	local session = self:_ResolveSession(
		playerOrSession
	)

	if not session
		or not session:IsActive() then
		return nil,
			"SESSION_NOT_FOUND"
	end

	return session:Get(path)
end

function NexusDataStore:Write(
	playerOrSession,
	path,
	value
)
	local session = self:_ResolveSession(
		playerOrSession
	)

	if not session
		or not session:IsActive() then
		return false,
			"SESSION_NOT_FOUND"
	end

	return session:Set(
		path,
		value
	)
end

function NexusDataStore:Add(
	playerOrSession,
	path,
	amount
)
	local session = self:_ResolveSession(
		playerOrSession
	)

	if not session
		or not session:IsActive() then
		return false,
			"SESSION_NOT_FOUND"
	end

	return session:Increment(
		path,
		amount
	)
end

function NexusDataStore:Sub(
	playerOrSession,
	path,
	amount
)
	return self:Add(
		playerOrSession,
		path,
		-(amount or 1)
	)
end

function NexusDataStore:Mutate(
	playerOrSession,
	callback
)
	local session = self:_ResolveSession(
		playerOrSession
	)

	if not session
		or not session:IsActive() then
		return false,
			"SESSION_NOT_FOUND"
	end

	return session:Transaction(
		callback
	)
end

function NexusDataStore:Save(
	playerOrSession,
	priority
)
	local session = self:_ResolveSession(
		playerOrSession
	)

	if not session then
		return false,
			"SESSION_NOT_FOUND"
	end

	return self:SaveAsync(
		session,
		priority
	)
end

function NexusDataStore:Release(
	playerOrSession
)
	local session = self:_ResolveSession(
		playerOrSession
	)

	if not session then
		return true
	end

	return self:ReleaseAsync(
		session
	)
end

function NexusDataStore:GetData(
	playerOrSession,
	copy
)
	local session = self:_ResolveSession(
		playerOrSession
	)

	if not session
		or not session:IsActive() then
		return nil,
			"SESSION_NOT_FOUND"
	end

	if copy == false then
		return session.Data
	end

	return clone(
		session.Data
	)
end

function Session:Read(path)
	return self:Get(path)
end

function Session:Write(
	path,
	value
)
	return self:Set(
		path,
		value
	)
end

function Session:Add(
	path,
	amount
)
	return self:Increment(
		path,
		amount
	)
end

function Session:Sub(
	path,
	amount
)
	return self:Increment(
		path,
		-(amount or 1)
	)
end

function Session:GetOr(
	path,
	fallback
)
	local value = getAt(
		self.Data,
		path
	)

	if value == nil then
		return clone(fallback)
	end

	return clone(value)
end

function Session:Toggle(path)
	local value = getAt(
		self.Data,
		path
	)

	if typeof(value) ~= "boolean" then
		return false,
			"NOT_BOOLEAN"
	end

	return self:Set(
		path,
		not value
	)
end

function Session:Append(
	path,
	value
)
	return self:Insert(
		path,
		value
	)
end

function Session:Award(
	path,
	amount
)
	assert(
		(amount or 0) >= 0,
		"Award amount must be non-negative"
	)

	return self:Increment(
		path,
		amount or 0
	)
end

function Session:Spend(
	path,
	amount
)
	amount = amount or 0

	if amount < 0 then
		return false,
			"INVALID_AMOUNT"
	end

	return self:Transaction(function(transaction)
		transaction:Require(
			path,
			function(value)
				return finiteNumber(value)
					and value >= amount
			end
		)

		transaction:Increment(
			path,
			-amount
		)
	end)
end

function Session:Mutate(callback)
	return self:Transaction(
		callback
	)
end

NexusDataStore.Compression = {
	Version = CODEC_VERSION_V621,
	BuildSchema = buildCompressionSchemaV621,
	BitWriter = BitWriter,
	BitReader = BitReader,
}

return NexusDataStore
