--!strict
-- Roblox Studio server regression tests for Compression v2.6.0 (legacy 230, compact 231, packed 232, RLE 233).
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
local function makePacket(payload: {number}, codec: number?): buffer
    local packet = buffer.create(11 + #payload)
    buffer.writeu32(packet, 0, Compression.Magic)
    buffer.writeu16(packet, 4, codec or Compression.CodecVersion)
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

assert(Compression.Version() == "2.6.0", "Unexpected compression version")
assert(Compression.CodecVersion == 230 and Compression.CompactCodecVersion == 231 and Compression.PackedCodecVersion == 232 and Compression.RunLengthCodecVersion == 233, "Codec compatibility changed")
assert(Compression.TableMode({}) == "buffer-v230" and Compression.TableMode({}, {CompactEncoding = true}) == "buffer-v231" and Compression.TableMode({}, {BitPackedIntegers = true}) == "buffer-v232" and Compression.TableMode({}, {RunLengthArrays = true}) == "buffer-v233", "Packet modes changed")

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

-- The eighth VarUInt byte cannot contribute a 54th bit to a Luau safe integer.
assertRejected(makePacket({0, 3, 128, 128, 128, 128, 128, 128, 128, 16}), "VARUINT_UNSAFE_INTEGER")
passed += 1


-- Compact v231 preserves every bit of legacy values but packs small integers
-- and Boolean arrays without per-value tags.
local bits = {}
for index = 1, 64 do bits[index] = index % 3 == 0 end
local compactFixtures = {
    {Name = "64 Boolean flags", Value = {Flags = bits}},
    {Name = "small signed integers", Value = {A = -8, B = -1, C = 0, D = 15, E = 16, F = -9}},
    {Name = "Boolean boundaries", Value = {Four = {true, false, true, true}, Nine = {false, true, false, true, false, true, false, true, true}}},
    {Name = "nested flag arrays", Value = {Flags = bits, Nested = {Flags = bits, Level = 3}}},
}
for _, fixture in ipairs(compactFixtures) do
    for _, useDictionary in ipairs({true, false}) do
        local encoded, report = Compression.CompressTablePacket(fixture.Value, {CompactEncoding = true, StringDictionary = useDictionary, DeterministicMaps = true})
        assert(buffer.readu16(encoded, 4) == 231 and report.CodecVersion == 231, "Compact version mismatch")
        local decoded = Compression.DecompressTable(encoded)
        assert(equals(fixture.Value, decoded), "Compact roundtrip failed: " .. fixture.Name)
        passed += 1
    end
end

local oldFlags = Compression.CompressTablePacket({Flag = bits}, {StringDictionary = false})
local compactFlags = Compression.CompressTablePacket({Flag = bits}, {CompactEncoding = true, StringDictionary = false})
assert(buffer.len(oldFlags) >= 80, "Legacy test packet unexpectedly small")
assert(buffer.len(compactFlags) <= 30, "Compact Boolean packet exceeds 30 bytes")
assert(equals(Compression.DecompressTable(oldFlags), Compression.DecompressTable(compactFlags)), "Legacy compact mismatch")
print(("Packed Boolean packet: %d -> %d bytes"):format(buffer.len(oldFlags), buffer.len(compactFlags)))
passed += 1

-- Exercise all bitset boundary lengths and small-integer transitions with
-- deterministic fixtures (no live backend or nondeterministic RNG).
for count = 0, 255 do
    local values = {}
    for index = 1, count do values[index] = (index * 17 + count) % 7 <= 2 end
    local fixture = {Flags = values, Delta = count % 32 - 16, Index = count}
    local packet = Compression.CompressTablePacket(fixture, {CompactEncoding = true, StringDictionary = count % 2 == 0})
    local restored = Compression.DecompressTable(packet)
    assert(equals(fixture, restored), "Boundary roundtrip failed for length " .. tostring(count))
    passed += 1
end

-- Construct checksum-correct hostile v231 packets to test canonical padding.
assertRejected(makePacket({0, 9, 4, 16}, 231), "NONZERO_BOOLEAN_PADDING")
passed += 1
assertRejected(makePacket({0, 9, 3, 7}, 231), "INVALID_BOOLEAN_ARRAY_COUNT")
passed += 1
assertRejected(makePacket({0, 9, 8}, 231), "COMPRESSION_TRUNCATED")
passed += 1
assertRejected(makePacket({0, 16}, 230), "UNKNOWN_TAG")
passed += 1

-- v232 bit width is selected from real signed integer array contents; no padding data is lost.
for length = 8, 256 do
    local values = {}
    local range = length % 8
    for index = 1, length do
        local magnitude = index % (2 ^ range)
        values[index] = index % 2 == 0 and magnitude or -magnitude
    end
    local fixture = {Integers = values, Flags = {true, false, true, false, true, false, true, false}, Other = 1.25}
    local packet, report = Compression.CompressTablePacket(fixture, {BitPackedIntegers = true, StringDictionary = false})
    assert(report.CodecVersion == 232 and buffer.readu16(packet, 4) == 232)
    local restored = Compression.DecompressTable(packet)
    assert(equals(fixture, restored), "Packed array roundtrip failed: " .. tostring(length))
    passed += 1
end

local tiny = {}
for index = 1, 64 do tiny[index] = index % 4 end
local oldIntegers = Compression.CompressTablePacket({Values = tiny}, {CompactEncoding = true, StringDictionary = false})
local packedIntegers = Compression.CompressTablePacket({Values = tiny}, {BitPackedIntegers = true, StringDictionary = false})
assert(buffer.len(packedIntegers) < buffer.len(oldIntegers), "Packed integer codec failed to save bits")
assert(equals(Compression.DecompressTable(oldIntegers), Compression.DecompressTable(packedIntegers)))
print(("Packed integer packet: %d -> %d bytes"):format(buffer.len(oldIntegers), buffer.len(packedIntegers)))
passed += 1

-- Packet-level hostile tests use correct checksums to reach the packed decoder.
assertRejected(makePacket({0, 10, 8, 0, 0}, 232), "INVALID_PACKED_INTEGER_WIDTH")
passed += 1
assertRejected(makePacket({0, 10, 8, 17, 0}, 232), "INVALID_PACKED_INTEGER_WIDTH")
passed += 1
assertRejected(makePacket({0, 10, 7, 1, 0}, 232), "INVALID_PACKED_ARRAY_COUNT")
passed += 1
assertRejected(makePacket({0, 10, 8, 1}, 232), "COMPRESSION_TRUNCATED")
passed += 1
assertRejected(makePacket({0, 10, 9, 1, 0, 2}, 232), "NONZERO_PACKED_INTEGER_PADDING")
passed += 1
assertRejected(makePacket({0, 10, 8, 4, 0, 0, 0, 0}, 232), "NON_CANONICAL_PACKED_INTEGER_WIDTH")
passed += 1
assertRejected(makePacket({0, 10, 8, 1, 0}, 231), "UNKNOWN_TAG")
passed += 1


-- RLE chooses the smallest representation for runs of repeated inventory strings,
-- flat values and flags; mixed and alternating arrays retain safe legacy encoding.
local repeatedStrings, repeatedIntegers, repeatedBooleans = {}, {}, {}
for i = 1, 256 do
    repeatedStrings[i] = i <= 128 and "Potion" or "Sword"
    repeatedIntegers[i] = 0
    repeatedBooleans[i] = true
end
for _, fixture in ipairs({
    {Name = "inventory", Value = {Inventory = repeatedStrings}},
    {Name = "counters", Value = {Counters = repeatedIntegers}},
    {Name = "flags", Value = {Flags = repeatedBooleans}},
}) do
    local base = Compression.CompressTablePacket(fixture.Value, {BitPackedIntegers = true, StringDictionary = true})
    local packed, report = Compression.CompressTablePacket(fixture.Value, {RunLengthArrays = true, StringDictionary = true})
    assert(report.CodecVersion == 233 and report.RunLengthArrays >= 1, "Expected RLE: " .. fixture.Name)
    assert(report.RunLengthValues >= 256, "Missing RLE value metrics")
    assert(buffer.len(packed) < buffer.len(base), "RLE did not reduce bytes: " .. fixture.Name)
    assert(equals(Compression.DecompressTable(packed), fixture.Value), "RLE roundtrip changed values")
    print(("RLE %s packet: %d -> %d bytes"):format(fixture.Name, buffer.len(base), buffer.len(packed)))
    passed += 1
end
for length = 0, 255 do
    local values = {}
    for i = 1, length do
        local item = (math.floor(i / 3) + length) % 5
        values[i] = item == 0 and "Ruby" or (item == 1 and false or (item == 2 and 4 or (item == 3 and "Bow" or 1.5)))
    end
    local original = {Items = values, Status = true}
    local encoded, report = Compression.CompressTablePacket(original, {RunLengthArrays = true, StringDictionary = length % 2 == 0})
    assert(report.CodecVersion == 233)
    assert(equals(Compression.DecompressTable(encoded), original), "RLE mixed boundary loss " .. tostring(length))
    passed += 1
end
assertRejected(makePacket({0, 11, 4, 1, 0, 2}, 233), "INVALID_RLE_RUN_LENGTH")
passed += 1
assertRejected(makePacket({0, 11, 4, 1, 5, 2}, 233), "INVALID_RLE_RUN_LENGTH")
passed += 1
assertRejected(makePacket({0, 11, 4, 1, 2, 2}, 233), "INVALID_RLE_TOTAL_LENGTH")
passed += 1
assertRejected(makePacket({0, 11, 4, 2, 2, 2, 2, 2}, 233), "NON_CANONICAL_RLE_RUN")
passed += 1
assertRejected(makePacket({0, 11, 4, 1, 4, 0}, 233), "INVALID_RLE_SCALAR")
passed += 1
assertRejected(makePacket({0, 11, 4, 4}, 233), "INVALID_RLE_ARRAY_COUNT")
passed += 1
assertRejected(makePacket({0, 11, 4, 1, 4, 2}, 232), "UNKNOWN_TAG")
passed += 1

print(("Compression v2.6.0 codec230/231/232/233 regression PASS: %d cases"):format(passed))
