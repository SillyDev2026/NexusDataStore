--!strict
-- NexusDataStore v7.0.8: ONE MILLION iterations per selected in-memory function.
-- Roblox Studio SERVER Script, placed beside DataStore and Compression ModuleScripts.
-- Requires DataStore.PlayersData. Does NOT call the live DataStore service.
--
-- Set SUITE to one case name to benchmark a function independently. "all"
-- runs the complete matrix and may require a long Studio session.
-- Times are measured in Studio, never assumed from source inspection.
local ITERATIONS = 1_000_000
local BATCH_SIZE = 1000
local SUITE = "all"
local DataStore = require(script.Parent:WaitForChild("DataStore"))
local store: any = DataStore.new({
	Name = "NexusMillionLocalBench",
	Template = {
		Coins = 0,
		Level = 1,
		Inventory = {} :: {string},
		Upgrades = {WalkSpeed = 0},
		Settings = {Music = true},
	},
	Compression = false,
	AutoSave = false,
	AutoPlayerLifecycle = false,
	BudgetAware = false,
	DetectDirectChanges = false,
	ValidateOnWrite = true,
	MaxSnapshots = 1,
})
assert(store:GetVersion() == "7.0.8", "Benchmark targets the wrong library version")
local record = store:_BuildNewRecord(store:GetTemplate())
local profile: any = store:_CreateSession("local", record, "local-session", {})
local packet = store:EncodeCompressed(store:GetTemplate())
assert(typeof(packet) == "buffer", "Codec fixture must encode")
local summary = {}
local countCases = 0
local totalCalls = 0

local function benchmark(name: string, callback: (number) -> boolean)
	if SUITE ~= "all" and SUITE ~= name then return end
	countCases += 1
	local cpu = 0
	for startIndex = 1, ITERATIONS, BATCH_SIZE do
		local lastIndex = math.min(ITERATIONS, startIndex + BATCH_SIZE - 1)
		local started = os.clock()
		for i = startIndex, lastIndex do
			if not callback(i) then error(name .. " failed at iteration " .. tostring(i)) end
		end
		cpu += os.clock() - started
		task.wait() -- Keep Studio responsive; waiting time is excluded.
	end
	totalCalls += ITERATIONS
	local microseconds = cpu * 1e6 / ITERATIONS
	summary[name] = {Calls = ITERATIONS, CpuSeconds = cpu, MicrosecondsPerCall = microseconds}
	print(("[NexusBench] %-24s %d checks | %.3f us/check | %.3f s measured"):format(name, ITERATIONS, microseconds, cpu))
end

benchmark("Get", function() return typeof(profile:Get("Coins")) == "number" end)
benchmark("GetOr", function() return profile:GetOr("Missing", 42) == 42 end)
benchmark("Has", function() return profile:Has("Inventory") end)
benchmark("IsActive", function() return profile:IsActive() end)
benchmark("IsDirty", function() return typeof(profile:IsDirty()) == "boolean" end)
benchmark("GetStatus", function() return profile:GetStatus().Active == true end)
benchmark("GetSession", function() return store:GetSession("local") == profile end)
benchmark("WaitForSession", function() return store:WaitForSession("local", 0) == profile end)
benchmark("GetVersion", function() return store:GetVersion() == "7.0.8" end)
benchmark("GetTemplate", function() return typeof(store:GetTemplate().Coins) == "number" end)
benchmark("GetSchema", function() return store:GetSchema() == nil end)
benchmark("Validate", function() return store:Validate(profile.Data) == true end)
benchmark("GetMetrics", function() return typeof(store:GetMetrics().Mutations) == "number" end)
benchmark("GetStats", function() return profile:GetStats().Valid == true end)

