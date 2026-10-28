--!strict
-- Studio-only regression: schema migration, reconciliation, validation, and decode failure.
-- Place next to the DataStore ModuleScript (with PlayersData child); no live backend.
local DataStore = require(script.Parent:WaitForChild("DataStore"))
local oldSource: any = nil

local store: any = DataStore.new({
    Name = "NexusSchemaMigrationRegression",
    Template = {Coins = 0, Prestige = 0, Settings = {Music = true}},
    SchemaVersion = 2,
    Migrations = {
        [2] = function(data, context)
            assert(context.FromVersion == 1 and context.ToVersion == 2)
            data.Prestige = 7
            return data
        end,
    },
    Schema = {
        Coins = {Type = "integer", Min = 0},
        Prestige = {Type = "integer", Min = 0, Max = 100},
        Settings = {Type = "table", Children = {Music = {Type = "boolean"}}},
    },
    Compression = false,
    AutoSave = false,
    AutoPlayerLifecycle = false,
    BudgetAware = false,
})
oldSource = store:_BuildNewRecord({Coins = 45})
oldSource.SchemaVersion = 1
local updates = 0
store.DataStore = {
    UpdateAsync = function(_self, key, callback)
        assert(key == "schema_1")
        updates += 1
        local updated = callback(oldSource)
        if updated ~= nil then oldSource = updated end
        return oldSource
    end,
    GetAsync = function(_self, key)
        assert(key == "schema_1")
        return oldSource
    end,
}
local profile, errorCode = store:OpenAsync("schema_1")
assert(profile and errorCode == nil, tostring(errorCode))
assert(profile.Data.Coins == 45 and profile.Data.Prestige == 7, "Migration erased player data")
assert(profile.Data.Settings.Music == true, "Template reconciliation did not apply")
assert(profile.SchemaVersion == 2, "Session has outdated schema")
local current = store:_DecodeRecord(oldSource)
assert(current and current.SchemaVersion == 2 and current.Data.Prestige == 7, "Backend record did not migrate")
local rejected, validationError = profile:Set("Prestige", 999)
assert(not rejected and string.find(tostring(validationError), "VALIDATION_FAILED", 1, true), "Schema upper bound not enforced")
assert(profile.Data.Prestige == 7, "Rejected schema mutation changed active record")
assert(profile:ReleaseAsync())
assert(store:CloseAsync())
assert(updates == 2, "Unexpected migration/release writes")

-- An unavailable migration must not silently create or save replacement data.
local missingStore: any = DataStore.new({
    Name = "NexusMissingMigrationRegression",
    Template = {Coins = 0, Prestige = 0},
    SchemaVersion = 2,
    Compression = false,
    AutoSave = false,
    AutoPlayerLifecycle = false,
    BudgetAware = false,
})
local legacy = missingStore:_BuildNewRecord({Coins = 999})
legacy.SchemaVersion = 1
local wroteReplacement = false
missingStore.DataStore = {
    UpdateAsync = function(_self, _key, callback)
        local replacement = callback(legacy)
        if replacement ~= nil then wroteReplacement = true end
        return legacy
    end,
}
local missingProfile, missingError = missingStore:OpenAsync("legacy_1")
assert(missingProfile == nil and missingError == "MIGRATION_MISSING:2", "Absent migration did not fail safely")
assert(not wroteReplacement and legacy.Data.Coins == 999 and legacy.SchemaVersion == 1, "Failed migration destroyed saved data")
assert(missingStore:CloseAsync())

-- Corrupt records should fail before profile construction.
local bad = store:_BuildNewRecord({Coins = 5, Prestige = 0, Settings = {Music = true}})
bad.Format = 999
local decoded, decoderError = store:_DecodeRecord(bad)
assert(decoded == nil and decoderError == "UNSUPPORTED_RECORD_FORMAT")
print("NexusDataStore schema, migration, corruption prevention regression PASS")
