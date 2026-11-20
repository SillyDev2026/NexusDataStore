--!strict
-- Portable v9 tests exercise the real selector, codec dispatch, and read-only history APIs.
local v9Passed, v9Failed = 0, 0
local function v9Test(name, callback)
	local ok, err = pcall(callback)
	if ok then v9Passed += 1; print("PASS", name) else v9Failed += 1; print("FAIL", name, err) end
end

local function v9MockStore()
	local record = {Format = 700, SchemaVersion = 1, Revision = 3, CreatedAt = 100, UpdatedAt = 200, Data = {Coins = 51}}
	local legacy = {CodecVersion = 230, CompactCodecVersion = 231, PackedCodecVersion = 232, RunLengthCodecVersion = 233}
	legacy.CompressTablePacket = function()
		return buffer.create(80), {CodecVersion = 230, EncodedBytes = 80}
	end
	legacy.DecompressTable = function()
		return table.clone(record)
	end
	local modern = {}
	modern.CompressTablePacket = function()
		return {Data = buffer.create(5), Codec = "ModernMock"}
	end
	modern.DecompressTable = function()
		return table.clone(record)
	end
	local store = setmetatable({
		Closed = false,
		Config = {
			KeyPrefix = "", LoadTimeout = 30, Compression = true, CompressionPolicy = "adaptive",
			CompressionMinBytes = 0, CompressionTransport = "buffer", CompressionStrategy = "balanced",
			CompressionOptions = {}, ModernCompressionOptions = {}, EnableModernCompression = true,
			MaxStoredBytes = 3900000, CompactSessionLocks = false, ForceCompressedBuffer = false,
		},
		CompressionEngine = legacy, ModernCompressionEngine = modern, ModernCompressionEngineVersion = "2.6.5",
	}, DataStore)
	store._MeasureStoredValue = function(_, value)
		if value.Compressed then return 40 + buffer.len(value.Payload) end
		return 200
	end
	return store
end

v9Test("Modern 250 wins without modifying the old record format", function()
	local store = v9MockStore()
	local encoded, err, report = store:_EncodeRecord({Data = {Coins = 51}})
	assert(encoded, tostring(err))
	assert(encoded.Format == 700 and encoded.Codec == 250 and encoded.Compressed == true)
	assert(report.SelectedCodec == 250 and report.EngineVersion == "2.6.5")
	local decoded, decodeErr = store:_DecodeRecord(encoded)
	assert(decoded and decoded.Data.Coins == 51, tostring(decodeErr))
end)

v9Test("Disabling modern writes preserves the v8 codec selector", function()
	local store = v9MockStore()
	store.Config.EnableModernCompression = false
	local encoded, err, report = store:_EncodeRecord({Data = {Coins = 51}})
	assert(encoded and encoded.Codec == 230, tostring(err))
	assert(report.SelectedCodec == 230)
end)

v9Test("Modern decoder is required even when modern writes are off", function()
	local store = v9MockStore()
	store.Config.EnableModernCompression = false
	store.ModernCompressionEngine = nil
	local decoded, err = store:_DecodeRecord({Format = 700, Codec = 250, Compressed = true, Encoding = "buffer", Payload = buffer.create(4)})
	assert(decoded == nil and string.find(tostring(err), "MODERN_COMPRESSION_UNAVAILABLE", 1, true) == 1)
end)

v9Test("Historical list rejects invalid bounds and returns detached summaries", function()
	local store = v9MockStore()
	Enum.SortDirection = {Descending = "Descending"}
	store._Retry = function(_, callback) return pcall(callback) end
	store.DataStore = {
		ListVersionsAsync = function(_, key, direction, _, _, limit)
			assert(key == "1234" and direction == "Descending" and limit == 2)
			return {GetCurrentPage = function() return {{Version = "v2", CreatedTime = 2}, {Version = "v1", CreatedTime = 1}} end}
		end,
	}
	local invalid, reason = store:ListVersionsAsync(1234, 101)
	assert(invalid == nil and reason == "INVALID_VERSION_LIMIT")
	local listed, err = store:ListVersionsAsync(1234, 2)
	assert(listed and #listed == 2 and listed[1].Version == "v2", tostring(err))
end)

v9Test("Historical record reading never acquires a player lock", function()
	local store = v9MockStore()
	store._Retry = function(_, callback) return pcall(callback) end
	local calls = 0
	store.DataStore = {
		GetVersionAsync = function(_, key, version)
			assert(key == "77" and version == "v1")
			calls += 1
			return {Format = 700, SchemaVersion = 1, Revision = 9, CreatedAt = 100, UpdatedAt = 200, Data = {Coins = 88}}
		end,
	}
	local data, info = store:GetVersionAsync(77, "v1")
	assert(data and data.Coins == 88 and info.Revision == 9 and calls == 1)
	data.Coins = 1
	assert(store:GetVersionAsync(77, "") == nil and calls == 1)
end)

print(string.format("v9 portable regression tests: %d passed, %d failed", v9Passed, v9Failed))
assert(v9Failed == 0, "v9 regressions failed")