benchmark("Set", function(i)
	local ok = profile:Set("Coins", i % 1000)
	return ok and profile.Data.Coins == i % 1000
end)
benchmark("Delete", function()
	local ok = profile:Delete({"Upgrades", "Temp"})
	return ok and profile.Data.Upgrades.Temp == nil
end)
benchmark("Increment", function()
	local current = profile.Data.Coins
	local ok, value = profile:Increment("Coins", 1)
	return ok and value == current + 1
end)
benchmark("IncrementClamped", function()
	local ok, value = profile:IncrementClamped("Level", 1, 1, 100)
	return ok and value >= 1 and value <= 100
end)
benchmark("Award", function()
	local old = profile.Data.Coins
	local ok, value = profile:Award("Coins", 1)
	return ok and value == old + 1
end)
if SUITE == "Spend" then assert(profile:Set("Coins", 2_000_000)) end
benchmark("Spend", function()
	local old = profile.Data.Coins
	local ok, value = profile:Spend("Coins", 1)
	return ok and value == old - 1
end)
benchmark("Toggle", function()
	local old = profile.Data.Settings.Music
	local ok, value = profile:Toggle({"Settings", "Music"})
	return ok and value == (not old)
end)
benchmark("UpdatePath", function()
	local old = profile.Data.Upgrades.WalkSpeed
	local ok, value = profile:UpdatePath({"Upgrades", "WalkSpeed"}, function(v)
		return v + 1
	end)
	return ok and value == old + 1
end)
local changes: any = {{Path = "Coins", Value = 0}}
benchmark("Patch", function(i)
	changes[1].Value = i
	local ok = profile:Patch(changes)
	return ok and profile.Data.Coins == i
end)
benchmark("Mutate", function()
	local old = profile.Data.Coins
	local ok = profile:Mutate(function(draft)
		draft.Coins += 1
		return true
	end)
	return ok and profile.Data.Coins == old + 1
end)
benchmark("Append+RemoveAt", function()
	local added, size = profile:Append("Inventory", "Potion")
	if not added or size ~= 1 then return false end
	local removed, item = profile:RemoveAt("Inventory", 1)
	return removed and item == "Potion" and #profile.Data.Inventory == 0
end)
if summary["Append+RemoveAt"] then
	totalCalls += ITERATIONS -- One million calls to EACH method in the pair.
	print("[NexusBench] Append and RemoveAt each invoked 1,000,000 times; combined time reported.")
end

benchmark("Watch", function()
	local subscription = profile:Watch("Coins", function() end)
	if not subscription.Connected then return false end
	subscription:Disconnect()
	return not subscription.Connected
end)
local latestSnapshot: any
benchmark("Snapshot", function()
	latestSnapshot = profile:Snapshot("bench")
	return latestSnapshot.Id ~= nil and #profile.Snapshots == 1
end)
if latestSnapshot ~= nil or SUITE == "Restore" then
	latestSnapshot = latestSnapshot or profile:Snapshot("bench")
	benchmark("Restore", function()
		local ok = profile:Restore(latestSnapshot)
		return ok and profile.Data.Coins == latestSnapshot.Data.Coins
	end)
end
benchmark("DiffFromPersisted", function() return typeof(profile:DiffFromPersisted()) == "table" end)
benchmark("GetCompressionReport", function()
	local report = store:GetCompressionReport(profile)
	return report ~= nil and report.StorageBytes > 0
end)
benchmark("EncodeCompressed", function()
	local value = store:EncodeCompressed(profile.Data)
	return typeof(value) == "buffer"
end)
benchmark("DecodeCompressed", function()
	local value = store:DecodeCompressed(packet)
	return value ~= nil and typeof(value.Coins) == "number"
end)

assert(countCases > 0, "No matching SUITE found")
print(("[NexusBench] %d functions/cases, %d verified method calls, %d iterations per case"):format(countCases, totalCalls, ITERATIONS))
print("[NexusBench] Results are Studio-local CPU measurements. No Roblox DataStore latency or server contention measured.")
profile.Active = false
store:_UnregisterSession(profile)
assert(store:CloseAsync())
