-- Actual Session and validation methods, with no remote services or background loops.
local passed, failed = 0, 0
local function test(name, callback)
    local ok, err = pcall(callback)
    if ok then passed += 1; print("PASS", name) else failed += 1; print("FAIL", name, err) end
end
local function profile(options)
    local config = {DetectDirectChanges = true, ValidateOnWrite = true, ProfileOperations = false, ChangeJournalLimit = 0, SkipUnchangedMutations = false, MaxDepth = 64, MaxDataNodes = 50000, MaxDataBytes = 3900000, EnforceTemplateTypes = false, AutoSaveInterval = 30}
    for key, value in pairs(options or {}) do config[key] = value end
    local store = setmetatable({Config = config, Closed = false, Sessions = {}, SessionById = {}, SessionByPlayer = {}, Events = {}, Metrics = {Mutations = 0, Transactions = 0, NoopMutations = 0, TypeErrors = 0}, SchemaVersion = 1}, DataStore)
    return store:_CreateSession("test", store:_BuildNewRecord({Coins = 10, Other = 20, Inventory = {"Potion"}}), "session", {})
end

test("Mutate detaches retained draft and returned nested table", function()
    local session = profile({DetectDirectChanges = false})
    local retained
    local ok, result = session:Mutate(function(draft)
        retained = draft
        draft.Coins = 11
        return draft.Inventory
    end)
    assert(ok)
    retained.Coins = 999
    result[1] = "injected"
    assert(session.Data.Coins == 11 and session.Data.Inventory[1] == "Potion", "Callback retains live data ownership")
end)

test("UpdatePath captures caller path before callback", function()
    local session = profile()
    local path = {"Coins"}
    local ok = session:UpdatePath(path, function(value) path[1] = "Other"; return value + 1 end)
    assert(ok and session.Data.Coins == 11 and session.Data.Other == 20, "Callback redirected or invalidated path")
end)

test("Mutate rechecks lifecycle before no-op success", function()
    local session = profile({SkipUnchangedMutations = true})
    local ok, err = session:Mutate(function() session.Releasing = true end)
    assert(not ok and err == "SESSION_RELEASING", "Released callback reported success")
end)

test("UpdatePath rejects malformed path without throwing", function()
    local session = profile()
    local called = false
    local ok, err = session:UpdatePath({}, function() called = true; return 1 end)
    assert(not ok and string.find(err, "INVALID_PATH:", 1, true) == 1 and not called)
end)

test("Mutate preserves tracked concurrent changes", function()
    local session = profile()
    local ok, err = session:Mutate(function(draft) assert(session:Set("Coins", 12)); draft.Coins = 999 end)
    assert(not ok and err == "CONCURRENT_MUTATION" and session.Data.Coins == 12)
end)

test("Mutate validation failure is atomic", function()
    local session = profile()
    local ok = session:Mutate(function(draft) draft.Coins = math.huge end)
    assert(not ok and session.Data.Coins == 10 and session.MutationId == 0)
end)

test("SetDefault inserts isolated defaults and preserves false", function()
    local session = profile()
    local fallback = {Enabled = false}
    local ok, value, inserted = session:SetDefault("Settings", fallback)
    assert(ok and inserted and value.Enabled == false)
    fallback.Enabled = true
    value.Enabled = true
    assert(session.Data.Settings.Enabled == false)
    local id = session.MutationId
    local exists, current, added = session:SetDefault({"Settings", "Enabled"}, true)
    assert(exists and current == false and added == false and session.MutationId == id)
end)

test("SetDefault rejects invalid defaults and inactive sessions", function()
    local session = profile()
    assert(not session:SetDefault("Missing", nil))
    assert(not session:SetDefault({}, 2))
    local cycle = {}; cycle.Self = cycle
    assert(not session:SetDefault("Missing", cycle))
    assert(session.Data.Missing == nil and session.MutationId == 0)
    session.Active = false
    local ok, err = session:SetDefault("Coins", 5)
    assert(not ok and err == "SESSION_INACTIVE")
end)

