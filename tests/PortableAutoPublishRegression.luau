--!strict
-- Portable tests use mocked Roblox services. These cannot validate real published-version signals.
local autoPassed, autoFailed = 0, 0
local function autoTest(name, callback)
    local ok, err = pcall(callback)
    if ok then autoPassed += 1; print("PASS", name)
    else autoFailed += 1; print("FAIL", name, err) end
end

local function newAutoStore()
    local store = newShutdownStore()
    store.Config.AutoRestartOnPublish = true
    store.Config.AutoPublishCountdownSeconds = 45
    store.Config.AutoPublishPollInterval = 60
    store.Metrics.AutoPublishChecks = 0
    store.Metrics.AutoPublishCheckFailed = 0
    store.Metrics.AutoPublishDetected = 0
    store.Metrics.AutoPublishTeleportAttempts = 0
    store.Metrics.AutoPublishTeleportFailed = 0
    store.AutoPublishCandidatesSeen = 0
    store.AutoPublishTeleportBusy = false
    return store
end

autoTest("Opt-out store does not query published asset version", function()
    local store = newAutoStore()
    store.Config.AutoRestartOnPublish = false
    local result, reason = store:_CheckAutoPublishVersion()
    assert(not result and reason == "NOT_MONITORING")
end)

autoTest("First asset version is baseline, not an update", function()
    local store = newAutoStore()
    services.InsertService.GetLatestAssetVersionAsync = function() return 4501 end
    local result, reason = store:_CheckAutoPublishVersion()
    assert(not result and reason == "BASELINE_READY")
    assert(store.AutoPublishBaseline == 4501 and store.SoftShutdownState == nil)
end)

autoTest("Changed asset needs two stable observations and ignores one-off noise", function()
    local store = newAutoStore()
    local version = 100
    services.InsertService.GetLatestAssetVersionAsync = function() return version end
    store:_CheckAutoPublishVersion()
    version = 101
    local detected, reason = store:_CheckAutoPublishVersion()
    assert(not detected and reason == "CANDIDATE_CHANGED")
    version = 100
    store:_CheckAutoPublishVersion()
    assert(store.AutoPublishCandidate == nil and store.SoftShutdownState == nil)
end)

autoTest("After two changed readings, schedule coordinated save and countdown", function()
    local store = newAutoStore()
    local version = 4501
    services.InsertService.GetLatestAssetVersionAsync = function() return version end
    DateTime = {fromUnixTimestamp = function(timestamp) return {UnixTimestamp = timestamp} end}
    store:_CheckAutoPublishVersion()
    version = 4502
    assert(not store:_CheckAutoPublishVersion())
    assert(store:_CheckAutoPublishVersion())
    assert(store.SoftShutdownState.Source == "AutoPublish")
    assert(store.SoftShutdownState.RestartAt >= os.time() + 43)
    assert(not store.SoftShutdownFrozen and not store.SoftShutdownState.FinalSaved)
    assert(store.Metrics.AutoPublishDetected == 1)
end)

autoTest("Failed version check cannot cause migration", function()
    local store = newAutoStore()
    services.InsertService.GetLatestAssetVersionAsync = function() error("NOT_AVAILABLE") end
    local ok, reason = store:_CheckAutoPublishVersion()
    assert(not ok and reason == "VERSION_QUERY_FAILED")
    assert(store.SoftShutdownState == nil and store.Metrics.AutoPublishCheckFailed == 1)
end)

autoTest("A failed or pending final save prevents teleportation", function()
    local store = newAutoStore()
    store:_OnServerRestartScheduled({UnixTimestamp = os.time() - 2}, {Name = "AutoPublish"}, {})
    services.Players.GetPlayers = function() return {} end
    store:_AutoPublishTeleportTick(os.time())
    assert(not store.SoftShutdownState.TeleportAttempted)
    store.FlushAsync = function() return false, "BUDGET_ERROR" end
    store:_SoftShutdownTick(os.time())
    store:_AutoPublishTeleportTick(os.time())
    assert(not store.SoftShutdownState.TeleportAttempted)
end)

autoTest("After final save, a fresh reserved server is used for the teleport", function()
    local store = newAutoStore()
    local now = os.time()
    store:_OnServerRestartScheduled({UnixTimestamp = now - 1}, {Name = "AutoPublish"}, {})
    store.SoftShutdownState.FinalSaved = true
    local player = {Parent = services.Players}
    services.Players.GetPlayers = function() return {player} end
    game.PlaceId = 123456
    Instance = {new = function(class) assert(class == "TeleportOptions"); return {} end}
    services.HttpService.GenerateGUID = function() return "unique-private-destination" end
    local calls = 0
    services.TeleportService.TeleportAsync = function(_self, placeId, players, options)
        calls += 1
        assert(placeId == 123456 and #players == 1)
        assert(options.ReservedServerId == "unique-private-destination")
    end
    store:_AutoPublishTeleportTick(now)
    assert(calls == 1 and store.SoftShutdownState.Status == "moving")
    assert(store.Metrics.AutoPublishTeleportAttempts == 1)
    store:_AutoPublishTeleportTick(now + 1)
    assert(calls == 1, "Duplicate teleport while already in progress")
end)

autoTest("Teleport initiation failure leaves sessions in old server and schedules retry", function()
    local store = newAutoStore()
    local now = os.time()
    store:_OnServerRestartScheduled({UnixTimestamp = now - 1}, {Name = "AutoPublish"}, {})
    store.SoftShutdownState.FinalSaved = true
    local player = {Parent = services.Players}
    services.Players.GetPlayers = function() return {player} end
    services.TeleportService.TeleportAsync = function() error("NETWORK_FAILURE") end
    store:_AutoPublishTeleportTick(now)
    assert(store.SoftShutdownState.Status == "teleport-retrying")
    assert(store.SoftShutdownState.TeleportStarted == false)
    assert(store.Metrics.AutoPublishTeleportFailed == 1)
    assert(not store.Closing and not store.Closed, "Old server was shut down despite failure")
end)

print(string.format("Auto-publish tests: %d passed, %d failed", autoPassed, autoFailed))
assert(autoFailed == 0, "Auto publish regression failed")
