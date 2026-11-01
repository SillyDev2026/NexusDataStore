--!strict
-- Studio-only two-server mock. No live DataStore or MessagingService calls.
-- Install beside DataStore ModuleScript with its required PlayersData child.
local DataStore = require(script.Parent:WaitForChild("DataStore"))
local records: {[string]: any} = {}
local calls = 0
local backend: any = {
    UpdateAsync = function(_self, key, transform)
        calls += 1
        local value = transform(records[key])
        if value ~= nil then records[key] = value end
        return records[key]
    end,
    GetAsync = function(_self, key)
        return records[key]
    end,
}
local function createStore(jobId: string)
    local store: any = DataStore.new({
        Name = "NexusHandoffV75Regression",
        Template = {Coins = 0},
        Compression = false,
        AutoSave = false,
        AutoPlayerLifecycle = false,
        DetectDirectChanges = false,
        BudgetAware = false,
        RetryAttempts = 1,
        WaitForSessionLock = true,
        SessionLockRetryInterval = 0.5,
        LoadTimeout = 4,
    })
    store.DataStore = backend
    store.JobId = jobId
    store.Config.EnableSessionHandoff = true
    store.Config.SessionHandoffCooldown = 2
    store.CrossServerSubscription = {Disconnect = function() end}
    return store
end
local owner = createStore("OwnerServer")
local follower = createStore("FollowerServer")
local emitted = 0
local released = 0

owner._Publish = function(_self, event, payload)
    if event ~= "Released" then return end
    released += 1
    follower:_HandleHandoffPacket({Store = owner.Config.Name, Scope = owner.Config.Scope, KeyPrefix = owner.Config.KeyPrefix, JobId = owner.JobId, Event = "Released", At = os.time(), Payload = payload})
end
follower._PublishHandoffRequest = function(_self, key, ownerJob, ownerSession)
    emitted += 1
    owner:_HandleHandoffPacket({Store = owner.Config.Name, Scope = owner.Config.Scope, KeyPrefix = owner.Config.KeyPrefix, JobId = follower.JobId, Event = "HandoffRequest", At = os.time(), Payload = {Key = key, OwnerJobId = ownerJob, OwnerSessionId = ownerSession}})
end

local profile, err = owner:OpenAsync("player_123", {UserId = 123})
assert(profile, "Owner open failed: " .. tostring(err))
assert(profile:Award("Coins", 75))
profile.Player = {Parent = nil}
local newProfile, loadErr = follower:OpenAsync("player_123", {UserId = 123})
assert(newProfile, "Handoff failed: " .. tostring(loadErr))
assert(newProfile.Data.Coins == 75, "Handoff did not persist the owner's latest data")
assert(not profile:IsActive() and newProfile:IsActive(), "Multiple servers retained ownership")
assert(emitted == 1 and released == 1, "Expected one request and one release notification")
assert(follower.Metrics.HandoffWakeups == 1, "Follower did not receive release notice")
assert(newProfile:ReleaseAsync(), "Follower release failed")

-- A still-active owner must not be released by an incoming request.
local active, activeErr = owner:OpenAsync("live_player", {UserId = 123})
assert(active, "Active open failed: " .. tostring(activeErr))
-- Stub uses an arbitrary Parent, which is not an actual Players service.
-- Validate active-player protection via the production handler in a live multi-server test.
active.Player = nil
local forged = {Store = owner.Config.Name, Scope = owner.Config.Scope, KeyPrefix = owner.Config.KeyPrefix, JobId = "intruder", Event = "HandoffRequest", At = os.time(), Payload = {Key = active.Key, OwnerJobId = owner.JobId, OwnerSessionId = active.SessionId}}
owner:_HandleHandoffPacket(forged)
assert(active:IsActive(), "Non-player profile was unexpectedly released")
assert(active:ReleaseAsync(), "Active profile release failed")

-- Lock expiration recovery remains exclusively guarded by UpdateAsync.
local crashed, crashErr = owner:OpenAsync("crash", {UserId = 123})
assert(crashed, "Recovery setup failed: " .. tostring(crashErr))
assert(crashed:Award("Coins", 50))
assert(crashed:SaveAsync("high"))
local raw = records.crash
assert(raw and raw.Lock, "Mock lock missing")
raw.Lock.ExpiresAt = os.time() - 1
local recovered, recoveryErr = follower:OpenAsync("crash", {UserId = 123})
assert(recovered, "Expired lock not recoverable: " .. tostring(recoveryErr))
assert(recovered.Data.Coins == 50, "Recovery lost previously committed progress")
local oldOK = crashed:SaveAsync("high")
-- A clean save may not issue UpdateAsync: force a dirty write to verify fencing.
assert(crashed:Award("Coins", 1))
local fenced, fencedErr = crashed:SaveAsync("high")
assert(not fenced and (fencedErr == "SESSION_LOST" or fencedErr == "REVISION_CONFLICT"), "Expired owner overwrote successor: " .. tostring(fencedErr))
assert(recovered:ReleaseAsync(), "Recovered owner release failed")
assert(owner:CloseAsync(4) and follower:CloseAsync(4), "Mock server cleanup failed")
print("NexusDataStore v7.5.0 handoff and recovery regression PASS", calls, emitted, released)
