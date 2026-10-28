--!strict
-- Studio-only regression for v7.2 migration previews, forecast, and bounded journal.
-- Place beside DataStore (with PlayersData child). No live DataStore calls.
local DataStore = require(script.Parent:WaitForChild("DataStore"))
local store: any = DataStore.new({
	Name = "NexusDeveloperToolsRegression",
	Template = {Coins = 0, Stats = {Level = 1}, Inventory = {}},
	SchemaVersion = 2,
	Migrations = {
		[2] = function(data, context)
			assert(context.FromVersion == 1 and context.ToVersion == 2)
			data.Stats = {Level = 8}
			return data
		end,
	},
	Compression = false,
	AutoSave = false,
	AutoPlayerLifecycle = false,
	BudgetAware = false,
	SkipUnchangedMutations = true,
	ChangeJournalLimit = 2,
})
assert(store:GetVersion() == "7.2.0")
local original = {Coins = 55}
local preview, previewErr = store:PreviewMigration(original, 1, "User_42")
assert(preview ~= nil and previewErr == nil, tostring(previewErr))
assert(original.Coins == 55 and original.Stats == nil, "Preview mutated caller's original data")
assert(preview.FromVersion == 1 and preview.ToVersion == 2 and preview.Changed)
assert(preview.Data.Coins == 55 and preview.Data.Stats.Level == 8, "Preview did not reconcile correctly")
assert(#preview.Changes >= 1, "Expected a migration diff")
preview.Data.Coins = 500
assert(original.Coins == 55, "Returned preview shares caller data")
local repeatPreview = store:PreviewMigration(original, 1)
assert(repeatPreview and repeatPreview.Data.Coins == 55, "Previous preview mutated migration state")

local badVersion, badError = store:PreviewMigration(original, -1)
assert(badVersion == nil and badError == "INVALID_SCHEMA_VERSION")
local badKey, keyError = store:PreviewMigration(original, 1, "")
assert(badKey == nil and keyError == "INVALID_PREVIEW_KEY")
local badData, dataError = store:PreviewMigration({Coins = math.huge}, 2)
assert(badData == nil and typeof(dataError) == "string", "Preview accepted nonfinite data")

local missing: any = DataStore.new({
	Name = "NexusMissingPreviewRegression",
	Template = {Coins = 0}, SchemaVersion = 2,
	Compression = false, AutoSave = false, AutoPlayerLifecycle = false, BudgetAware = false,
})
local failed, missingErr = missing:PreviewMigration({Coins = 999}, 1)
assert(failed == nil and missingErr == "MIGRATION_MISSING:2", "Missing migration did not fail")
assert(missing:CloseAsync())

local forecast, forecastErr = store:GetStorageForecast({Coins = 10, Stats = {Level = 8}, Inventory = {}}, 0.01)
assert(forecast ~= nil and forecastErr == nil, tostring(forecastErr))
assert(forecast.StorageBytes > 0 and forecast.RemainingBytes > 0, "Forecast returned invalid sizes")
assert(forecast.CapacityBytes == store.Config.MaxStoredBytes)
assert(forecast.Utilization == forecast.StorageBytes / forecast.CapacityBytes)
assert(forecast.NearLimit == forecast.Utilization >= 0.01)
local invalidRatio, invalidRatioErr = store:GetStorageForecast(store:GetTemplate(), 1.2)
assert(invalidRatio == nil and invalidRatioErr == "INVALID_WARNING_RATIO")
local invalidValue, invalidValueErr = store:GetStorageForecast({Coins = math.huge})
assert(invalidValue == nil and invalidValueErr ~= nil, "Forecast failed to reject nonserializable values")

local record = store:_BuildNewRecord(store:GetTemplate())
local session: any = store:_CreateSession("session", record, "test-guid", {})
local lockedForecast = store:GetStorageForecast(session)
assert(lockedForecast and lockedForecast.IncludesSessionLock, "Session forecast ignored lock overhead")
assert(lockedForecast.StorageBytes >= forecast.StorageBytes, "Session lock should not decrease JSON storage size")
assert(#session:GetChangeJournal() == 0, "Journal should start empty")
assert(session:Set("Coins", 10))
assert(session:Set("Coins", 20))
assert(session:Set("Coins", 30))
local journal = session:GetChangeJournal()
assert(#journal == 2 and journal[1].MutationId == 2 and journal[2].MutationId == 3, "Journal ring size/order incorrect")
assert(journal[2].Path[1] == "Coins", "Journal lost the changed path")
journal[2].Path[1] = "malicious"
assert(session:GetChangeJournal(1)[1].Path[1] == "Coins", "Journal returned live references")
assert(session:GetChangeJournal(0)[1] == nil, "Zero journal limit should be empty")
assert(session:Set("Coins", 30))
assert(#session:GetChangeJournal() == 2 and session.MutationId == 3, "No-op wrote journal entry")
assert(session:Mutate(function(draft) draft.Coins = 40 return true end))
local latest = session:GetChangeJournal(1)
assert(latest[1].MutationId == 4 and latest[1].Path == nil, "Whole-profile mutation should be journaled as a summary")
assert(session:ClearChangeJournal() == 2 and #session:GetChangeJournal() == 0, "Journal clear failed")
session.Active = false
store:_UnregisterSession(session)
assert(store:CloseAsync())
print("NexusDataStore v7.2.0 migration preview, storage forecast and bounded journal regression PASS")
