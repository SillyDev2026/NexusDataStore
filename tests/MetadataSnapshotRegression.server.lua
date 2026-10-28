--!strict
-- Roblox Studio server regression: preserves key information during Open/Save/Release
-- and prevents snapshot/path misuse. Place alongside DataStore, Compression and
-- the required DataStore.PlayersData module. No live backend is accessed.
local DataStore = require(script.Parent:WaitForChild("DataStore"))
local store: any = DataStore.new({
    Name = "NexusMetadataSnapshotRegression",
    Template = {Coins = 0, Inventory = {}},
    Compression = false,
    AutoSave = false,
    AutoPlayerLifecycle = false,
    DetectDirectChanges = true,
    BudgetAware = false,
    RetryAttempts = 1,
    MaxSnapshots = 1,
})
local stored: any = store:_BuildNewRecord({Coins = 10, Inventory = {"Potion"}})
local keyInfo = {
    GetUserIds = function() return {12345678} end,
    GetMetadata = function() return {Owner = "legacy", Build = 5} end,
}
local updateCount, preserved = 0, 0
store.DataStore = {
    UpdateAsync = function(_self, key, transform)
        assert(key == "profile_1", "Unexpected key")
        updateCount += 1
        local nextRecord, userIds, metadata = transform(stored, keyInfo)
        if nextRecord ~= nil then
            assert(typeof(userIds) == "table" and userIds[1] == 12345678, "User IDs lost during UpdateAsync")
            assert(typeof(metadata) == "table" and metadata.Owner == "legacy" and metadata.Build == 5, "Metadata lost during UpdateAsync")
            preserved += 1
            stored = nextRecord
        end
        return stored
    end,
}
local profile, openError = store:OpenAsync("profile_1")
assert(profile and openError == nil, "Failed to open profile: " .. tostring(openError))
assert(profile.Data.Coins == 10, "Profile was not loaded")
assert(profile:Set("Coins", 20))
assert(profile:SaveAsync("critical"))
assert(updateCount == 2 and preserved == 2, "Open and save must preserve metadata")

local first = profile:Snapshot("safe")
assert(first.Data.Coins == 20)
first.Data.Coins = 999
assert(profile:Set("Coins", 50))
local restored, restoreError = profile:Restore(first)
assert(restored and restoreError == nil and profile.Data.Coins == 20, "Snapshot caller was able to replace retained data")

local impostor = {Id = "forged-id", Revision = first.Revision, Data = {Coins = 999, Inventory = {}}}
local impostorOK, impostorError = profile:Restore(impostor)
assert(not impostorOK and impostorError == "SNAPSHOT_NOT_OWNED", "Forged snapshot accepted")
assert(profile.Data.Coins == 20, "Forged snapshot changed data")

local evicted = profile:Snapshot("newer")
assert(evicted.Id ~= first.Id)
local oldOK, oldError = profile:Restore(first)
assert(not oldOK and oldError == "SNAPSHOT_NOT_OWNED", "Evicted snapshot incorrectly restored")

local invalidPaths = {
    {},
    {[2] = "Coins"},
    {[1] = "Inventory", [3] = 1},
    {Coins = "Coins"},
    {"Inventory", 0},
}
for _, invalid in ipairs(invalidPaths) do
    local accepted = pcall(function() return profile:Get(invalid) end)
    assert(not accepted, "Invalid path was accepted")
    local ok, reason = profile:Patch({{Path = invalid, Value = 5}})
    assert(not ok and string.find(tostring(reason), "INVALID_PATCH_PATH", 1, true) == 1, "Invalid patch path was not safely rejected")
    assert(profile.Data.Coins == 20, "Invalid path changed profile data")
end
local setInvalid, setInvalidError = profile:Set({[2] = "Coins"}, 99)
assert(not setInvalid and string.find(tostring(setInvalidError), "INVALID_PATH", 1, true) == 1, "Set must return invalid path error")
local deleteInvalid, deleteInvalidError = profile:Delete({[2] = "Coins"})
assert(not deleteInvalid and string.find(tostring(deleteInvalidError), "INVALID_PATH", 1, true) == 1, "Delete must return invalid path error")

profile.Releasing = true
local releasedSet, releasedSetError = profile:Set("Coins", 123)
local releasedDelete, releasedDeleteError = profile:Delete("Coins")
profile.Releasing = false
assert(not releasedSet and releasedSetError == "SESSION_RELEASING", "Set must reject releasing session")
assert(not releasedDelete and releasedDeleteError == "SESSION_RELEASING", "Delete must reject releasing session")
assert(profile.Data.Coins == 20, "Releasing session was mutated")

assert(profile:Set({"Inventory", 1}, "SuperPotion"), "Valid nested path rejected")
assert(profile:Get({"Inventory", 1}) == "SuperPotion", "Valid nested path returned wrong value")

local fakeRecord = store:_BuildNewRecord({Coins = 10, Inventory = {}})
local decoded, decodeError = store:_DecodeRecord(fakeRecord)
assert(decoded ~= nil and decodeError == nil, "Record codec regressed")
assert(profile:ReleaseAsync(), "Release failed")
local released = store:_DecodeRecord(stored)
assert(released and released.Lock == nil, "Release did not clear session lock")
assert(updateCount == 3 and preserved == 3, "Release must also preserve metadata")
assert(store:CloseAsync())
print("NexusDataStore metadata, snapshot and path regressions PASS")
