#!/usr/bin/env python3
"""Static source-compatibility checks; not Roblox Studio tests."""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parent.parent
data = (ROOT / "DataStore.lua").read_text(encoding="utf-8")
codec = (ROOT / "Compression.lua").read_text(encoding="utf-8")
readme = (ROOT / "README.md").read_text(encoding="utf-8")
checks = []

def check(name: str, passed: bool) -> None:
    checks.append((name, passed))
    print(("PASS " if passed else "FAIL ") + name)

match = re.search(r'NexusDataStore\.Version\s*=\s*"(\d+\.\d+\.\d+)"', data)
version = match.group(1) if match else None
check("version defined", version is not None)
check("README and source versions match", version is not None and ("**Current version:** `" + version + "`") in readme)
check("README badge matches", version is not None and ("NexusDataStore-" + version + "-") in readme)
check("strict Luau directive", data.startswith("--!strict\n"))
check("soft shutdown remains explicitly opt-in", "EnableSoftShutdown = config.EnableSoftShutdown == true" in data)
check("scheduled restart event handles developer and Roblox platform migrations", "game.ServerRestartScheduled:Connect" in data and "_OnServerRestartScheduled" in data)
check("session writes freeze before final persistence", 'SOFT_SHUTDOWN_FROZEN' in data and 'self.SoftShutdownFrozen = true' in data)
check("shutdown uses bounded parallel release", 'remaining -= 1' in data and 'self.Config.SoftShutdownCloseTimeout' in data)
check("destination waits on session ownership", "config.EnableSoftShutdown == true" in data and "WaitForSessionLock" in data)
check("restart UI and client arrival implementation present", all(token in (ROOT / "SoftShutdownClient.client.lua").read_text(encoding="utf-8") for token in ("SetTeleportGui", "GetArrivingTeleportGui", "NexusDataStoreProfileReady", "UDim2.fromScale", "Restart in")))
check("restart setup and publish workflow documented", "## New in 7.10.0" in readme and "Restart only servers with outdated versions" in readme)
local_declaration_pattern = re.compile(r"^[ \t]*local[ \t]+[^=\n]+=[ \t]*$", re.MULTILINE)
luau_files = [ROOT / "DataStore.lua", ROOT / "Compression.lua", *(ROOT / "tests").glob("*.lua"), *(ROOT / "tests").glob("*.luau")]
split_locals = [str(path.relative_to(ROOT)) for path in luau_files if local_declaration_pattern.search(path.read_text(encoding="utf-8"))]
check("Luau local assignments keep the RHS on the same line", len(split_locals) == 0)
if split_locals:
    print("Split local assignments found in:", ", ".join(split_locals))