test("GetDataSnapshot isolates data without consuming restore slots", function()
    local session = profile()
    local snapshot = session:GetDataSnapshot()
    snapshot.Inventory[1] = "changed"
    assert(session.Data.Inventory[1] == "Potion" and #session.Snapshots == 0)
    assert(session.MutationId == 0 and not session.Dirty)
end)

test("UpdatePath rechecks lifecycle on cancellation", function()
    local session = profile()
    local ok, err = session:UpdatePath("Coins", function() session.Active = false; return nil end)
    assert(not ok and err == "SESSION_INACTIVE")
end)

test("Mutate cancellation discards draft", function()
    local session = profile()
    local ok, _, status = session:Mutate(function(draft) draft.Coins = 0; return false end)
    assert(ok and status == "CANCELLED" and session.Data.Coins == 10 and session.MutationId == 0)
end)

test("SetDefault preserves zero and reports validation errors", function()
    local session = profile()
    assert(session:Set("Coins", 0))
    local ok, value, inserted = session:SetDefault("Coins", 100)
    assert(ok and value == 0 and not inserted)
    local success = session:SetDefault("Bad", math.huge)
    assert(not success and session.Data.Bad == nil)
end)

test("SetDefault rejects invalid parent without partial changes", function()
    local session = profile()
    local ok = session:SetDefault({"Coins", "Child"}, 2)
    assert(not ok and session.Data.Coins == 10 and session.MutationId == 0)
end)

test("Mutate rejects cyclic drafts without changing live data", function()
    local session = profile()
    local ok, err = session:Mutate(function(draft) draft.Self = draft end)
    assert(not ok and string.find(err, "INVALID_MUTATION_DRAFT:", 1, true) == 1)
    assert(session.Data.Self == nil and session.MutationId == 0)
end)

test("Mutate rechecks lifecycle before cancellation", function()
    local session = profile()
    local ok, err = session:Mutate(function() session.Active = false; return false end)
    assert(not ok and err == "SESSION_INACTIVE")
end)

test("UpdatePath captures paths with direct detection disabled", function()
    local session = profile({DetectDirectChanges = false})
    local path = {"Coins"}
    assert(session:UpdatePath(path, function(value) path[1] = "Other"; return value + 3 end))
    assert(session.Data.Coins == 13 and session.Data.Other == 20)
end)

test("10,000 mixed operations preserve model and detached values", function()
    local session = profile({SkipUnchangedMutations = true})
    local expected = 10
    for index = 1, 10000 do
        local operation = index % 5
        if operation == 0 then
            assert(session:Increment("Coins", 2))
            expected += 2
        elseif operation == 1 then
            assert(session:Mutate(function(draft) draft.Coins += 3 end))
            expected += 3
        elseif operation == 2 then
            assert(session:UpdatePath("Coins", function(value) return value - 1 end))
            expected -= 1
        elseif operation == 3 then
            local ok, value, inserted = session:SetDefault("Coins", 999)
            assert(ok and value == expected and not inserted)
        else
            local copy = session:GetDataSnapshot()
            copy.Coins = -999
            copy.Inventory[1] = "external"
        end
        assert(session.Data.Coins == expected and session.Data.Inventory[1] == "Potion")
    end
end)

test("Handoff request releases only detached matching sessions", function()
    local session = profile()
    local store = session.Store
    store.Config.Name = "HandoffTest"
    store.Config.Scope = "Global"
    store.Config.KeyPrefix = ""
    store.Config.EnableSessionHandoff = true
    store.JobId = "owner-job"
    store.HandoffWakeGeneration = {}
    store.Metrics.HandoffRequestsDeclined = 0
    store.Metrics.HandoffReleaseAttempts = 0
    store.Metrics.HandoffReleaseFailed = 0
    store.Metrics.HandoffWakeups = 0
    session.Player = {Parent = nil}
    local calls = 0
    store.ReleaseAsync = function(_self, target)
        assert(target == session)
        calls += 1
        target.Active = false
        return true
    end
    local packet = {Store = "HandoffTest", Scope = "Global", KeyPrefix = "", JobId = "new-job", Event = "HandoffRequest", At = os.time(), Payload = {Key = "test", OwnerJobId = "owner-job", OwnerSessionId = "session"}}
    local wrong = table.clone(packet)
    wrong.Scope = "Other"
    store:_HandleHandoffPacket(wrong)
    wrong = table.clone(packet)
    wrong.Payload = {Key = "test", OwnerJobId = "owner-job", OwnerSessionId = "wrong"}
    store:_HandleHandoffPacket(wrong)
    wrong = table.clone(packet)
    wrong.At = os.time() - 120
    store:_HandleHandoffPacket(wrong)
    assert(calls == 0, "Unauthorized request released a profile")
    store:_HandleHandoffPacket(packet)
    assert(calls == 1 and not session.Active and store.Metrics.HandoffReleaseAttempts == 1)
    store:_HandleHandoffPacket(packet)
    assert(calls == 1, "Duplicate release attempt")
end)

test("Released notifications wake waiters without changing ownership", function()
    local session = profile()
    local store = session.Store
    store.Config.Name = "HandoffTest"
    store.Config.Scope = "Global"
    store.Config.KeyPrefix = ""
    store.Config.EnableSessionHandoff = true
    store.JobId = "waiting-job"
    store.HandoffWakeGeneration = {test = 0}
    store.Metrics.HandoffWakeups = 0
    local good = {Store = "HandoffTest", Scope = "Global", KeyPrefix = "", JobId = "owner-job", Event = "Released", At = os.time(), Payload = {Key = "test"}}
    store:_HandleHandoffPacket(good)
    assert(store.HandoffWakeGeneration.test == 1 and session:IsActive() and store.Metrics.HandoffWakeups == 1)
    local stale = table.clone(good)
    stale.At = os.time() - 600
    store:_HandleHandoffPacket(stale)
    local selfMessage = table.clone(good)
    selfMessage.JobId = "waiting-job"
    store:_HandleHandoffPacket(selfMessage)
    assert(store.HandoffWakeGeneration.test == 1, "Untrusted notification triggered retry")
end)

print(string.format("Behavioral tests: %d passed, %d failed", passed, failed))
assert(failed == 0, "Behavioral regressions failed")
