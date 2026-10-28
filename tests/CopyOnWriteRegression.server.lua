--!strict
-- In-memory regression for v7.0.8 path-level copy-on-write.
-- Place beside DataStore ModuleScript (with PlayersData child); NO live DataStore calls.
local DataStore = require(script.Parent:WaitForChild("DataStore"))

local function createFixture(detectDirectChanges: boolean)
	local store: any = DataStore.new({
		Name = detectDirectChanges and "NexusCowDirectOn" or "NexusCowDirectOff",
		Template = {
			Coins = 0,
			Inventory = {} :: {string},
			Settings = {Music = true, SFX = true},
			Nested = {Branch = {Score = 0, Extra = 10}, Other = {Score = 25}},
		},
		Compression = false,
		AutoSave = false,
		AutoPlayerLifecycle = false,
		DetectDirectChanges = detectDirectChanges,
		BudgetAware = false,
		Strict = true,
	})
	local record = store:_BuildNewRecord(store:GetTemplate())
	local session: any = store:_CreateSession("cow", record, "local-cow-session", {})
	return store, session
end

for _, direct in ipairs({true, false}) do
	local store, profile = createFixture(direct)
	assert(store:GetVersion() == "7.0.8")
	local initial = profile.Data
	local initialBranch = initial.Nested.Branch
	local initialOther = initial.Nested.Other
	local watcherCount, lastBefore, lastAfter = 0, nil, nil
	local watching = profile:Watch({"Nested", "Branch", "Score"}, function(newValue, oldValue)
		watcherCount += 1
		lastBefore, lastAfter = oldValue, newValue
	end)

	-- A nested change creates new root/ancestor nodes without altering old references.
	assert(profile:Set({"Nested", "Branch", "Score"}, 99))
	assert(profile:Get({"Nested", "Branch", "Score"}) == 99)
	assert(initial.Nested.Branch.Score == 0)
	assert(profile.Data ~= initial and profile.Data.Nested ~= initial.Nested)
	assert(profile.Data.Nested.Branch ~= initialBranch)
	assert(profile.Data.Nested.Other == initialOther, "Untouched sibling was deep-cloned")
	task.wait(0.02)
	assert(watcherCount == 1 and lastBefore == 0 and lastAfter == 99, "Watcher values changed")
	watching:Disconnect()

	local passed, failure = profile:Set({"Nested", "Unknown", "Score"}, 3)
	assert(not passed and string.find(tostring(failure), "PATH_PARENT_MISSING", 1, true), "Invalid ancestor should fail")
	assert(profile.Data.Nested.Other.Score == 25, "Failed update damaged sibling")

	-- Deletions must not change previously retained tables.
	local oldSettings = profile.Data.Settings
	assert(profile:Delete({"Settings", "Music"}))
	assert(profile.Data.Settings.Music == nil and oldSettings.Music == true)

	-- Update same ancestor twice within one Patch and make it all-or-nothing.
	assert(profile:Patch({
		{Path = {"Nested", "Branch", "Score"}, Value = 41},
		{Path = {"Nested", "Branch", "Extra"}, Value = 42},
		{Path = "Coins", Value = 33},
	}))
	assert(profile.Data.Nested.Branch.Score == 41 and profile.Data.Nested.Branch.Extra == 42 and profile.Data.Coins == 33)
	local oldRoot = profile.Data
	local rejected, reason = profile:Patch({
		{Path = "Coins", Value = 444},
		{Path = {"Nested", "Missing", "Score"}, Value = 99},
	})
	assert(not rejected and string.find(tostring(reason), "PATH_PARENT_MISSING", 1, true), "Patch must reject missing ancestor")
	assert(profile.Data == oldRoot and profile.Data.Coins == 33, "Partial patch committed unexpectedly")

	local inventoryBefore = profile.Data.Inventory
	assert(profile:Append("Inventory", "Potion"))
	assert(profile:Append("Inventory", "Shield"))
	assert(#profile.Data.Inventory == 2 and #inventoryBefore == 0, "Append mutated old array")
	local arrayBeforeRemove = profile.Data.Inventory
	local removed, item = profile:RemoveAt("Inventory", 1)
	assert(removed and item == "Potion" and profile.Data.Inventory[1] == "Shield")
	assert(#arrayBeforeRemove == 2 and arrayBeforeRemove[1] == "Potion", "RemoveAt mutated old array")

	-- Reconciliation/validation must still protect the full candidate.
	local oldProfile = profile.Data
	local invalid, invalidErr = profile:Set({"Settings", "SFX"}, "not a boolean")
	assert(not invalid and string.find(tostring(invalidErr), "VALIDATION_FAILED", 1, true))
	assert(profile.Data == oldProfile and profile.Data.Settings.SFX == true, "Failed validation leaked changes")

	-- Check both direct-change detection configurations without backend access.
	local snapshot = profile:Snapshot("pre-reward")
	assert(profile:Award("Coins", 7))
	assert(profile:Restore(snapshot))
	assert(profile.Data.Coins == 33, "Snapshot rollback changed semantics")
	profile.Active = false
	store:_UnregisterSession(profile)
	assert(store:CloseAsync(), "Fixture did not close")
end

print("NexusDataStore v7.0.8 copy-on-write correctness regression PASS (direct-change tracking on/off)")
