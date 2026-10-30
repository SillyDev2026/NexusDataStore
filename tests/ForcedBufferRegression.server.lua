--!strict
-- Roblox Studio server regression for opt-in forced buffer persistence.
-- Place this Script beside DataStore and Compression; DataStore requires PlayersData child.
-- All persistence uses an in-memory mock; no live player keys are accessed.
local DataStore = require(script.Parent:WaitForChild("DataStore"))
local Compression = script.Parent:WaitForChild("Compression")
local template = {Coins = 0, Collected = 0}

local function newStore(name: string, overrides: {[string]: any}): any
    local config: any = {
        Name = name,
        Template = template,
        Compression = true,
        CompressionModule = Compression,
        CompressionStrategy = "smallest",
        CompressionMinBytes = 512,
        CompressionTransport = "buffer",
        AutoSave = false,
        AutoPlayerLifecycle = false,
        DetectDirectChanges = false,
        BudgetAware = false,
        RetryAttempts = 1,
    }
    for key, value in pairs(overrides) do config[key] = value end
    return DataStore.new(config)
end

local normal = newStore("NexusBufferRegressionRaw", {})
local forced = newStore("NexusBufferRegressionForced", {ForceCompressedBuffer = true, CompressionReports = true})
local record = normal:_BuildNewRecord(template)

local raw, rawError, rawReport = normal:_EncodeRecord(record)
assert(raw ~= nil, tostring(rawError))
assert(rawReport.PersistedCompressed == false and rawReport.SelectionReason == "below-minimum-bytes")
assert(rawReport.Transport == "raw-table", "Legacy automatic raw fallback changed")

local encoded, encodeError, report = forced:_EncodeRecord(record)
assert(encoded ~= nil, tostring(encodeError))
assert(encoded.Compressed == true and encoded.Encoding == "buffer", "Forced mode did not select buffer")
assert(typeof(encoded.Payload) == "buffer", "Persisted payload is not a buffer")
assert(report.PersistedCompressed == true and report.ForcedBuffer == true)
assert(report.SelectionReason == "forced-buffer", "Missing forced-buffer diagnostics")
assert(report.Transport == "buffer" and report.StorageBytes > 0)
assert(forced.Config.CompressionMinBytes == 512, "Forced mode should preserve config threshold for diagnostics")

local decoded, decodeError = forced:_DecodeRecord(encoded)
assert(decoded ~= nil, tostring(decodeError))
assert(decoded.Data.Coins == 0 and decoded.Data.Collected == 0, "Forced buffer roundtrip changed data")

local legacyDecoded, legacyError = forced:_DecodeRecord(raw)
assert(legacyDecoded ~= nil and legacyDecoded.Data.Coins == 0, tostring(legacyError))
local crossDecoded, crossError = normal:_DecodeRecord(encoded)
assert(crossDecoded ~= nil and crossDecoded.Data.Collected == 0, tostring(crossError))

local forecast, forecastError = forced:GetCompressionReport(template)
assert(forecast ~= nil, tostring(forecastError))
assert(forecast.Transport == "buffer" and forecast.PersistedCompressed, "Forecast and persistence diverged")

local oldLimit = forced.Config.MaxStoredBytes
forced.Config.MaxStoredBytes = report.StorageBytes - 1
local oversized, oversizedError = forced:_EncodeRecord(record)
assert(oversized == nil and string.find(tostring(oversizedError), "STORED_BYTES_EXCEEDED", 1, true), "Forced mode incorrectly fell back to raw on limit")
forced.Config.MaxStoredBytes = oldLimit

local function assertBadConfig(name: string, changes: {[string]: any})
    local ok = pcall(function() newStore(name, changes) end)
    assert(not ok, "Unsafe forced buffer configuration was accepted: " .. name)
end

assertBadConfig("NexusForceNoCompression", {ForceCompressedBuffer = true, Compression = false})
assertBadConfig("NexusForceBase64", {ForceCompressedBuffer = true, CompressionTransport = "base64"})
assertBadConfig("NexusForceAutoTransport", {ForceCompressedBuffer = true, CompressionTransport = "auto"})
assertBadConfig("NexusForceWrongType", {ForceCompressedBuffer = "yes"})
assertBadConfig("NexusForceInvalidThreshold", {ForceCompressedBuffer = true, CompressionMinBytes = -2})

local stored: any = raw
local writes = 0
forced.DataStore = {
    UpdateAsync = function(_self, key, transform)
        assert(key == "Test_42")
        local updated = transform(stored)
        if updated ~= nil then stored = updated end
        writes += 1
        return stored
    end,
}
local session, openError = forced:OpenAsync("Test_42")
assert(session ~= nil, tostring(openError))
assert(stored.Compressed == true and stored.Encoding == "buffer", "Legacy raw data was not re-encoded at open")
assert(session:Get("Coins") == 0)
assert(session:Set("Coins", 99))
local saved, saveError = session:SaveAsync("critical")
assert(saved, tostring(saveError))
assert(stored.Compressed == true and typeof(stored.Payload) == "buffer", "SaveAsync did not persist a buffer")
local savedRecord, savedError = forced:_DecodeRecord(stored)
assert(savedRecord ~= nil and savedRecord.Data.Coins == 99, tostring(savedError))
local released, releaseError = session:ReleaseAsync()
assert(released, tostring(releaseError))
assert(stored.Compressed == true and typeof(stored.Payload) == "buffer", "Release reverted the buffer format")
local releasedRecord, releasedError = forced:_DecodeRecord(stored)
assert(releasedRecord and releasedRecord.Lock == nil and releasedRecord.Data.Coins == 99, tostring(releasedError))
assert(writes >= 3)
assert(normal:CloseAsync())
assert(forced:CloseAsync())
print("NexusDataStore forced buffer persistence regression PASS")
