--!strict
-- Studio-only: no live DataStore keys. Requires DataStore with PlayersData and Compression modules.
local DataStore = require(script.Parent:WaitForChild("DataStore"))
local Compression = require(script.Parent:WaitForChild("Compression"))
local HttpService = game:GetService("HttpService")

local numbers = {}
for index = 1, 256 do numbers[index] = index % 4 - 2 end
local template = {Numbers = numbers, Coins = 5, Enabled = true}
local function makeStore(name: string, packed: boolean): any
    return DataStore.new({
        Name = name,
        Template = template,
        Compression = true,
        CompressionPolicy = "always-smallest",
        CompressionTransport = "buffer",
        CompressionMinBytes = 0,
        CompressionOptions = {BitPackedIntegers = packed, StringDictionary = false},
        AutoSave = false,
        BudgetAware = false,
        DetectDirectChanges = false,
    })
end
local legacy = makeStore("NexusPackedV78Legacy", false)
local compact = makeStore("NexusPackedV78OptIn", true)
local record = compact:_BuildNewRecord(template)
local legacyStored, oldErr, oldReport = legacy:_EncodeRecord(record)
local packedStored, packedErr, packedReport = compact:_EncodeRecord(record)
assert(legacyStored and packedStored, tostring(oldErr or packedErr))
assert(packedStored.Compressed == true and packedStored.Codec == 232, "Packed codec was not selected")
assert(packedReport.AlternativeCodecCandidates == 6 and oldReport.AlternativeCodecCandidates == 4)
assert(packedReport.StorageBytes < oldReport.StorageBytes, "Packed storage did not reduce record bytes")
assert(packedReport.PackedIntegerValues == 256 and packedReport.PackedIntegerValueBits == 768)
local decoded, decodeErr = legacy:_DecodeRecord(packedStored)
assert(decoded, tostring(decodeErr))
assert(decoded.Data.Coins == 5 and #decoded.Data.Numbers == 256)
for i = 1, 256 do assert(decoded.Data.Numbers[i] == numbers[i]) end

local forecast, forecastErr = compact:GetStorageForecast(template)
assert(forecast, tostring(forecastErr))
assert(forecast.SelectedCodec == 232 and forecast.CandidatesChecked == 6)
assert(forecast.PackedIntegerValues == 256 and forecast.PackedIntegerValueBits == 768)

local modified = table.clone(packedStored)
modified.Codec = 231
local bad, badErr = compact:_DecodeRecord(modified)
assert(bad == nil and badErr == "COMPRESSED_ENVELOPE_CODEC_MISMATCH", "Codec metadata mismatch not rejected")

local originalPacket = Compression.CompressTablePacket(template, {BitPackedIntegers = true})
assert(buffer.readu16(originalPacket, 4) == 232)
local data = Compression.DecompressTable(originalPacket, {BitPackedIntegers = false})
assert(data.Numbers[1] == numbers[1] and data.Numbers[256] == numbers[256], "Decoder must detect version from packet")
local oldPacket = Compression.CompressTablePacket(template, {CompactEncoding = true})
assert(buffer.readu16(oldPacket, 4) == 231)
assert(Compression.DecompressTable(oldPacket).Numbers[256] == numbers[256])
assert(legacy:CloseAsync() and compact:CloseAsync())
print(("NexusDataStore v7.8.0 bitpack regression PASS: %d -> %d bytes"):format(oldReport.StorageBytes, packedReport.StorageBytes))
