--!strict
-- Studio-only v7.6 encoder integration. No live DataStore writes.
-- Place beside DataStore, Compression, and PlayersData (under DataStore).
local DataStore = require(script.Parent:WaitForChild("DataStore"))
local Compression = require(script.Parent:WaitForChild("Compression"))
local flags = {}
for index = 1, 64 do flags[index] = index % 3 == 0 end
local template = {Flags = flags, Coins = 3, Level = 1}

local function makeStore(name: string, compact: boolean): any
    return DataStore.new({
        Name = name,
        Template = template,
        Compression = true,
        CompressionMinBytes = 0,
        CompressionTransport = "buffer",
        CompressionStrategy = "smallest",
        CompressionOptions = {CompactEncoding = compact, StringDictionary = false},
        BudgetAware = false,
        AutoSave = false,
        DetectDirectChanges = false,
    })
end

local oldStore = makeStore("NexusCodec230Regression", false)
local newStore = makeStore("NexusCodec231Regression", true)
local record = newStore:_BuildNewRecord(template)
local old, oldErr, oldReport = oldStore:_EncodeRecord(record)
local compact, compactErr, compactReport = newStore:_EncodeRecord(record)
assert(old and compact and oldReport and compactReport, "Encoding failed: " .. tostring(oldErr or compactErr))
assert(old.Compressed == true and old.Codec == 230, "Legacy packet must remain codec 230")
assert(compact.Compressed == true and compact.Codec == 231, "Compact packet must use codec 231")
assert(compactReport.StorageBytes <= oldReport.StorageBytes, "Compact packet grew for Boolean-heavy data")

local decodedOld, decodeOldErr = newStore:_DecodeRecord(old)
local decodedCompact, decodeCompactErr = oldStore:_DecodeRecord(compact)
assert(decodedOld and decodedCompact, "Cross-format decoding failed: " .. tostring(decodeOldErr or decodeCompactErr))
assert(decodedOld.Data.Coins == 3 and decodedCompact.Data.Coins == 3)
for index = 1, 64 do
    assert(decodedOld.Data.Flags[index] == flags[index])
    assert(decodedCompact.Data.Flags[index] == flags[index])
end
local tampered = table.clone(compact)
tampered.Codec = 230
local bad, badErr = newStore:_DecodeRecord(tampered)
assert(bad == nil and badErr == "COMPRESSED_ENVELOPE_CODEC_MISMATCH", "Codec envelope mismatch was accepted")

local legacyPacket = Compression.CompressTablePacket(template, {CompactEncoding = false})
local compactPacket = Compression.CompressTablePacket(template, {CompactEncoding = true})
assert(buffer.readu16(legacyPacket, 4) == 230 and buffer.readu16(compactPacket, 4) == 231)
assert(Compression.DecompressTable(compactPacket).Flags[64] == flags[64])
assert(oldStore:CloseAsync() and newStore:CloseAsync())
print(("NexusDataStore v8.4.2 record codec regression PASS: %d -> %d record bytes"):format(oldReport.StorageBytes, compactReport.StorageBytes))
