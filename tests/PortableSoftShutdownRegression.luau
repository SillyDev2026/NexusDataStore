--!strict
-- Runs with portable DataStore harness, no live Roblox services or teleport calls.
local shutdownPass, shutdownFail = 0, 0
local function shutdownTest(name, fn)
    local ok, err = pcall(fn)
    if ok then shutdownPass += 1; print("PASS", name)
    else shutdownFail += 1; print("FAIL", name, err) end
end

local function newShutdownStore()
    local history = {}
    local remote = {
        SetAttribute = function(_self, key, value) table.insert(history, {key, value}) end,
        FireAllClients = function(_self, ...) table.insert(history, {...}) end,
    }
    local flushes = 0
    local store = setmetatable({
        Config = {EnableSoftShutdown = true, SoftShutdownPreSaveSeconds = 20,
            SoftShutdownFreezeSeconds = 6, SoftShutdownCloseTimeout = 25, SaveTimeout = 25},
        Metrics = {RestartsScheduled = 0, SoftShutdownFlushes = 0, SoftShutdownFlushFailed = 0},
        Closed = false, Closing = false, Events = {}, SoftShutdownRemote = remote,
        SoftShutdownFrozen = false,
    }, DataStore)
    store._Fire = function() end
    store.FlushAsync = function()
        flushes += 1
        return true
    end
    return store, history, function() return flushes end
end

shutdownTest("Scheduled restart exposes state and remote attributes", function()
    local store, history = newShutdownStore()
    local current = os.time()
    store:_OnServerRestartScheduled({UnixTimestamp = current + 120}, {Name = "DeveloperUpdate"}, {message = "New content!"})
    local status = store:GetSoftShutdownStatus()
    assert(status.Status == "scheduled" and status.RestartAt == current + 120)
    assert(status.Source == "DeveloperUpdate" and status.Message == "New content!")
    assert(not status.Frozen and store.Metrics.RestartsScheduled == 1 and #history >= 5)
end)

shutdownTest("Preflush runs once and final flush freezes mutation", function()
    local store, _, count = newShutdownStore()
    local current = os.time()
    store:_OnServerRestartScheduled({UnixTimestamp = current + 100}, {Name = "DeveloperUpdate"}, {})
    store:_SoftShutdownTick(current + 50)
    assert(count() == 0 and not store.SoftShutdownFrozen)
    store:_SoftShutdownTick(current + 80)
    assert(count() == 1 and store:GetSoftShutdownStatus().PreSaved)
    store:_SoftShutdownTick(current + 81)
    assert(count() == 1, "Preflush repeated")
    store:_SoftShutdownTick(current + 94)
    assert(count() == 2 and store.SoftShutdownFrozen)
    assert(store:GetSoftShutdownStatus().FinalSaved and store:GetSoftShutdownStatus().Status == "ready")
    store:_SoftShutdownTick(current + 100)
    assert(count() == 2 and store.Metrics.SoftShutdownFlushes == 2, "Final flush repeated")
end)

shutdownTest("Failed final save leaves session locked and retries", function()
    local store = newShutdownStore()
    local current = os.time()
    store:_OnServerRestartScheduled({UnixTimestamp = current + 5}, {Name = "RobloxMaintenance"}, {})
    local attempted = 0
    store.FlushAsync = function()
        attempted += 1
        if attempted == 1 then return false, "BUDGET_TIMEOUT" end
        return true
    end
    store:_SoftShutdownTick(current)
    assert(store.SoftShutdownFrozen and store:GetSoftShutdownStatus().Status == "retrying")
    assert(store.Metrics.SoftShutdownFlushFailed == 1 and not store:GetSoftShutdownStatus().FinalSaved)
    store.SoftShutdownState.NextAttempt = 0
    store:_SoftShutdownTick(current + 1)
    assert(attempted == 2 and store:GetSoftShutdownStatus().Status == "ready")
end)

shutdownTest("Restart reschedule resets freeze without releasing ownership", function()
    local store = newShutdownStore()
    local current = os.time()
    store:_OnServerRestartScheduled({UnixTimestamp = current + 4}, {Name = "DeveloperUpdate"}, {})
    store:_SoftShutdownTick(current)
    assert(store.SoftShutdownFrozen)
    store:_OnServerRestartScheduled({UnixTimestamp = current + 100}, {Name = "DeveloperUpdate"}, {message = "Delayed"})
    assert(not store.SoftShutdownFrozen and store:GetSoftShutdownStatus().Status == "scheduled")
end)

shutdownTest("Session mutation is blocked only when final save freezes", function()
    local session = profile()
    local ok = session:Set("Coins", 11)
    assert(ok)
    session.Store.SoftShutdownFrozen = true
    local savedValue = session.Data.Coins
    local allowed, reason = session:Set("Coins", 999)
    assert(not allowed and reason == "SOFT_SHUTDOWN_FROZEN")
    assert(session.Data.Coins == savedValue)
    session.Store.SoftShutdownFrozen = false
    assert(session:Set("Coins", 12))
end)

shutdownTest("Disabled feature ignores restart event and remains idle", function()
    local store = newShutdownStore()
    store.Config.EnableSoftShutdown = false
    store:_OnServerRestartScheduled({UnixTimestamp = os.time() + 5}, {Name = "DeveloperUpdate"}, {})
    assert(store:GetSoftShutdownStatus().Status == "idle" and not store.SoftShutdownFrozen)
end)

print(string.format("Soft shutdown tests: %d passed, %d failed", shutdownPass, shutdownFail))
assert(shutdownFail == 0, "Soft shutdown regression failed")
