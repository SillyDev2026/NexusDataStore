--!strict
-- One million invocations per selected backend-facing NexusDataStore function.
-- Place beside DataStore and Compression ModuleScripts in ROBLOX STUDIO.
-- Replaces standard/ordered backend instances with in-memory mocks.
-- NO live DataStore, MessagingService, or cross-server load testing occurs.
-- Set SUITE to a case name to run a single function.
local ITERATIONS = 1_000_000
local BATCH_SIZE = 1000
local SUITE = "all"
local DataStore = require(script.Parent:WaitForChild("DataStore"))
local store: any = DataStore.new({
	Name = "NexusMillionBackendBench",
	Template = {Coins = 0, Level = 1},
	Compression = false,
	AutoSave = false,
	AutoPlayerLifecycle = false,
	BudgetAware = false,
	DetectDirectChanges = false,
	RetryAttempts = 1,
	MinimumSaveInterval = 0,
	OrderedDataStores = {
		Score = {Name = "NexusMillionOrderedMock", Path = "Coins", Mode = "set", AutoSync = false, Integer = true},
	},
})
assert(store:GetVersion() == "7.0.8")
local records: {[string]: any} = {}
store.DataStore = {
	UpdateAsync = function(_self, key: string, transform)
		local nextRecord = transform(records[key], nil)
		if nextRecord ~= nil then records[key] = nextRecord end
		return records[key]
	end,
	GetAsync = function(_self, key: string)
		return records[key]
	end,
}
local template = store:GetTemplate()
records.peek = store:_BuildNewRecord(template)
local sessionRecord = store:_BuildNewRecord(template)
store:_LockRecord(sessionRecord, "mock-session")
records["local"] = sessionRecord
local profile: any = store:_CreateSession("local", sessionRecord, "mock-session", {})
local ordered: any = store:GetOrderedStore("Score")
assert(ordered ~= nil)
local ranks: {[string]: number} = {score = 1, other = 5}
ordered.DataStore = {
	GetAsync = function(_self, key: string) return ranks[key] end,
	SetAsync = function(_self, key: string, value: number) ranks[key] = value return value end,
	UpdateAsync = function(_self, key: string, callback)
		local nextValue = callback(ranks[key])
		if nextValue ~= nil then ranks[key] = nextValue end
		return ranks[key]
	end,
	IncrementAsync = function(_self, key: string, delta: number)
		ranks[key] = (ranks[key] or 0) + delta
		return ranks[key]
	end,
	RemoveAsync = function(_self, key: string)
		local previous = ranks[key]
		ranks[key] = nil
		return previous
	end,
	GetSortedAsync = function(_self, ascending: boolean, limit: number)
		local data = {}
		for key, value in pairs(ranks) do table.insert(data, {key = key, value = value}) end
		table.sort(data, function(a, b)
			if a.value ~= b.value then return ascending and a.value < b.value or a.value > b.value end
			return a.key < b.key
		end)
		local output = {}
		for i = 1, math.min(limit, #data) do output[i] = data[i] end
		return {IsFinished = true, GetCurrentPage = function() return output end}
	end,
}
local cases, invocations = 0, 0
local function benchmark(name: string, callback: (number) -> boolean, callsPerIteration: number?)
	if SUITE ~= "all" and SUITE ~= name then return end
	cases += 1
	local elapsed = 0
	for startIndex = 1, ITERATIONS, BATCH_SIZE do
		local stopIndex = math.min(ITERATIONS, startIndex + BATCH_SIZE - 1)
		local begin = os.clock()
		for i = startIndex, stopIndex do
			assert(callback(i), name .. " failed at " .. tostring(i))
		end
		elapsed += os.clock() - begin
		task.wait()
	end
	local calls = ITERATIONS * (callsPerIteration or 1)
	invocations += calls
	print(("[NexusMockBench] %-24s %d method calls | %.3f us/iteration"):format(name, calls, elapsed * 1e6 / ITERATIONS))
end

benchmark("PeekAsync", function()
	local value = store:PeekAsync("peek")
	return value ~= nil and value.Coins == 0
end)
benchmark("SaveAsync", function(i)
	local dirty = profile:Set("Coins", i)
	if not dirty then return false end
	local saved = profile:SaveAsync("critical")
	return saved and records["local"] ~= nil and profile.Revision == i
end)
benchmark("FlushAsync", function()
	local ok = store:FlushAsync(5)
	return ok
end)
benchmark("GetHealth", function()
	local health = store:GetHealth()
	return health.Version == "7.0.8"
end)
benchmark("GetOrderedStore", function()
	return store:GetOrderedStore("Score") == ordered
end)
benchmark("OrderedGetAsync", function()
	local ok, value = ordered:GetAsync("score")
	return ok and typeof(value) == "number"
end)
benchmark("OrderedSetAsync", function(i)
	local ok, value = ordered:SetAsync("score", i)
	return ok and value == i
end)
benchmark("OrderedUpdateAsync", function()
	local before = ranks.score or 0
	local ok, value = ordered:UpdateAsync("score", function(old)
		return (old or 0) + 1
	end)
	return ok and value == before + 1
end)
benchmark("OrderedMaxAsync", function()
	local before = ranks.score or 0
	local ok = ordered:MaxAsync("score", before + 1)
	return ok and ranks.score == before + 1
end)
benchmark("OrderedMinAsync", function()
	local before = ranks.score or 0
	local ok = ordered:MinAsync("score", before - 1)
	return ok and ranks.score == before - 1
end)
benchmark("OrderedIncrementAsync", function()
	local before = ranks.score or 0
	local ok, value = ordered:IncrementAsync("score", 1)
	return ok and value == before + 1
end)
benchmark("OrderedWriteAsync", function(i)
	local ok, value = ordered:WriteAsync("score", i, "set")
	return ok and value == i
end)
benchmark("OrderedGetSortedAsync", function()
	local ok, pages = ordered:GetSortedAsync(false, 10)
	return ok and pages:GetCurrentPage() ~= nil
end)
benchmark("OrderedGetTopAsync", function()
	local ok, entries = ordered:GetTopAsync(10)
	return ok and #entries >= 1
end)
benchmark("OrderedGetBottomAsync", function()
	local ok, entries = ordered:GetBottomAsync(10)
	return ok and #entries >= 1
end)
benchmark("OrderedGetRankAsync", function()
	local ok, result = ordered:GetRankAsync("score", false, 1)
	return ok and result.Rank >= 1
end)
benchmark("OrderedSyncSessionAsync", function()
	local ok = ordered:SyncSessionAsync(profile)
	return ok
end)
benchmark("SyncOrderedAsync", function()
	local ok = store:SyncOrderedAsync(profile, "Score")
	return ok
end)
benchmark("SyncAllOrderedAsync", function()
	local ok = store:SyncAllOrderedAsync("Score")
	return ok
end)
benchmark("OrderedRemoveAsync", function()
	local ok = ordered:RemoveAsync("temporary")
	return ok
end)
benchmark("OpenAsync+ReleaseAsync", function()
	local session, err = store:OpenAsync("reopen")
	if not session then warn(err) return false end
	local released = session:ReleaseAsync()
	return released and not session:IsActive() and store:GetSession("reopen") == nil
end, 2)

assert(cases > 0, "No matching SUITE found")
print(("[NexusMockBench] %d cases, %d method calls, %d iterations per case"):format(cases, invocations, ITERATIONS))
print("[NexusMockBench] These figures exclude real Roblox network latency, budgets and cross-server locking.")
-- This fixture deliberately uses a fake persisted lock and does not make external requests.
assert(profile:ReleaseAsync())
assert(store:CloseAsync())
