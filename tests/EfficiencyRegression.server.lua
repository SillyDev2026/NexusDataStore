--!strict
-- Studio regression: optional no-op mutations, concurrent save coalescing and profiler.
-- Place beside DataStore (with PlayersData child). All writes use in-memory mocks.
local DataStore = require(script.Parent:WaitForChild("DataStore"))
local store: any = DataStore.new({
	Name = "NexusEfficiencyRegression",
	Template = {Coins = 0, Settings = {Music = true}, Inventory = {}},
	Compression = false,
	AutoSave = false,
	AutoPlayerLifecycle = false,
	BudgetAware = false,
	RetryAttempts = 1,
	DetectDirectChanges = true,
	MinimumSaveInterval = 0,
	SkipUnchangedMutations = true,
	ProfileOperations = true,
})
assert(store:GetVersion() == "7.2.0")
local current: any = nil
local updateCalls = 0
store.DataStore = {
	UpdateAsync = function(_self, key, callback)
		assert(key == "local")
		updateCalls += 1
		local updated = callback(current)
		if updated ~= nil then current = updated end
		-- Simulate a slow acknowledgement, allowing another save to queue.
		task.wait(0.04)
		return current
	end,
	GetAsync = function(_self, _key)
		return current
	end,
}
local profile: any = store:OpenAsync("local")
assert(profile and profile:IsActive() and updateCalls == 1)
local initialId = profile.MutationId
local changedEvents = 0
local watch = profile:Watch("Coins", function() changedEvents += 1 end)

assert(profile:Set("Coins", 0))
assert(profile:Delete({"Settings", "Missing"}))
assert(profile:Patch({{Path = "Coins", Value = 0}, {Path = {"Settings", "Music"}, Value = true}}))
local mutateOk, mutateResult = profile:Mutate(function(_draft) return "same" end)
assert(mutateOk and mutateResult == "same")
assert(profile.MutationId == initialId and not profile:IsDirty(), "No-op produced a mutation")
assert(store:GetMetrics().NoopMutations == 4, "No-op counter incorrect")

-- Missing parent errors still apply even when the candidate value is nil.
local setOK, setError = profile:Set({"Unknown", "Child"}, nil)
local deleteOK, deleteError = profile:Delete({"Unknown", "Child"})
local patchOK, patchError = profile:Patch({{Path = {"Unknown", "Child"}, Value = nil}})
assert(not setOK and string.find(tostring(setError), "PATH_PARENT_MISSING", 1, true))
assert(not deleteOK and string.find(tostring(deleteError), "PATH_PARENT_MISSING", 1, true))
assert(not patchOK and string.find(tostring(patchError), "PATH_PARENT_MISSING", 1, true))
assert(profile.MutationId == initialId, "Malformed no-op changed profile")

local setChanged, setChangedErr = profile:Set("Coins", 100)
assert(setChanged, tostring(setChangedErr))
task.wait(0.02)
assert(changedEvents == 1, "No-op watcher notification or missing mutation notification")
watch:Disconnect()

local firstDone, secondDone = false, false
local firstOK, secondOK = false, false
task.spawn(function()
	firstOK = profile:SaveAsync("critical")
	firstDone = true
end)
task.wait(0.01)
task.spawn(function()
	secondOK = profile:SaveAsync("critical")
	secondDone = true
end)
local waitStart = os.clock()
while not (firstDone and secondDone) and os.clock() - waitStart < 5 do task.wait(0.01) end
assert(firstDone and secondDone and firstOK and secondOK, "Concurrent saves did not finish")
assert(updateCalls == 2, "Second queued save issued redundant UpdateAsync")
assert(store:GetMetrics().SavesCoalesced >= 1, "Queued save not counted")
assert(profile.Revision == 1 and not profile:IsDirty(), "Save did not preserve revision/dirty state")
local record = store:_DecodeRecord(current)
assert(record and record.Data.Coins == 100, "Persisted record has wrong data")
local report = store:GetPerformanceReport()
assert(report.Enabled and report.NoopMutations == 4 and report.SavesCoalesced >= 1)
assert(report.Operations.MutationDraft and report.Operations.MutationDraft.Count == 1, "Mutation profiler not active")
assert(report.Operations.DataStoreCommit and report.Operations.DataStoreCommit.Count >= 2, "Commit profiler not active")
assert(report.Operations.MutationDraft.TotalMs >= 0 and report.Operations.DataStoreCommit.MaxMs >= 0)

-- A caller receives copies of profile reports; they cannot mutate store metrics.
report.Operations.MutationDraft.Count = -999
assert(store:GetPerformanceReport().Operations.MutationDraft.Count == 1)

-- Backward-compatible defaults: no-op detection and profiling must remain opt-in.
local legacy: any = DataStore.new({
	Name = "NexusEfficiencyLegacy",
	Template = {Coins = 0},
	Compression = false, AutoSave = false, AutoPlayerLifecycle = false, BudgetAware = false,
})
local legacyProfile: any = legacy:_CreateSession("legacy", legacy:_BuildNewRecord({Coins = 0}), "legacy-session", {})
local before = legacyProfile.MutationId
assert(legacyProfile:Set("Coins", 0), "Legacy same-value mutation failed")
assert(legacyProfile.MutationId == before + 1 and legacyProfile:IsDirty(), "Default notification/mutation semantics changed")
local legacyReport = legacy:GetPerformanceReport()
assert(not legacyReport.Enabled and next(legacyReport.Operations) == nil and legacyReport.NoopMutations == 0)
legacyProfile.Active = false
legacy:_UnregisterSession(legacyProfile)
assert(legacy:CloseAsync())

local released, releaseError = profile:ReleaseAsync()
assert(released, tostring(releaseError))
assert(store:CloseAsync())
print("NexusDataStore v7.2.0 efficiency, coalescing and profiler regression PASS")
