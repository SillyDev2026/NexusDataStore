--!strict
-- Studio-only regression: mutation callbacks, sparse patches and API input guards.
-- Place this Script beside DataStore ModuleScript (which has PlayersData child).
-- No remote DataStore calls are made; all sessions are fabricated in memory.
local DataStore = require(script.Parent:WaitForChild("DataStore"))
local store: any = DataStore.new({
    Name = "NexusMutationSafetyRegression",
    Template = {Coins = 0, Inventory = {}},
    Compression = false,
    AutoSave = false,
    AutoPlayerLifecycle = false,
    DetectDirectChanges = true,
    BudgetAware = false,
})
local record = store:_BuildNewRecord({Coins = 10, Inventory = {"Potion"}})
local profile: any = store:_CreateSession("regression", record, "regression-session", {})
assert(profile:IsActive() and profile.Data.Coins == 10, "Session setup failed")

local invalidWait, invalidWaitError = store:WaitForSession("missing", -1)
assert(invalidWait == nil and invalidWaitError == "INVALID_WAIT_TIMEOUT", "Negative wait time must fail cleanly")
local invalidWait2, invalidWaitError2 = store:WaitForSession("missing", math.huge)
assert(invalidWait2 == nil and invalidWaitError2 == "INVALID_WAIT_TIMEOUT", "Nonfinite timeout must fail cleanly")

local badAppend, appendError = profile:Append("Inventory", nil)
assert(badAppend == false and appendError == "INVALID_APPEND_VALUE", "Nil array items must be rejected")

local originalMutationId = profile.MutationId
local emptyOK = profile:Patch({})
assert(emptyOK and profile.MutationId == originalMutationId, "Empty patches should be no-ops")

local sparse = {[2] = {Path = "Coins", Value = 999}}
local sparseOK, sparseError = profile:Patch(sparse)
assert(sparseOK == false and sparseError == "PATCH_MUST_BE_DENSE_ARRAY", "Sparse patch silently accepted")
assert(profile.Data.Coins == 10, "Sparse patch changed data")

local mapOK, mapError = profile:Patch({Entry = {Path = "Coins", Value = 999}})
assert(mapOK == false and mapError == "PATCH_MUST_BE_DENSE_ARRAY", "Map-shaped patch silently accepted")
assert(profile.Data.Coins == 10, "Map patch changed data")

local failedOK, failedError = profile:Patch({{Path = "Coins", Value = 42}, {Path = {"Inventory", "Missing"}, Value = 1}})
assert(not failedOK and failedError ~= nil, "Invalid multi-patch must fail")
assert(profile.Data.Coins == 10, "Rejected patch partially modified live profile")

local invalidPathOK, invalidPathError = profile:Patch({{Path = {}, Value = 77}})
assert(invalidPathOK == false and string.find(tostring(invalidPathError), "INVALID_PATCH_PATH", 1, true) == 1, "Invalid patch path should not throw")
assert(profile.Data.Coins == 10, "Invalid path modified the profile")

local patchOK, patchError = profile:Patch({{Path = "Coins", Value = 20}, {Path = {"Inventory", 1}, Value = "SuperPotion"}})
assert(patchOK and patchError == nil and profile.Data.Coins == 20 and profile.Data.Inventory[1] == "SuperPotion", "Valid patch failed")

local completed = false
local mutateOK: any, mutateError: any
task.spawn(function()
    mutateOK, mutateError = profile:Mutate(function(draft)
        task.wait(0.08)
        draft.Coins = 999
        return true
    end)
    completed = true
end)
task.wait(0.02)
profile.Data.Coins = 37
task.wait(0.12)
assert(completed and mutateOK == false and mutateError == "CONCURRENT_DIRECT_MUTATION", "Yielded Mutate overwrote direct edits")
assert(profile.Data.Coins == 37, "Concurrent direct edit lost during Mutate")

local pathCompleted = false
local pathOK: any, pathError: any
task.spawn(function()
    pathOK, pathError = profile:UpdatePath("Coins", function(current)
        task.wait(0.08)
        return current + 1
    end)
    pathCompleted = true
end)
task.wait(0.02)
profile.Data.Coins = 50
task.wait(0.12)
assert(pathCompleted and pathOK == false and pathError == "CONCURRENT_DIRECT_MUTATION", "Yielded UpdatePath overwrote direct edits")
assert(profile.Data.Coins == 50, "Concurrent direct edit lost during UpdatePath")

local successOK, successValue = profile:Mutate(function(draft)
    draft.Coins += 5
    return "success"
end)
assert(successOK and successValue == "success" and profile.Data.Coins == 55, "Normal Mutate path regressed")

local cancelOK, cancelValue, cancelStatus = profile:UpdatePath("Coins", function() return nil end)
assert(cancelOK and cancelValue == 55 and cancelStatus == "CANCELLED", "UpdatePath cancellation behavior changed")
assert(profile.Data.Coins == 55, "Canceled UpdatePath should not mutate")

-- Close after unregistering this fake session; no backend is available.
profile.Active = false
store:_UnregisterSession(profile)
assert(store:CloseAsync())
print("NexusDataStore v7.1.0 session mutation safety regression PASS")
