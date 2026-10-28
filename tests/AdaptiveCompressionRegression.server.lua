--!strict
-- Studio-only regression for adaptive payload selection and compact session locks.
-- Script belongs beside DataStore and Compression; DataStore needs PlayersData child.
-- No live DataStore reads or writes are performed.
local DataStore = require(script.Parent:WaitForChild("DataStore"))
local Compression = require(script.Parent:WaitForChild("Compression"))
local HttpService = game:GetService("HttpService")
local module = script.Parent:WaitForChild("Compression")

local fixture = {
    Coins = 123456,
    Enabled = true,
    Level = 12.5,
    Inventory = {},
    Repeated = string.rep("abcdefgh-abcdefgh-", 80),
}
for index = 1, 100 do
    fixture.Inventory[index] = "Potion"
end
local function newStore(name: string, extra: {[string]: any}): any
    local config: any = {Name = name, Template = fixture, Compression = true, CompressionModule = module, CompressionMinBytes = 0, AutoSave = false, AutoPlayerLifecycle = false, DetectDirectChanges = false}
    for key, value in pairs(extra) do config[key] = value end
    return DataStore.new(config)
end
local balanced = newStore("NexusBalancedRegression", {CompressionStrategy = "balanced"})
local smallest = newStore("NexusSmallestRegression", {CompressionStrategy = "smallest"})
assert(balanced:GetVersion() == "7.1.0")
assert(Compression.CodecVersion == 230 and Compression.Version() == "2.3.4")

local lock = {JobId = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa", SessionId = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb", HeartbeatAt = 1000, ExpiresAt = 1120}
local record = smallest:_BuildNewRecord(fixture)
record.Lock = lock
local legacy, legacyError = smallest:_EncodeRecord(record)
assert(legacy ~= nil, tostring(legacyError))
local legacyDecoded, oldError = smallest:_DecodeRecord(legacy)
assert(legacyDecoded and legacyDecoded.Lock.JobId == lock.JobId, tostring(oldError))

local compact = newStore("NexusCompactRegression", {CompressionStrategy = "smallest", CompactSessionLocks = true})
local compactStored, compactError, compactReport = compact:_EncodeRecord(record)
assert(compactStored ~= nil and compactReport.CompactLock == true, tostring(compactError))
local roundtrip, roundtripError = compact:_DecodeRecord(compactStored)
assert(roundtrip ~= nil and roundtrip.Lock.JobId == lock.JobId and roundtrip.Lock.SessionId == lock.SessionId, tostring(roundtripError))
assert(roundtrip.Lock.HeartbeatAt == 1000 and roundtrip.Lock.ExpiresAt == 1120)
assert(record.Lock.JobId == lock.JobId and record.Lock[1] == nil, "EncodeRecord mutated the source lock")
assert(roundtrip.Data.Coins == fixture.Coins and roundtrip.Data.Enabled == true and roundtrip.Data.Level == fixture.Level, "Scalar data changed")
assert(#roundtrip.Data.Inventory == #fixture.Inventory and roundtrip.Data.Inventory[100] == "Potion", "Inventory changed")
assert(roundtrip.Data.Repeated == fixture.Repeated, "Long string changed")

local noCodec = newStore("NexusRawCompactRegression", {Compression = false, CompactSessionLocks = true})
local rawCompact, rawError, rawReport = noCodec:_EncodeRecord(record)
assert(rawCompact ~= nil and rawReport.Transport == "raw-table", tostring(rawError))
assert(typeof(rawCompact.Lock) == "table" and rawCompact.Lock[1] == lock.JobId, "Compact lock not emitted")
local oldRawBytes = #HttpService:JSONEncode(record)
local newRawBytes = #HttpService:JSONEncode(rawCompact)
assert(newRawBytes < oldRawBytes, "Compact lock did not reduce raw serialized size")
local restored, restoreError = noCodec:_DecodeRecord(rawCompact)
assert(restored and restored.Lock.JobId == lock.JobId, tostring(restoreError))

local malformed = table.clone(record)
malformed.Lock = {lock.JobId, lock.SessionId, 1000}
local decodedBad, badError = compact:_DecodeRecord(malformed)
assert(decodedBad == nil and badError == "INVALID_COMPACT_RECORD_LOCK", "Malformed compact lock accepted")

local invalid = table.clone(record)
invalid.Lock = {JobId = "", SessionId = "valid", HeartbeatAt = 0, ExpiresAt = 1}
local rejected, rejectedError = compact:_EncodeRecord(invalid)
assert(rejected == nil and rejectedError == "INVALID_RECORD_LOCK", "Invalid lock was compacted")

local _, _, smallestReport = smallest:_EncodeRecord(record)
local _, _, balancedReport = balanced:_EncodeRecord(record)
assert(smallestReport and balancedReport, "Missing compression report")
assert(smallestReport.AlternativeCodecCandidates == 2)
assert(balancedReport.AlternativeCodecCandidates == 1)
assert(smallestReport.StorageBytes <= balancedReport.StorageBytes, "Size-first strategy selected a larger payload")

local packet = Compression.CompressTablePacket(record)
local restoredPacket = Compression.DecompressTable(packet)
assert(restoredPacket.Lock.SessionId == lock.SessionId, "Existing codec cannot read legacy lock")
for _, store in ipairs({balanced, smallest, compact, noCodec}) do assert(store:CloseAsync()) end
print(("NexusDataStore v7.1.0 adaptive compression PASS: lock %d -> %d JSON bytes"):format(oldRawBytes, newRawBytes))
