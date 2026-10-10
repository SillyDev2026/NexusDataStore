--!strict
-- Place beside DataStore ModuleScript; DataStore has a PlayersData child.
-- Intentionally does not perform external DataStore requests.
local DataStore = require(script.Parent:WaitForChild("DataStore"))
local store: any = DataStore.new({
    Name = "NexusCloseRecoveryRegression",
    Template = {Coins = 0},
    Compression = false,
    AutoSave = false,
    AutoPlayerLifecycle = false,
    DetectDirectChanges = false,
})
local fakeSession: any = {Key = "regression-key", Active = true}
function fakeSession:IsActive(): boolean
    return self.Active
end
store.Sessions[fakeSession.Key] = fakeSession

local closeAttempts = 0
store.ReleaseAsync = function(_self, _session)
    closeAttempts += 1
    return false, "INJECTED_RELEASE_FAILURE"
end
local ok, err = store:CloseAsync(5)
assert(not ok and err == "INJECTED_RELEASE_FAILURE", "Failed close should report release error")
assert(not store.Closed and not store.Closing, "Failed close must leave store recoverable")
assert(store.Sessions[fakeSession.Key] == fakeSession, "Failed session vanished")
assert(closeAttempts == 1, "Expected one failed release")

store.ReleaseAsync = function(self, session)
    session.Active = false
    self.Sessions[session.Key] = nil
    return true
end
local recovered, recoveryErr = store:CloseAsync(5)
assert(recovered and recoveryErr == nil, "Close retry failed")
assert(store.Closed and not store.Closing, "Successful close did not finish")
assert(not store.Sessions[fakeSession.Key], "Successful close left session registered")
print("NexusDataStore v7.0.4 shutdown recovery regression PASS")
