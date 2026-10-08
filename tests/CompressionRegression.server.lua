--!strict
-- Roblox Studio server regression tests for Compression v2.3.3 (codec 230).
-- Place this Script beside a ModuleScript named Compression and run Play/Run.
local Compression = require(script.Parent:WaitForChild("Compression"))

local function equals(a: any, b: any): boolean
    if typeof(a) ~= typeof(b) then return false end
    if typeof(a) ~= "table" then return a == b end
    for key, value in pairs(a) do
        if not equals(value, b[key]) then return false end
    end
    for key in pairs(b) do
        if a[key] == nil then return false end
    end
    return true
end

local function assertRejected(packet: buffer, expected: string)
    local ok, result = pcall(Compression.DecompressTable, packet)
    assert(not ok, "Expected rejection: " .. expected)
    assert(string.find(tostring(result), expected, 1, true) ~= nil, "Unexpected codec error: " .. tostring(result))
end

-- Construct checksum-correct hostile packets to test the decoder rather than
-- simply triggering the checksum guard.
local function makePacket(payload: {number}): buffer
    local packet = buffer.create(11 + #payload)
    buffer.writeu32(packet, 0, Compression.Magic)
    buffer.writeu16(packet, 4, Compression.CodecVersion)
    buffer.writeu8(packet, 6, 0)
    local a = 1
    local b = 0
    for index, byte in ipairs(payload) do
        buffer.writeu8(packet, index + 10, byte)
        a = (a + byte) % 65521
        b = (b + a) % 65521
    end
    buffer.writeu32(packet, 7, b * 65536 + a)
    return packet
end

assert(Compression.Version() == "2.3.3", "Unexpected compression version")
assert(Compression.CodecVersion == 230, "Persistent codec must remain v230")
assert(Compression.TableMode({}) == "buffer-v230", "Packet format changed")

local fixtures = {
    {Name = "empty table", Value = {}},
    {Name = "primitive values", Value = {Coins = 0, Negative = -47, Enabled = true, Disabled = false}},
    {Name = "nested profile", Value = {Coins = 100, Inventory = {"Sword", "Bow", "Sword"}, Level = {Total = 10, Xp = 3.5}}},
    {Name = "UTF-8 strings", Value = {Title = "Rêve 🚀", Duplicate = "Rêve 🚀", Empty = ""}},
    {Name = "fractional and large doubles", Value = {A = 0.125, B = -0.125, C = 9007199254740991}},
    {Name = "numeric map keys", Value = {[0] = "zero", [3] = "three", Text = "three"}},
}
local configs = {
    {StringDictionary = true, DeterministicMaps = true},
    {StringDictionary = false},
    {StringDictionary = true, DeterministicMaps = false},
}
local passed = 0
for _, fixture in ipairs(fixtures) do
    for _, options in ipairs(configs) do
        local bytes, report = Compression.CompressTablePacket(fixture.Value, options)
        local decoded = Compression.DecompressTable(bytes, options)
        assert(equals(fixture.Value, decoded), "Roundtrip failed: " .. fixture.Name)
        assert(report.EncodedBytes == buffer.len(bytes), "Report size mismatch")
        passed += 1
    end
end

local original = Compression.CompressTablePacket({A = "valid"})
local damaged = buffer.create(buffer.len(original))
buffer.copy(damaged, 0, original, 0, buffer.len(original))
local finalPosition = buffer.len(damaged) - 1
buffer.writeu8(damaged, finalPosition, (buffer.readu8(damaged, finalPosition) + 1) % 256)
assertRejected(damaged, "COMPRESSION_CHECKSUM_MISMATCH")
passed += 1

-- Nonminimal integer encoding for dictionary count zero: 0x80, 0x00.
assertRejected(makePacket({128, 0, 1}), "NON_CANONICAL_VARUINT")
passed += 1

-- One map entry with key "x" and a nil value must not silently disappear.
-- payload = [dict count 0][TAG_MAP 8][count 1][TAG_STRING 5][len 1]["x"][TAG_NIL 0].
assertRejected(makePacket({0, 8, 1, 5, 1, 120, 0}), "NIL_MAP_VALUE")
passed += 1

print(("Compression v2.3.3 codec230 regression PASS: %d cases"):format(passed))
