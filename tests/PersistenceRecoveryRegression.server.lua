--!strict
-- Studio server regression: simulated backend commits, dropped acknowledgements, codec integration.
-- Put this Script beside DataStore and Compression; DataStore has a PlayersData child.
-- No external DataStore keys are read or written.
local DataStore = require(script.Parent:WaitForChild("DataStore"))
local compression = script.Parent:WaitForChild("Compression")
local store: any = DataStore.new({
    Name = "NexusPersistenceRecoveryRegression",
    Template = {Coins = 0, Blob = ""},
    Compression = true,
    CompressionModule = script.Parent:WaitForChild("Compression"),
    CompressionMinBytes = 512,
    AutoSave = false,
    AutoPlayerLifecycle = false,
    DetectDirectChanges = false,
    BudgetAware = false,
    RetryAttempts = 1,
})
assert(store:GetVersion() == "7.1.0")
assert(compression.Version() == "2.3.4")
local stored: any = nil
local failNextAcknowledgement = false
local uncachedReads = 0
local updates = 0
store.DataStore = {
    UpdateAsync = function(_self, key, transform)
        assert(key == "User_42")
        updates += 1
        local nextValue = transform(stored)
        if nextValue ~= nil then stored = nextValue end
        if failNextAcknowledgement then
            failNextAcknowledgement = false
            error("INJECTED_LOST_ACKNOWLEDGEMENT")
        end
        return stored
    end,
    GetAsync = function(_self, key, options)
        assert(key == "User_42")
        assert(options ~= nil and options.UseCache == false, "Ambiguous writes must verify without cache")
        uncachedReads += 1
        return stored
    end,
}
failNextAcknowledgement = true
local session, openErr = store:OpenAsync("User_42")
assert(session ~= nil, "Dropped load acknowledgement lost the session: " .. tostring(openErr))
assert(uncachedReads == 1, "Load acknowledgement was not verified")
assert(session:Get("Coins") == 0)

local changed, changeErr = session:Set("Coins", 72)
assert(changed, tostring(changeErr))
failNextAcknowledgement = true
local saved, saveErr = session:SaveAsync("critical")
assert(saved, "Confirmed backend save was incorrectly rejected: " .. tostring(saveErr))
assert(uncachedReads == 2, "Save acknowledgement was not verified")
assert(not session:IsDirty(), "Confirmed save left session dirty")
local savedRecord, savedDecodeErr = store:_DecodeRecord(stored)
assert(savedRecord and savedRecord.Data.Coins == 72, "Saved coins were corrupted: " .. tostring(savedDecodeErr))

local longValue = string.rep("repeatable-inventory-payload-", 500)
assert(session:Set("Blob", longValue))
assert(session:SaveAsync("critical"))
local compressedRecord, compressionErr = store:_DecodeRecord(stored)
assert(compressedRecord and compressedRecord.Data.Blob == longValue, "Compression roundtrip failed: " .. tostring(compressionErr))
assert(session:ReleaseAsync())
assert(not session:IsActive())
assert(store:CloseAsync())
assert(uncachedReads == 2 and updates >= 4, "Unexpected backend request accounting")
print("NexusDataStore v7.1.0 load/save acknowledgement and codec regression PASS")
