--!strict
-- Executed by the portable Luau CLI harness with the real DataStore:_EncodeRecord.
-- Fake compressor isolates selector correctness from codec round-trip tests.
local policyPassed, policyFailed = 0, 0
local function policyTest(name, callback)
    local ok, err = pcall(callback)
    if ok then policyPassed += 1; print("PASS", name) else policyFailed += 1; print("FAIL", name, err) end
end

local function newPolicyStore(rawSize)
    local calls = {}
    local engine = {CodecVersion = 230, CompactCodecVersion = 231, PackedCodecVersion = 232, RunLengthCodecVersion = 233}
    engine.CompressTablePacket = function(_value, options)
        local compact = options.CompactEncoding == true
        local packed = options.BitPackedIntegers == true
        local rle = options.RunLengthArrays == true
        local dictionary = options.StringDictionary == true
        table.insert(calls, tostring(compact) .. ":" .. tostring(dictionary) .. ":" .. tostring(packed) .. ":" .. tostring(rle))
        local size = rle and 2 or (packed and 3 or (compact and (dictionary and 9 or 5) or (dictionary and 17 or 11)))
        return buffer.create(size), {CodecVersion = rle and 233 or (packed and 232 or (compact and 231 or 230)), EncodedBytes = size}
    end
    local store = setmetatable({
        Config = {
            Compression = true,
            CompressionPolicy = "always-smallest",
            ForceCompressedBuffer = false,
            CompressionMinBytes = 512,
            CompressionTransport = "buffer",
            CompressionStrategy = "balanced",
            CompressionOptions = {StringDictionary = true, CompactEncoding = false, AllowExpansion = false},
            CompactSessionLocks = false,
            MaxStoredBytes = 3900000,
        },
        CompressionEngine = engine,
        CompressionEngineVersion = "2.6.0",
    }, DataStore)
    store._MeasureStoredValue = function(_self, value)
        if value.Compressed then return 40 + buffer.len(value.Payload) end
        return rawSize
    end
    return store, calls
end

policyTest("Always-smallest ignores compression threshold and forces encoding", function()
    local store, calls = newPolicyStore(99)
    local output, err, report = store:_EncodeRecord({Data = {Coins = 1}})
    assert(output, tostring(err))
    assert(output.Compressed and output.Encoding == "buffer" and output.Codec == 231)
    assert(report.StorageBytes == 45 and report.SelectedCodec == 231)
    assert(report.SelectionReason == "always-compressed-smallest")
    assert(report.AlternativeCodecCandidates == 4 and #calls == 4)
    assert(report.DictionaryEnabled == false and report.CompactEncoding == true)
end)

policyTest("Already compact data remains encoded even if compressed storage grows", function()
    local store = newPolicyStore(10)
    local output, err, report = store:_EncodeRecord({Data = {Tiny = true}})
    assert(output and output.Compressed, tostring(err))
    assert(report.CompressionExpanded and report.ExpansionBytes == 35)
    assert(report.SavedStorageBytes == -35 and report.RawStorageEstimate == 10)
end)

policyTest("Storage limit refuses writes rather than silently switching to raw", function()
    local store = newPolicyStore(10)
    store.Config.MaxStoredBytes = 44
    local output, err = store:_EncodeRecord({Data = {Tiny = true}})
    assert(output == nil and string.find(err, "STORED_BYTES_EXCEEDED:", 1, true) == 1)
end)

policyTest("Adaptive legacy policy still skips records below threshold", function()
    local store, calls = newPolicyStore(10)
    store.Config.CompressionPolicy = "adaptive"
    local output, err, report = store:_EncodeRecord({Data = {Tiny = true}})
    assert(output and not output.Compressed and not err)
    assert(report.SelectionReason == "below-minimum-bytes" and #calls == 0)
end)

policyTest("Four-way search wins despite the caller requesting the legacy codec", function()
    local store = newPolicyStore(99)
    store.Config.CompressionOptions = {StringDictionary = true, CompactEncoding = false}
    local output, _, report = store:_EncodeRecord({Data = {Number = 3}})
    assert(output.Codec == 231 and report.AlternativeCodecCandidates == 4)
    assert(store.Config.CompressionOptions.CompactEncoding == false, "User config mutated during encode")
end)

policyTest("Forced-buffer legacy mode is unchanged", function()
    local store, calls = newPolicyStore(10)
    store.Config.CompressionPolicy = "adaptive"
    store.Config.ForceCompressedBuffer = true
    store.Config.CompressionStrategy = "smallest"
    local output, _, report = store:_EncodeRecord({Data = {Tiny = true}})
    assert(output and output.Compressed and output.Codec == 230)
    assert(report.SelectionReason == "forced-buffer" and report.AlternativeCodecCandidates == 2 and #calls == 2)
end)

policyTest("Packed codec is opt-in and expands six-way selection safely", function()
    local store, calls = newPolicyStore(99)
    store.Config.CompressionOptions.BitPackedIntegers = true
    local output, err, report = store:_EncodeRecord({Data = {Numbers = {1, 2, 3, 4, 5, 6, 7, 8}}})
    assert(output and output.Codec == 232, tostring(err))
    assert(report.SelectedCodec == 232 and report.BitPackedIntegers)
    assert(report.AlternativeCodecCandidates == 6 and #calls == 6)
    assert(store.Config.CompressionOptions.CompactEncoding == false)
end)

policyTest("Packed mode preserves adaptive force-buffer behavior", function()
    local store, calls = newPolicyStore(10)
    store.Config.CompressionPolicy = "adaptive"
    store.Config.ForceCompressedBuffer = true
    store.Config.CompressionOptions.BitPackedIntegers = true
    local output, _, report = store:_EncodeRecord({Data = {Numbers = {1, 2, 3, 4, 5, 6, 7, 8}}})
    assert(output and output.Codec == 232 and report.AlternativeCodecCandidates == 1)
    assert(#calls == 1)
end)

policyTest("Opt-in RLE extends smallest-record search to eight codec variants", function()
    local store, calls = newPolicyStore(90)
    store.Config.CompressionOptions.RunLengthArrays = true
    local output, err, report = store:_EncodeRecord({Data = {Inventory = {"Potion", "Potion", "Potion"}}})
    assert(output and output.Codec == 233, tostring(err))
    assert(report.SelectedCodec == 233 and report.RunLengthEncoding)
    assert(report.AlternativeCodecCandidates == 8 and #calls == 8)
    assert(store.Config.CompressionOptions.CompactEncoding == false, "Codec selection mutated config")
end)

policyTest("RLE remains optional in adaptive forced-buffer mode", function()
    local store, calls = newPolicyStore(10)
    store.Config.CompressionPolicy = "adaptive"
    store.Config.ForceCompressedBuffer = true
    store.Config.CompressionOptions.RunLengthArrays = true
    local output, _, report = store:_EncodeRecord({Data = {Inventory = {"Potion", "Potion"}}})
    assert(output and output.Codec == 233 and report.AlternativeCodecCandidates == 1)
    assert(#calls == 1)
end)

print(string.format("Compression policy tests: %d passed, %d failed", policyPassed, policyFailed))
assert(policyFailed == 0, "Always-smallest policy regressions failed")
