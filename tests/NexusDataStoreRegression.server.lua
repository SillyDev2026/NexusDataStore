--!strict
-- Studio-only regression for DataStore's map-key codec-node allowance.
-- Place this Script beside DataStore and Compression ModuleScripts. DataStore
-- must have its PlayersData ModuleScript child as required by the public API.
-- No DataStore keys are read or written by this test.
local DataStore = require(script.Parent:WaitForChild("DataStore"))
local compressionModule = script.Parent:WaitForChild("Compression")

local inventory: {[string]: number} = {}
for index = 1, 2200 do
    inventory["Key_" .. tostring(index)] = index
end
local template = {Coins = 0, Inventory = inventory}
local store = DataStore.new({
    Name = "NexusDataStore_Regression",
    Template = template,
    Compression = true,
    CompressionModule = compressionModule,
    AutoSave = false,
    DetectDirectChanges = false,
    AutoPlayerLifecycle = false,
    MaxDataNodes = 3000,
})
assert(store:GetVersion() == "7.0.3", "Unexpected NexusDataStore version")
assert(store.Config.CompressionOptions.MaxNodes >= store.Config.MaxDataNodes * 2, "Codec node budget is too small")
local packet, report = store:EncodeCompressed(template)
assert(typeof(packet) == "buffer", "Large string-key map failed to encode: " .. tostring(report))
local result, err = store:DecodeCompressed(packet)
assert(result ~= nil, "Could not decode map: " .. tostring(err))
assert(result.Inventory.Key_2200 == 2200, "Map data changed during encoding")
local closed, closeErr = store:CloseAsync()
assert(closed, "Test store cleanup failed: " .. tostring(closeErr))
print("NexusDataStore v7.0.3 map-key regression PASS (2,200 keys)")