check("typed public API retained", "export type Data = PlayersData.Data" in data and "export type Store<T>" in data and "export type Session<T>" in data)
check("record format compatible", "local RECORD_FORMAT = 700" in data)
check("compression legacy and compact codecs declared", 'Compression.CodecVersion = 230' in codec and 'Compression.CompactCodecVersion = 231' in codec and 'return "2.6.0"' in codec and 'Compression.RunLengthCodecVersion = 233' in codec and 'Compression.PackedCodecVersion = 232' in codec)
check("legacy codec is the default encoder", 'CompactEncoding = source.CompactEncoding == true' in codec and 'Compression.CodecVersion = 230' in codec)
check("compact Boolean arrays pack eight values per byte", 'TAG_BOOLEAN_BITS = 9' in codec and 'index % 8 == 0' in codec)
check("compact small integers and decoding are bounded", 'TAG_SMALL_INTEGER_LAST = 39' in codec and 'NONZERO_BOOLEAN_PADDING' in codec)
check("packed integers opt-in", 'BitPackedIntegers = source.BitPackedIntegers == true or source.RunLengthArrays == true' in codec and 'BitPackedIntegers: boolean?' in data)
check("packed integer codec rejects padding", 'NONZERO_PACKED_INTEGER_PADDING' in codec and 'NON_CANONICAL_PACKED_INTEGER_WIDTH' in codec)
check("packed integer codec validates array size and width", 'INVALID_PACKED_ARRAY_COUNT' in codec and 'INVALID_PACKED_INTEGER_WIDTH' in codec)
check("packed codec negotiation and envelopes", 'selectedCodec ~= 232' in data and 'PackedCodecVersion' in data)
check("forecast includes packed bit counts", 'PackedIntegerValueBits = report.PackedIntegerValueBits' in data)
check("RLE codec declared and opt-in", 'Compression.RunLengthCodecVersion = 233' in codec and 'RunLengthArrays = source.RunLengthArrays == true' in codec)
check("RLE encoder compares exact array costs", 'local competingBytes = normalBytes' in codec and 'rleBytes < competingBytes' in codec)
check("RLE decoder rejects hostile run lengths", 'NON_CANONICAL_RLE_RUN' in codec and 'INVALID_RLE_TOTAL_LENGTH' in codec and 'INVALID_RLE_SCALAR' in codec)
check("RLE does not mutate source and exposes diagnostics", 'RunLengthRuns = writeState.RunLengthRuns' in codec and 'RunLengthValues = report.RunLengthValues' in data)
check("RLE selection supports eight candidates", '"legacy", "compact", "packed", "rle"' in data and 'selectedCodec ~= 233' in data)
check("v7.9 documented opt-in and safe rollout", '## Previously in 7.9.0' in readme and 'RunLengthArrays = true' in readme and 'Safe rollout' in readme)
check("v7.8 README documents rolling upgrades", '## Previously in 7.8.0' in readme and 'BitPackedIntegers = true' in readme and 'Safe rollout' in readme)
check("store envelope carries selected packet codec", 'Codec = selectedCodec' in data and 'COMPRESSED_ENVELOPE_CODEC_MISMATCH' in data)
check("compact setting documented with staged rollout", '## Previously in 7.6.0' in readme and 'CompactEncoding = true' in readme and 'Safe deployment order' in readme)
check("compact locks default disabled", "CompactSessionLocks = config.CompactSessionLocks == true" in data)
check("forced buffer mode defaults off and remains opt-in", "ForceCompressedBuffer = config.ForceCompressedBuffer == true" in data)
check("forced buffer option is typed", "ForceCompressedBuffer: boolean?" in data)
check("forced buffer requires buffer transport", "ForceCompressedBuffer requires CompressionTransport = buffer" in data)
check("forced buffer never silently falls back to raw", "if not enforceCompressed and rawBytes <= self.Config.MaxStoredBytes" in data)
check("forced buffer ignores threshold safely", "if not enforceCompressed and rawBytes < self.Config.CompressionMinBytes" in data)
check("both compressed and raw reports can be emitted", "if self.Config.CompressionReports then" in data and "SelectionReason" in data)
check("always-smallest remains opt-in", 'CompressionPolicy = config.CompressionPolicy or "adaptive"' in data)
check("always-smallest forces all writes compressed", 'local enforceCompressed = alwaysCompressed or self.Config.ForceCompressedBuffer' in data and 'if not enforceCompressed and rawBytes < self.Config.CompressionMinBytes' in data)
check("always-smallest evaluates four compression options", 'local codecModes = alwaysCompressed' in data and 'bestReport.AlternativeCodecCandidates = #variants * #codecModes' in data)
check("always-smallest selects whole-record transport size", 'if candidate ~= nil and candidateBytes < bestBytes then' in data and 'bestReport.SelectedCodec = bestEnvelope.Codec' in data)
check("always-smallest never raw-falls-back at size limit", 'if not enforceCompressed and rawBytes <= self.Config.MaxStoredBytes then' in data and 'STORED_BYTES_EXCEEDED' in data)
check("always-smallest reports expansion accurately", 'bestReport.CompressionExpanded = bestBytes > rawBytes' in data and 'bestReport.ExpansionBytes = math.max(0, bestBytes - rawBytes)' in data)
check("always-smallest rejects invalid combinations", 'config.CompressionPolicy ~= "always-smallest" or config.ForceCompressedBuffer ~= true' in data and 'config.CompressionPolicy ~= "always-smallest" or config.Compression ~= false' in data)
check("always-smallest has full setup and limits documentation", '## Previously in 7.7.0' in readme and 'CompressionPolicy = "always-smallest"' in readme and 'Safe rollout' in readme)
check("no-op suppression opt-in", "SkipUnchangedMutations = config.SkipUnchangedMutations == true" in data)
check("profiling opt-in", "ProfileOperations = config.ProfileOperations == true" in data)
check("coalesced save metric present", "SavesCoalesced += 1" in data)
check("lock waiting defaults off", "WaitForSessionLock = config.WaitForSessionLock == true" in data)
check("lock retry interval is validated", 'configNumber(config.SessionLockRetryInterval, 2, 0.5, "SessionLockRetryInterval", false, 30)' in data)
check("context conflicts rejected", '"SESSION_CONTEXT_CONFLICT"' in data)
check("session contention metrics present", "SessionLockRetries += 1" in data)
check("handoff disabled by default", "EnableSessionHandoff = config.EnableSessionHandoff == true" in data)
check("handoff uses bounded cooldown", 'configNumber(config.SessionHandoffCooldown, 6, 1, "SessionHandoffCooldown", false, 60)' in data)
check("handoff uses authoritative owner and session fencing", "payload.OwnerJobId ~= self.JobId" in data and "session.SessionId ~= payload.OwnerSessionId" in data)
check("handoff refuses connected players and arbitrary profiles", "not session.Player or session.Player.Parent == Players" in data)
check("handoff wait state cleaned up", "self.HandoffWakeGeneration[normalizedKey] = nil" in data)
check("handoff messages are independent of general events", "or self.Config.EnableSessionHandoff then" in data)
check("handoff release notification present", 'eventName == "Released"' in data)
check("handoff documented with service limits", "MessagingService is **best effort**" in readme)
check("session contention documented", "## Previously in 7.4.0" in readme and "SessionLockRetryInterval" in readme)
check("snapshot protection retained", '"SNAPSHOT_NOT_OWNED"' in data)
check("key metadata preservation retained", "persistWithKeyInfo(encoded, keyInfo)" in data)
methods = [
    "NexusDataStore:OpenAsync", "NexusDataStore:OpenPlayerAsync",
    "NexusDataStore:SaveAsync", "NexusDataStore:ReleaseAsync",
    "NexusDataStore:_Commit", "NexusDataStore:GetMetrics",
    "NexusDataStore:GetPerformanceReport", "NexusDataStore:GetHealth",
    "NexusDataStore:PreviewMigration", "NexusDataStore:GetStorageForecast",
    "Session:Get", "Session:SetDefault", "Session:GetDataSnapshot", "Session:Set", "Session:Delete", "Session:Patch",
    "Session:Mutate", "Session:Append", "Session:RemoveAt",
    "Session:Snapshot", "Session:Restore", "Session:SaveAsync",
    "Session:GetChangeJournal", "Session:ClearChangeJournal",
    "Session:ReleaseAsync", "OrderedStore:GetAsync",
    "OrderedStore:SetAsync", "OrderedStore:UpdateAsync",
    "OrderedStore:GetTopAsync", "OrderedStore:GetRankAsync",
]
check("critical APIs have unique definitions", all(
    len(re.findall(r"^function " + re.escape(method) + r"\(", data, flags=re.MULTILINE)) == 1
    for method in methods
))
check("README reference retained", "## Configuration reference" in readme and "## API reference" in readme)
check("forced buffer documented with caveats", "### Opt-in forced buffer storage" in readme and "does not guarantee fewer bytes" in readme)
check("new features documented", "GetPerformanceReport()" in readme and "SkipUnchangedMutations" in readme)
check("v7.2 tool documentation present", "PreviewMigration(data, fromVersion" in readme and "GetStorageForecast(dataOrSession" in readme and "ChangeJournalLimit" in readme)
check("bounded journal defaults off", "ChangeJournalLimit = configNumber(config.ChangeJournalLimit, 0, 0" in data)
test_dir = ROOT / "tests"
required = (
    "EfficiencyRegression.server.lua", "CopyOnWriteRegression.server.lua",
    "DeveloperToolsRegression.server.lua",
    "MutationSafetyRegression.server.lua", "PersistenceRecoveryRegression.server.lua",
    "SchemaMigrationRegression.server.lua", "CompressionRegression.server.lua",
    "ForcedBufferRegression.server.lua", "SessionLockWaitRegression.server.lua", "SessionHandoffRegression.server.lua",
    "AlwaysCompressedRegression.server.lua", "PortableCompressionPolicyRegression.luau", "PortableSoftShutdownRegression.luau",
    "CompactCodecRegression.server.lua", "PackedIntegerCodecRegression.server.lua", "RunLengthPersistenceRegression.server.lua",
    "MillionLocalBenchmark.server.lua", "MillionMockBackendBenchmark.server.lua",
)
check("core regression and benchmark scripts exist", all((test_dir / name).is_file() for name in required))
forced_test = (test_dir / "ForcedBufferRegression.server.lua").read_text(encoding="utf-8")
check("forced buffer mock-backed save test present", all(token in forced_test for token in ("ForceCompressedBuffer", "OpenAsync", "SaveAsync", "ReleaseAsync", "STORED_BYTES_EXCEEDED")))
check("forced buffer legacy-compatibility test present", "legacyDecoded" in forced_test and "crossDecoded" in forced_test)
always_test = (test_dir / "AlwaysCompressedRegression.server.lua").read_text(encoding="utf-8")
policy_test = (test_dir / "PortableCompressionPolicyRegression.luau").read_text(encoding="utf-8")
check("always-compressed test verifies real persisted envelopes", all(token in always_test for token in ("_EncodeRecord", "SaveAsync", "ReleaseAsync", "Compressed == true", "StorageBytes == minimum")))
check("portable always-compressed selector tests included", all(token in policy_test for token in ("CompressionExpanded", "STORED_BYTES_EXCEEDED", "AlternativeCodecCandidates", "always-compressed-smallest")))
runner = (ROOT / "tools" / "run_behavioral_tests.py").read_text(encoding="utf-8")
check("portable policy tests execute in GitHub Actions", "PortableCompressionPolicyRegression.luau" in runner)
lock_wait_test = (test_dir / "SessionLockWaitRegression.server.lua").read_text(encoding="utf-8")
check("contention regression covers ownership, timeout, shutdown and context guards", all(token in lock_wait_test for token in ("SESSION_LOCKED", "ReleaseAsync", "SESSION_CONTEXT_CONFLICT", "SESSION_LOCK_WAIT_TIMEOUT", "CloseAsync")))
handoff_test = (test_dir / "SessionHandoffRegression.server.lua").read_text(encoding="utf-8")
check("mock handoff and crash recovery coverage present", all(token in handoff_test for token in ("_HandleHandoffPacket", "_PublishHandoffRequest", "HandoffWakeups", "SESSION_LOST", "ExpiresAt")))
compact_test = (test_dir / "CompactCodecRegression.server.lua").read_text(encoding="utf-8")
check("v230/v231 cross-format record regression present", all(token in compact_test for token in ("COMPRESSED_ENVELOPE_CODEC_MISMATCH", "Codec == 230", "Codec == 231", "StorageBytes")))
packed_test = (test_dir / "PackedIntegerCodecRegression.server.lua").read_text(encoding="utf-8")
check("v232 Studio mocks and byte reporting", all(token in packed_test for token in ("Codec == 232", "PackedIntegerValueBits", "GetStorageForecast", "COMPRESSED_ENVELOPE_CODEC_MISMATCH")))
rle_test = (test_dir / "RunLengthPersistenceRegression.server.lua").read_text(encoding="utf-8")
check("RLE Studio mock covers load/save/release, cross-decode and byte savings", all(token in rle_test for token in ("OpenAsync", "SaveAsync", "ReleaseAsync", "RunLengthArrays", "StorageBytes < oldReport.StorageBytes")))
for filename, required_count in (
    ("MillionLocalBenchmark.server.lua", 32),
    ("MillionMockBackendBenchmark.server.lua", 21),
):
    script = (test_dir / filename).read_text(encoding="utf-8")
    cases = re.findall(r'benchmark\("([^"]+)"', script)
    check(filename + " cases are unique", len(cases) >= required_count and len(cases) == len(set(cases)))
    check(filename + " has million-iteration setting", "ITERATIONS = 1_000_000" in script)
failures = [name for name, passed in checks if not passed]
print(f"\nStatic release gate: {len(checks) - len(failures)}/{len(checks)} passed")
if failures:
    raise SystemExit("Failed checks: " + ", ".join(failures))
print("This gate cannot replace Luau analysis or Roblox Studio runtime tests.")
