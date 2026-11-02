--!strict
-- Studio-only mock backend. Place beside DataStore, Compression; PlayersData beneath DataStore.
local DataStore = require(script.Parent:WaitForChild("DataStore"))
local Compression = require(script.Parent:WaitForChild("Compression"))

local inventory, counters, flags = {}, {}, {}
for index = 1, 256 do
    inventory[index] = index <= 128 and "Potion" or "Sword"
    counters[index] = 0
    flags[index] = true
end
local fixture = {Coins = 5, Inventory = inventory, Counters = counters, Flags = flags}
local function makeStore(name: string, enableRLE: boolean): any
    return DataStore.new({
        Name = name, Template = fixture, Compression = true,
        CompressionPolicy = "always-smallest", CompressionTransport = "buffer",
        CompressionMinBytes = 0,
        CompressionOptions = {BitPackedIntegers = true, RunLengthArrays = enableRLE, StringDictionary = true},
        AutoSave = false, BudgetAware = false, DetectDirectChanges = false, RetryAttempts = 1,
    })
end

local baseline = makeStore("NexusV79NoRLE", false)
local improved = makeStore("NexusV79WithRLE", true)
local record = improved:_BuildNewRecord(fixture)
local oldRecord, oldErr, oldReport = baseline:_EncodeRecord(record)
local newRecord, newErr, newReport = improved:_EncodeRecord(record)
assert(oldRecord and newRecord and oldReport and newReport, tostring(oldErr or newErr))
assert(newRecord.Compressed and newRecord.Codec == 233, "Expected RLE record codec")
assert(newReport.AlternativeCodecCandidates == 8 and newReport.RunLengthArrays >= 1, "RLE candidates/metrics absent")
assert(newReport.StorageBytes < oldReport.StorageBytes, "RLE did not improve repeated-array record")
local crossDecoded, decodeErr = baseline:_DecodeRecord(newRecord)
assert(crossDecoded and crossDecoded.Data.Coins == 5 and #crossDecoded.Data.Inventory == 256, tostring(decodeErr))
for index = 1, 256 do
    assert(crossDecoded.Data.Inventory[index] == inventory[index])
    assert(crossDecoded.Data.Counters[index] == counters[index])
    assert(crossDecoded.Data.Flags[index] == flags[index])
end
local forecast, forecastErr = improved:GetStorageForecast(fixture)
assert(forecast and forecast.SelectedCodec == 233 and forecast.RunLengthValues >= 256, tostring(forecastErr))

-- Real OpenAsync/SaveAsync/ReleaseAsync through a mock UpdateAsync backend.
local persisted: any = record
local writes = 0
improved.DataStore = {
    UpdateAsync = function(_self, key, transform)
        assert(key == "player_1")
        local nextRecord = transform(persisted)
        if nextRecord ~= nil then persisted = nextRecord; writes += 1 end
        return persisted
    end,
    GetAsync = function(_self, _key)
        return persisted
    end,
}
local profile, openErr = improved:OpenAsync("player_1")
assert(profile, tostring(openErr))
assert(persisted.Compressed and persisted.Codec == 233)
assert(profile:Award("Coins", 25))
local saved, saveErr = profile:SaveAsync("critical")
assert(saved, tostring(saveErr))
assert(persisted.Compressed and persisted.Codec == 233)
local afterSave, afterSaveErr = baseline:_DecodeRecord(persisted)
assert(afterSave and afterSave.Data.Coins == 30, tostring(afterSaveErr))
local released, releaseErr = profile:ReleaseAsync()
assert(released and persisted.Compressed and persisted.Codec == 233, tostring(releaseErr))
assert(writes >= 3, "Insufficient mock persistence round trips")
assert(baseline:CloseAsync() and improved:CloseAsync())
print(("NexusDataStore v8.0.0 RLE Studio mock PASS: stored bytes %d -> %d"):format(oldReport.StorageBytes, newReport.StorageBytes))
