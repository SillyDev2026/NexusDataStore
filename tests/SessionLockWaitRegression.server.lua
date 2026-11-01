--!strict
-- Two-server contention regression using a shared mocked backend.
-- Run as a Studio server Script beside DataStore (with PlayersData child).
local DataStore = require(script.Parent:WaitForChild("DataStore"))
local backing: {[string]: any} = {}
local backend: any = {
    UpdateAsync = function(_self, key, transform)
        local candidate = transform(backing[key])
        if candidate ~= nil then backing[key] = candidate end
        return backing[key]
    end,
    GetAsync = function(_self, key)
        return backing[key]
    end,
}
local function createStore(jobId: string, waitForLock: boolean)
    local store: any = DataStore.new({
        Name = "NexusSessionLockWaitRegression",
        Template = {Coins = 0},
        Compression = false,
        AutoSave = false,
        AutoPlayerLifecycle = false,
        DetectDirectChanges = false,
        BudgetAware = false,
        RetryAttempts = 1,
        WaitForSessionLock = waitForLock,
        SessionLockRetryInterval = 0.5,
        LoadTimeout = 5,
    })
    store.DataStore = backend
    store.JobId = jobId
    return store
end

local first = createStore("MockJobA", false)
local second = createStore("MockJobB", false)

local firstProfile, firstErr = first:OpenAsync("transfer", {UserId = 123})
assert(firstProfile, "First server failed to acquire: " .. tostring(firstErr))
local blocked, blockedErr = second:OpenAsync("transfer", {UserId = 123})
assert(blocked == nil and blockedErr == "SESSION_LOCKED", "Second server bypassed the active lock")

second.Config.WaitForSessionLock = true
second.Config.SessionLockRetryInterval = 0.02
local finished = false
local acquired: any = nil
local acquireErr: any = nil
task.spawn(function()
    acquired, acquireErr = second:OpenAsync("transfer", {UserId = 123})
    finished = true
end)
task.wait(0.08)
assert(not finished and second.Metrics.SessionLockRetries > 0, "Second server did not wait for lock release")
assert(firstProfile:ReleaseAsync(), "First server failed to release")

for _ = 1, 100 do
    if finished then break end
    task.wait(0.02)
end
assert(finished and acquired ~= nil, "Second server did not acquire after release: " .. tostring(acquireErr))
assert(acquired:IsActive() and first.Sessions.transfer == nil, "Session ownership overlapped")
assert(acquired:ReleaseAsync(), "Second server failed to release")

local own, ownErr = first:OpenAsync("context", {UserId = 11})
assert(own, "Local context test failed to open: " .. tostring(ownErr))
local repeated, repeatedErr = first:OpenAsync("context", {UserId = 11})
assert(repeated == own and repeatedErr == nil, "Identical caller lost its local session")
local conflicting, conflictErr = first:OpenAsync("context", {UserId = 22})
assert(conflicting == nil and conflictErr == "SESSION_CONTEXT_CONFLICT", "Different user reused the active local session")
assert(own:ReleaseAsync(), "Local context test failed to release")

local held, heldErr = first:OpenAsync("timeout", {UserId = 123})
assert(held, "Timeout test failed to open: " .. tostring(heldErr))
second.Config.LoadTimeout = 0.12
local unavailable, timeoutErr = second:OpenAsync("timeout", {UserId = 123})
assert(unavailable == nil and (timeoutErr == "SESSION_LOCK_WAIT_TIMEOUT" or timeoutErr == "LOAD_TIMEOUT"), "Wait ignored bounded load deadline: " .. tostring(timeoutErr))
assert(held:ReleaseAsync(), "Timeout test failed to release")

local closing, closingErr = first:OpenAsync("closing", {UserId = 123})
assert(closing, "Close cancellation test failed to open: " .. tostring(closingErr))
second.Config.LoadTimeout = 5
local aborted = false
local abortResult: any = nil
task.spawn(function()
    local unused, err = second:OpenAsync("closing", {UserId = 123})
    assert(unused == nil, "Store acquired after shutdown began")
    abortResult = err
    aborted = true
end)
task.wait(0.04)
local closed, closeErr = second:CloseAsync(5)
assert(closed, "Closing a waiting store failed: " .. tostring(closeErr))
for _ = 1, 100 do
    if aborted then break end
    task.wait(0.02)
end
assert(aborted and abortResult == "STORE_CLOSING", "Waiting open ignored store shutdown: " .. tostring(abortResult))
assert(closing:ReleaseAsync(), "Closing test failed to release owner")
assert(first:CloseAsync(5), "First mock store could not close")
print("NexusDataStore v7.4.0 session contention regression PASS")
