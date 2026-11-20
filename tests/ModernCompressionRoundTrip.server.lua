--!strict
-- Roblox Studio integration test: place beside Compression and CompressionLatest ModuleScripts.
-- Does not touch live DataStore keys.
local Legacy = require(script.Parent:WaitForChild("Compression"))
local Modern = require(script.Parent:WaitForChild("CompressionLatest"))
assert(Legacy.Version() == "2.6.1", "Unexpected legacy compression version")
assert(Modern.Version() == "2.6.5", "Unexpected modern compression version")

local cases = {
	{Coins = 0, Gems = 100, Inventory = {}, Settings = {Music = true, SFX = false}},
	{Coins = 123456789, Rebirths = 999, Inventory = {"Dragon", "Dragon", "Potion", "Dragon"}},
	{Upgrades = {Speed = 100, Luck = 9999}, Quest = {Steps = {1, 1, 1, 1, 2, 2, 2}}},
	{Stats = {Wins = 4, Clicks = 150000}, Names = {"alpha", "beta", "alpha"}},
}

local function same(a: any, b: any): boolean
	if typeof(a) ~= typeof(b) then return false end
	if typeof(a) ~= "table" then return a == b end
	for k, value in pairs(a) do if not same(value, b[k]) then return false end end
	for k in pairs(b) do if a[k] == nil then return false end end
	return true
end

for index, value in ipairs(cases) do
	local legacyData = Legacy.CompressTablePacket(value, {CompactEncoding = true, RunLengthArrays = true})
	local modernPacket = Modern.CompressTablePacket(value, {UseStringDictionary = true, RunLengthArrays = true, EntropyCoding = true, EntropyStrategy = "Auto"})
	assert(typeof(legacyData) == "buffer", "Legacy packet not a buffer")
	assert(typeof(modernPacket) == "table" and typeof(modernPacket.Data) == "buffer", "Modern packet shape unexpected")
	assert(same(value, Legacy.DecompressTable(legacyData)), "Legacy round-trip failed: " .. index)
	assert(same(value, Modern.DecompressTable(modernPacket.Data)), "Modern round-trip failed: " .. index)
end

print("PASS: Modern 2.6.5 and legacy 2.6.1 table packet round-trips")
