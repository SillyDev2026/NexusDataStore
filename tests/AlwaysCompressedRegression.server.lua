--!strict
-- Studio-only comprehensive forced compression policy regression (mock backend).
-- Place beside DataStore ModuleScript with PlayersData and Compression children.
local DataStore = require(script.Parent:WaitForChild("DataStore"))
local Compression = require(script.Parent:WaitForChild("Compression"))
local cases = {
    {Name = "empty", Data = {}},
    {Name = "tiny", Data = {Coins = 1}},
    {Name = "booleans", Data = {Flags = table.create(64, true)}},
    {Name = "nested", Data = {Stats = {Wins = 1, Losses = 0, Enabled = false}, Inventory = {"Sword", "Sword", "Potion"}}},
    {Name = "randomlike", Data = {Text = ""}},
    {Name = "fractional", Data = {Money = 0.000123, Power = 3.141592653589793, Large = 9007199254740991}},
}
local bytes = {}
for i = 1, 320 do bytes[i] = string.char(33 + (i * 73 + i * i * 11) % 90) end
cases[5].Data.Text = table.concat(bytes)

local function makeStore(name: string, extra: {[string]: any}): any
    local config: any = {
        Name = name,
        Template = {Coins = 0, Flags = {}, Inventory = {}, Text = "", Stats = {}, Money = 0},
        Compression = true,
        CompressionModule = script.Parent:WaitForChild("Compression"),
        CompressionPolicy = "always-smallest",
        CompressionStrategy = "balanced",
        CompressionMinBytes = 999999,
        CompressionTransport = "auto",
        CompressionReports = true,
        BudgetAware = false,
        AutoSave = false,
        DetectDirectChanges = false,
        MaxStoredBytes = 100000,
    }
    for key, value in pairs(extra) do config[key] = value end
    return DataStore.new(config)
end

local store = makeStore("NexusAlwaysCompressedV77", {})
assert(store.Config.CompressionPolicy == "always-smallest")
local attempts = 0
local persisted: any = nil
for _, fixture in ipairs(cases) do
    local record = store:_BuildNewRecord(fixture.Data)
    local encoded, err, report = store:_EncodeRecord(record)
    assert(encoded and report, fixture.Name .. ": " .. tostring(err))
    assert(encoded.Compressed == true and (encoded.Codec == 230 or encoded.Codec == 231), "Uncompressed record: " .. fixture.Name)
    assert(report.PersistedCompressed and report.AlternativeCodecCandidates == 4)
    assert(report.SelectionReason == "always-compressed-smallest")
    assert(report.CompressionExpanded == (report.StorageBytes > report.RawStorageEstimate))
    assert(report.ExpansionBytes == math.max(0, report.StorageBytes - report.RawStorageEstimate))
    local decoded, decodeErr = store:_DecodeRecord(encoded)
    assert(decoded, fixture.Name .. ": " .. tostring(decodeErr))
    assert(decoded.Data ~= fixture.Data and decoded.Format == 700)
    local packedCodec = buffer.readu16(encoded.Encoding == "buffer" and encoded.Payload or game:GetService("EncodingService"):Base64Decode(buffer.fromstring(encoded.Payload)), 4)
    assert(packedCodec == encoded.Codec)
    -- Verify best measured persisted bytes across the four codec/dictionary modes.
    local minimum = math.huge
    for _, compact in ipairs({false, true}) do
        for _, dictionary in ipairs({false, true}) do
            local packet = Compression.CompressTablePacket(record, {CompactEncoding = compact, StringDictionary = dictionary})
            local envelope = {Format = 700, Codec = compact and 231 or 230, Compressed = true, Encoding = "buffer", Payload = packet}
            local measure = #game:GetService("HttpService"):JSONEncode(envelope)
            minimum = math.min(minimum, measure)
            local base64 = game:GetService("EncodingService"):Base64Encode(packet)
            envelope.Encoding = "base64"
            envelope.Payload = buffer.tostring(base64)
            minimum = math.min(minimum, #game:GetService("HttpService"):JSONEncode(envelope))
        end
    end
    assert(report.StorageBytes == minimum, fixture.Name .. ": failed to select smallest compressed record")
    attempts += 1
    persisted = encoded
end

-- A failed size constraint is not permission to write a raw record.
local tooSmall = makeStore("NexusAlwaysCompressedLimit", {MaxStoredBytes = 1000})
local sample = tooSmall:_BuildNewRecord({Coins = 7})
local _, _, sampleReport = tooSmall:_EncodeRecord(sample)
assert(sampleReport)
tooSmall.Config.MaxStoredBytes = sampleReport.StorageBytes - 1
local blocked, blockedErr = tooSmall:_EncodeRecord(sample)
assert(blocked == nil and string.find(tostring(blockedErr), "STORED_BYTES_EXCEEDED", 1, true), "Uncompressed fallback occurred under pressure")
assert(tooSmall:CloseAsync())
attempts += 1

local function reject(name: string, options: {[string]: any})
    local ok = pcall(function() makeStore(name, options) end)
    assert(not ok, "Unsafe always-smallest config accepted: " .. name)
end
reject("NexusPolicyInvalid", {CompressionPolicy = "magic"})
reject("NexusPolicyFalse", {Compression = false})
reject("NexusPolicyConflict", {ForceCompressedBuffer = true})
attempts += 3

-- Simulate opening an existing raw record: it must be re-encoded on load/save/release.
local mock: any = store:_BuildNewRecord({Coins = 0})
local writes = 0
store.DataStore = {
    UpdateAsync = function(_self, key, transform)
        assert(key == "player")
        local nextValue = transform(mock)
        if nextValue ~= nil then mock = nextValue; writes += 1 end
        return mock
    end,
    GetAsync = function(_self, _key)
        return mock
    end,
}
local profile, openErr = store:OpenAsync("player")
assert(profile, tostring(openErr))
assert(mock.Compressed == true, "Raw data survived open")
assert(profile:Award("Coins", 12))
assert(profile:SaveAsync("critical"))
assert(mock.Compressed == true and store:_DecodeRecord(mock).Data.Coins == 12)
assert(profile:ReleaseAsync() and mock.Compressed == true)
assert(writes >= 3)
assert(store:CloseAsync())
print(("NexusDataStore v8.4.2 always-smallest Studio mock PASS: %d fixtures"):format(attempts + 1))
