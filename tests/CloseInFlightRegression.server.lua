--!strict
-- Studio server regression for shutdown racing with a yielding OpenAsync.
-- Place beside DataStore ModuleScript (with PlayersData child). No live backend calls.
local DataStore = require(script.Parent:WaitForChild("DataStore"))
local store: any = DataStore.new({
    Name = "NexusCloseInFlightRegression",
    Template = {Coins = 0},
    Compression = false,
    AutoSave = false,
    AutoPlayerLifecycle = false,
    DetectDirectChanges = false,
    BudgetAware = false,
    RetryAttempts = 1,
})
local stored: any = nil
store.DataStore = {
    UpdateAsync = function(_self, key, transform)
        assert(key == "race")
        task.wait(0.08)
        local nextValue = transform(stored)
        if nextValue ~= nil then stored = nextValue end
        return stored
    end,
    GetAsync = function(_self, _key)
        return stored
    end,
}
local openedSession: any = nil
local openError: any = nil
task.spawn(function()
    openedSession, openError = store:OpenAsync("race")
end)
task.wait(0.01)
assert(store.OpenInFlight == 1, "Regression requires an in-flight open")
local closed, closeErr = store:CloseAsync(5)
assert(closed, "CloseAsync failed during concurrent load: " .. tostring(closeErr))
assert(openedSession ~= nil, "In-flight open failed: " .. tostring(openError))
assert(not openedSession:IsActive(), "CloseAsync stranded an acquired session")
assert(store.OpenInFlight == 0, "In-flight counter leaked")
assert(store.Sessions.race == nil and store.Closed, "Store closed with an active profile")
local raw = store:_DecodeRecord(stored)
assert(raw and raw.Lock == nil, "Shutdown failed to release backend session lock")
print("NexusDataStore v7.0.5 close-vs-open regression PASS")
