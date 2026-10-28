--!strict
-- Studio-only integration regression. Place beside DataStore (with PlayersData child).
-- All DataStore and OrderedDataStore operations use in-memory mocks.
local DataStore = require(script.Parent:WaitForChild("DataStore"))
local store: any = DataStore.new({
    Name = "NexusCoreFeatureMatrixRegression",
    Template = {Coins = 0, Level = 1, Inventory = {}, Upgrades = {}, Settings = {Music = true}},
    Schema = {Coins = {Type = "integer", Min = 0}, Level = {Type = "integer", Min = 1}},
    Compression = true,
    CompressionModule = script.Parent:WaitForChild("Compression"),
    AutoSave = false,
    DetectDirectChanges = true,
    BudgetAware = false,
    AutoPlayerLifecycle = false,
    CompressionMinBytes = 0,
    OrderedDataStores = {Coins = {Name = "NexusCoreFeatureMatrixOrdered", Path = "Coins", Mode = "set", AutoSync = true, Integer = true, ClampMin = 0}},
})
local stored: any = nil
local leaderboardValues: {[string]: number} = {}
store.DataStore = {
    UpdateAsync = function(_self, key, callback)
        assert(key == "core_1")
        local nextValue = callback(stored)
        if nextValue ~= nil then stored = nextValue end
        return stored
    end,
    GetAsync = function(_self, key)
        assert(key == "core_1")
        return stored
    end,
}
local ordered: any = store:GetOrderedStore("Coins")
assert(ordered ~= nil)
ordered.DataStore = {
    GetAsync = function(_self, key) return leaderboardValues[key] end,
    SetAsync = function(_self, key, value) leaderboardValues[key] = value return value end,
    UpdateAsync = function(_self, key, fn)
        local nextValue = fn(leaderboardValues[key])
        if nextValue ~= nil then leaderboardValues[key] = nextValue end
        return leaderboardValues[key]
    end,
    IncrementAsync = function(_self, key, amount)
        leaderboardValues[key] = (leaderboardValues[key] or 0) + amount
        return leaderboardValues[key]
    end,
    RemoveAsync = function(_self, key)
        local old = leaderboardValues[key]
        leaderboardValues[key] = nil
        return old
    end,
    GetSortedAsync = function(_self, ascending, pageSize)
        local arr = {}
        for key, value in pairs(leaderboardValues) do
            table.insert(arr, {key = key, value = value})
        end
        table.sort(arr, function(a, b)
            if a.value ~= b.value then return ascending and a.value < b.value or a.value > b.value end
            return a.key < b.key
        end)
        local page = {}
        for i = 1, math.min(pageSize, #arr) do page[i] = arr[i] end
        return {IsFinished = true, GetCurrentPage = function() return page end}
    end,
}
local opened, savedEvents = 0, 0
store:On("Opened", function() opened += 1 end)
store:On("Saved", function() savedEvents += 1 end)
local profile, openErr = store:OpenAsync("core_1")
assert(profile and openErr == nil, tostring(openErr))
task.wait()
assert(opened == 1 and profile:Get("Coins") == 0 and profile:GetOr("Level", 3) == 1)
assert(profile:Has("Inventory") and profile:Get({"Settings", "Music"}) == true)

local rejected, rejectErr = profile:Set("Coins", -1)
assert(not rejected and string.find(tostring(rejectErr), "VALIDATION_FAILED", 1, true), "Schema rejected negative currency")
assert(profile:Get("Coins") == 0, "Invalid write mutated active profile")

assert(profile:Award("Coins", 100))
assert(profile:Spend("Coins", 20))
assert(profile:Increment("Level", 3))
assert(profile:IncrementClamped("Level", 99, 1, 20))
assert(profile:Toggle({"Settings", "Music"}))
assert(profile:Append("Inventory", "Potion"))
assert(profile:Append("Inventory", "Sword"))
assert(profile:RemoveAt("Inventory", 1))
assert(profile:Set({"Upgrades", "WalkSpeed"}, 1))
assert(profile:UpdatePath({"Upgrades", "WalkSpeed"}, function(level) return level + 1 end))
assert(profile:Patch({{Path = "Coins", Value = 90}, {Path = "Level", Value = 10}}))

local mutated, state = profile:Mutate(function(draft)
    if draft.Coins < 15 then return false end
    draft.Coins -= 15
    draft.Inventory[#draft.Inventory + 1] = "Shield"
    return "DONE"
end)
assert(mutated and state == "DONE")
assert(profile.Data.Coins == 75 and profile.Data.Level == 10)
assert(#profile.Data.Inventory == 2 and profile.Data.Upgrades.WalkSpeed == 2)
assert(profile:Get({"Settings", "Music"}) == false)

local watchChanges = 0
local subscription = profile:Watch("Coins", function() watchChanges += 1 end)
assert(profile:Award("Coins", 1))
task.wait(0.01)
assert(watchChanges >= 1, "Path watcher not notified")
subscription:Disconnect()
local snapshot = profile:Snapshot("backup")
assert(profile:Award("Coins", 10))
assert(profile:Restore(snapshot))
assert(profile:Get("Coins") == 76)
assert(#profile:DiffFromPersisted() > 0)

local report, reportErr = store:GetCompressionReport(profile)
assert(report and report.StorageBytes > 0, tostring(reportErr))
local packet, compressionReport = store:EncodeCompressed(profile.Data)
assert(typeof(packet) == "buffer" and compressionReport.EncodedBytes > 0)
local roundtrip, decodeErr = store:DecodeCompressed(packet)
assert(roundtrip ~= nil and roundtrip.Coins == profile.Data.Coins, tostring(decodeErr))

assert(profile:SaveAsync("critical"), "Save failed")
task.wait(0.01)
assert(savedEvents >= 1, "Saved event missing")
assert(#profile:DiffFromPersisted() == 0, "Persisted snapshot not updated")
assert(leaderboardValues.core_1 == 76, "Automatic ordered sync failed")
local peek, metadataOrErr = store:PeekAsync("core_1")
assert(peek and peek.Coins == 76, tostring(metadataOrErr))

local changed, oldValue = ordered:WriteAsync("player_2", 150, "set")
assert(changed and oldValue == 150)
assert(ordered:MaxAsync("player_2", 140))
local ok, current = ordered:GetAsync("player_2")
assert(ok and current == 150, "Max mode allowed a decrease")
assert(ordered:MinAsync("player_2", 125))
assert(leaderboardValues.player_2 == 125, "Min mode not respected")
local topOK, top = ordered:GetTopAsync(10)
assert(topOK and #top == 2 and top[1].Key == "player_2", "Sorted leaderboard incorrect")
local rankOK, rank = ordered:GetRankAsync("core_1", false, 1)
assert(rankOK and rank.Rank == 2, "Ordered ranking incorrect")
assert(ordered:IncrementAsync("player_2", 5))
assert(leaderboardValues.player_2 == 130)
assert(ordered:RemoveAsync("player_2"))
assert(leaderboardValues.player_2 == nil)

profile.Data.Coins = 77
assert(profile:SaveAsync("critical"), "Direct change should be detected and persisted")
assert(leaderboardValues.core_1 == 77, "Ordered sync did not see direct edit")
assert(profile:ReleaseAsync())
assert(not profile:IsActive() and store:GetSession("core_1") == nil)
assert(store:CloseAsync())
local metrics = store:GetMetrics()
assert(metrics.Opened == 1 and metrics.Released == 1 and metrics.Saved >= 2)
print("NexusDataStore core features + compression + ordered regression PASS")
