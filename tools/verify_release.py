#!/usr/bin/env python3
"""Static source-compatibility checks; not Roblox Studio tests."""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parent.parent
data = (ROOT / "DataStore.lua").read_text(encoding="utf-8")
codec = (ROOT / "Compression.lua").read_text(encoding="utf-8")
readme = (ROOT / "README.md").read_text(encoding="utf-8")
historical_docs = (ROOT / "docs" / "README-HISTORY-v8.5.md").read_text(encoding="utf-8")
documentation = readme + "\n" + historical_docs
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
check("v8 signed zero is preserved by the encoder", 'local function isNegativeZero' in codec and 'not isNegativeZero(value)' in codec)
check("v8 size search tolerates failed optional candidates", 'local function evaluateCandidate' in data and 'candidateFailures += 1' in data)
check("v8 enforces compressed-only policy on failures", 'if not enforceCompressed and rawBytes <= self.Config.MaxStoredBytes then' in data and 'compression-failed-raw-fallback' in data)
check("v8 concurrent flush caps workers", 'math.min(6, #sessions)' in data and 'FLUSH_TIMEOUT' in data)
check("v8 restart readiness is store-scoped", 'NexusDataStoreProfileReady_' in data and 'NexusDataStoreProfileReady_' in (ROOT / "SoftShutdownClient.client.lua").read_text(encoding="utf-8"))
check("v8 major release notes retained", '## Previously in 8.0.0' in documentation and 'Compression v2.6.1' in documentation)
check("scheduled restart event handles developer and Roblox platform migrations", "game.ServerRestartScheduled:Connect" in data and "_OnServerRestartScheduled" in data)
check("session writes freeze before final persistence", 'SOFT_SHUTDOWN_FROZEN' in data and 'self.SoftShutdownFrozen = true' in data)
check("shutdown uses bounded parallel release", 'remaining -= 1' in data and 'self.Config.SoftShutdownCloseTimeout' in data)
check("destination waits on session ownership", "config.EnableSoftShutdown == true" in data and "WaitForSessionLock" in data)
client = (ROOT / "SoftShutdownClient.client.lua").read_text(encoding="utf-8")
check("restart UI and client arrival implementation present", all(token in client for token in ("SetTeleportGui", "GetArrivingTeleportGui", "NexusDataStoreProfileReady", "UDim2.fromScale", "Server restart in")))
check("responsive UI uses only normalized layout coordinates", "UDim2.new(" not in client and "UDim2.fromOffset(" not in client and "UISizeConstraint" not in client and all(value == "fromScale" for value in re.findall(r'\b(?:Position|Size)\s*=\s*UDim2\.(\w+)\(', client)))
check("responsive UI has animated banner and full-screen presentation", all(token in client for token in ("CanvasGroup", "GroupTransparency", 'activePresentation', 'kind == "banner"', 'kind == "full"', 'TweenService:Create')))
check("responsive layout reflows when orientation changes", 'applyResponsiveLayout' in client and 'GetPropertyChangedSignal("AbsoluteSize")' in client and 'viewportConnection:Disconnect()' in client)
check("restart motion disconnects listeners and cancels stale transition tweens", all(token in client for token in ('renderConnection:Disconnect()', 'viewportConnection:Disconnect()', 'arrivalReadyConnection:Disconnect()', 'cancelStatusTweens()', 'tween:Cancel()')))
check("arrival interface works with legacy transfer GUIs", 'arriving.Name == "NexusRestartGui"' in client and 'readyAttribute' in client and 'errorAttribute' in client)
check("v8.1 UI details retained", "## Previously in 8.1.0" in documentation and "UDim2.fromScale" in documentation)
check("v8.2 cinematic HUD and status timeline", all(token in client for token in ('DataCore', 'UIAspectRatioConstraint', 'GridX', 'GridY', 'stepNames', 'phaseSteps', 'active and shade', 'statusOrb', 'phaseColor')))
check("v8.2 phase transitions remain cancellable", all(token in client for token in ('cancelStatusTweens()', 'table.clear(statusTweens)', 'animateState(', 'haloGradientRef.Rotation', 'phaseColor')))
check("v8.2 true save, transfer and restore states", all(token in client for token in ('"ready"', '"arriving"', '"error"', '"01  Save"', '"02  Transfer"', '"03  Restore"', 'currentStep')))
check("v8.2 reduced-motion option", 'local REDUCED_MOTION = false' in client and 'if REDUCED_MOTION then' in client)
check("v8.2 historical release retained and codec unchanged", '## Previously in 8.2.0' in documentation and 'Compression v2.6.1' in documentation and 'record format' in documentation)
check("v8.3 motion controller runs on rendered frames", 'RunService.PreRender:Connect(renderStep)' in client and 'renderStep = function(deltaTime: number)' in client)
check("v8.3 motion is elapsed-time based", 'animationClock = (animationClock + dt)' in client and 'math.min(deltaTime, 0.05)' in client and 'phaseFill.Position = UDim2.fromScale(' in client)
check("v8.3 has adaptive quality hysteresis", all(token in client for token in ('averageFrameTime', 'slowFrameDuration >= 1.4', 'recoveryDuration >= 2.5', 'lightweightEffects', 'ObservedRenderFPS')))
check("v8.3 stops visual work when hidden", 'activePresentation == "full"' in client and 'activePresentation == "banner"' in client and 'currentStatus ~= "error"' in client)
check("v8.3 event-driven profile arrival", 'GetAttributeChangedSignal(readyAttribute)' in client and 'GetAttributeChangedSignal(errorAttribute)' in client and 'task.wait(0.25)' not in client)
check("v8.3 eliminates old fixed-cadence polling", 'task.wait(0.35)' not in client and 'loopTween(' not in client)
check("v8.3 timing simulations are included", (ROOT / "tests/PortableFramePacingRegression.luau").exists() and 'PortableFramePacingRegression.luau' in (ROOT / "tools/run_behavioral_tests.py").read_text(encoding="utf-8"))
check("v8.3 historical documentation retained", '## Previously in 8.3.0' in documentation and 'PreRender' in documentation)
check("v8.4 opt-in auto publish is guarded", 'AutoRestartOnPublish = config.AutoRestartOnPublish == true' in data and 'AutoRestartOnPublish requires EnableSoftShutdown' in data)
check("v8.4 version watch requires two consistent samples", 'GetLatestAssetVersionAsync' in data and 'self.AutoPublishCandidatesSeen < 2' in data and 'self.AutoPublishBaseline' in data)
check("v8.4 auto restart reuses safe flush", 'state.Source == "AutoPublish"' in data and 'state.FinalSaved' in data and '_SoftShutdownTick' in data)
check("v8.4 does not teleport without final save", 'timestamp < state.RestartAt or not state.FinalSaved' in data and 'not peer.FinalSaved' in data)
check("v8.4 uses fresh reserved server and retries", 'ReservedServerId = HttpService:GenerateGUID(false)' in data and 'TeleportService:TeleportAsync(game.PlaceId, batch' in data and 'TeleportInitFailed:Connect' in data)
check("v8.4 records auto publish and teleport diagnostics", 'AutoPublishDetected = 0' in data and 'AutoPublishTeleportFailed = 0' in data and 'GetAutoPublishStatus()' in data)
check("v8.4 client distinguishes teleport retry from save retry", '"teleport-retrying"' in client and '"moving"' in client)
check("v8.4 mock tests integrated", (ROOT / "tests/PortableAutoPublishRegression.luau").exists() and 'PortableAutoPublishRegression.luau' in (ROOT / "tools/run_behavioral_tests.py").read_text(encoding="utf-8"))
check("v8.4 setup and limitations preserved", '## Previously in 8.4.0' in documentation and 'best-effort' in documentation and 'reserved/private server' in documentation)
check("v8.4.1 neon horizon procedural background", all(token in client for token in ("buildHorizon(backdrop)", "PerspectiveGridFloor", "HorizonGlow", "HorizonLine", "GridX", "GridY", "DataTower", "DataStar", "HorizonHUDRing", "FloorLightArc", "HorizonScan")))
check("v8.4.1 optional exact art uses a Roblox ImageLabel", 'BACKGROUND_IMAGE_ID = ""' in client and 'image.ScaleType = Enum.ScaleType.Crop' in client and 'image.Image = BACKGROUND_IMAGE_ID' in client)
check("v8.4.1 floor perspective responds to viewport geometry", 'math.atan2(dy, dx)' in client and 'entry.Line.Rotation' in client and 'GetPropertyChangedSignal("AbsoluteSize")' in client)
check("v8.4.1 animated background only on active full screen", 'if horizonScan then' in client and 'if not lightweightEffects and backgroundAccumulator >= 1 / 30 then' in client and 'if REDUCED_MOTION then return end' in client)
check("v8.4.1 horizon asset instructions retained", '## Previously in 8.4.1' in documentation and 'BACKGROUND_IMAGE_ID' in documentation and 'neon_nexus_data_horizon.png' in documentation)
check("v8.4.2 typography settings preserved", 'TextTransparency = REDUCED_MOTION and 0 or 0.2' in client and 'TextWrapped' in client)
check("v8.4.2 uses a short, non-flashing text fade", 'TextTransparency = REDUCED_MOTION and 0 or 0.2' in client and 'TweenInfo.new(0.22' in client)
check("v8.4.2 throttles decorative background without degrading foreground", 'backgroundAccumulator >= 1 / 30' in client and 'if phaseFill then' in client and 'RunService.PreRender:Connect(renderStep)' in client)
check("v8.4.2 scan reverses without hard resetting", '0.5 - 0.5 * math.cos(t * 0.72)' in client and '(t * 0.095) % 1.45' not in client)
check("v8.4.2 avoids duplicate phase animation", 'if status == previousStatus and restartAt == target and lastMessage == message then return end' in client)
check("v8.4.2 release documentation retained", '## Previously in 8.4.2' in documentation and '## Previously in 8.4.1' in documentation)
check("v8.4.3 stops auto-shrinking display text", 'item.TextScaled = false' in client and 'item.TextScaled = true' not in client and 'UITextSizeConstraint' not in client)
check("v8.4.3 sizes typography per role and viewport", 'local scale = math.clamp(math.min(view.X / 1000, view.Y / 540)' in client and all(token in client for token in ('name == "Title"', 'name == "Status"', 'name == "Description"', 'name == "Message"', 'name == "Timer"', 'label.TextSize = math.floor(base * scale + 0.5)')))
check("v8.4.3 uses four responsive panel modes", all(token in client for token in ('local portrait = ratio < 0.85', 'local shortLandscape =', 'elseif ratio < 1.45', 'panel.Size = UDim2.fromScale(0.80, 0.82)', 'panel.Size = UDim2.fromScale(0.92, 0.56)')))
check("v8.4.3 avoids text collisions", 'title.Position = UDim2.fromScale(0.065, 0.315)' in client and 'description.Position = UDim2.fromScale(0.1, 0.603)' in client and 'phaseLabel.Position = UDim2.fromScale(0.105, 0.885)' in client)
check("v8.4.3 clears typography and event references", 'table.clear(textElements)' in client and 'eyebrowLabel, coreIconLabel = nil, nil' in client)
check("v8.4.3 release instructions", '## New in 8.4.3' in documentation and 'TextScaled = false' in documentation)
check("restart setup and publish workflow documented", "## Previously in 7.10.0" in documentation and "Restart only servers with outdated versions" in documentation)
local_declaration_pattern = re.compile(r"^[ \t]*local[ \t]+[^=\n]+=[ \t]*$", re.MULTILINE)
luau_files = [ROOT / "DataStore.lua", ROOT / "Compression.lua", *(ROOT / "tests").glob("*.lua"), *(ROOT / "tests").glob("*.luau")]
split_locals = [str(path.relative_to(ROOT)) for path in luau_files if local_declaration_pattern.search(path.read_text(encoding="utf-8"))]
check("Luau local assignments keep the RHS on the same line", len(split_locals) == 0)
if split_locals:
    print("Split local assignments found in:", ", ".join(split_locals))
check("typed public API retained", "export type Data = PlayersData.Data" in data and "export type Store<T>" in data and "export type Session<T>" in data)
check("record format compatible", "local RECORD_FORMAT = 700" in data)
check("compression legacy and compact codecs declared", 'Compression.CodecVersion = 230' in codec and 'Compression.CompactCodecVersion = 231' in codec and 'return "2.6.1"' in codec and 'Compression.RunLengthCodecVersion = 233' in codec and 'Compression.PackedCodecVersion = 232' in codec)
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
check("v7.9 documented opt-in and safe rollout", '## Previously in 7.9.0' in documentation and 'RunLengthArrays = true' in documentation and 'Safe rollout' in documentation)
check("v7.8 README documents rolling upgrades", '## Previously in 7.8.0' in documentation and 'BitPackedIntegers = true' in documentation and 'Safe rollout' in documentation)
check("store envelope carries selected packet codec", 'Codec = selectedCodec' in data and 'COMPRESSED_ENVELOPE_CODEC_MISMATCH' in data)
check("compact setting documented with staged rollout", '## Previously in 7.6.0' in documentation and 'CompactEncoding = true' in documentation and 'Safe deployment order' in documentation)
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
check("always-smallest selects whole-record transport size", 'elseif candidateBytes < bestBytes then' in data and 'bestReport.SelectedCodec = bestEnvelope.Codec' in data)
check("always-smallest never raw-falls-back at size limit", 'if not enforceCompressed and rawBytes <= self.Config.MaxStoredBytes then' in data and 'STORED_BYTES_EXCEEDED' in data)
check("always-smallest reports expansion accurately", 'bestReport.CompressionExpanded = bestBytes > rawBytes' in data and 'bestReport.ExpansionBytes = math.max(0, bestBytes - rawBytes)' in data)
check("always-smallest rejects invalid combinations", 'config.CompressionPolicy ~= "always-smallest" or config.ForceCompressedBuffer ~= true' in data and 'config.CompressionPolicy ~= "always-smallest" or config.Compression ~= false' in data)
check("always-smallest has full setup and limits documentation", '## Previously in 7.7.0' in documentation and 'CompressionPolicy = "always-smallest"' in documentation and 'Safe rollout' in documentation)
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
check("handoff documented with service limits", "MessagingService is **best effort**" in documentation)
check("session contention documented", "## Previously in 7.4.0" in documentation and "SessionLockRetryInterval" in documentation)
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
check("README reference retained", "## Configuration reference" in documentation and "## API reference" in documentation)
check("forced buffer documented with caveats", "### Opt-in forced buffer storage" in documentation and "does not guarantee fewer bytes" in documentation)
check("new features documented", "GetPerformanceReport()" in documentation and "SkipUnchangedMutations" in documentation)
check("v7.2 tool documentation present", "PreviewMigration(data, fromVersion" in documentation and "GetStorageForecast(dataOrSession" in documentation and "ChangeJournalLimit" in documentation)
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
check("v8.5 safe snapshot reads exported and implemented", 'TryGet: (self: Session<T>' in data and 'function Session:TryGet(' in data and 'return true, value' in data)
check("v8.5 bounded zero timeout and lifecycle waits", 'local remaining = deadline - now()' in data and 'math.min(0.05, remaining)' in data and '"PLAYER_LEFT"' in data and '"INVALID_SESSION_KEY"' in data)
check("v8.5 retry state resets between attempts", 'saveError = nil\n\t\t\tencodeReport = nil' in data and 'acquireError = nil\n\t\t\t\tlockedOwner = nil' in data)
check("v8.5 session status diagnostics", all(token in data for token in ('NextAutoSaveIn =', 'LastHeartbeatAge =', 'CommitBusy = self.CommitBusy', 'SavePending = self.SavePending')))
check("v8.5 server-synchronized restart countdown", 'Workspace.GetServerTimeNow' in client and 'DateTime.now().UnixTimestamp' in client)
check("v8.5 late restart RemoteEvent binding", 'ReplicatedStorage.ChildAdded:Connect(bindRestartRemote)' in client and 'WaitForChild("NexusDataStoreRestart_"' not in client)
check("v8.5 restart UI exposes operational attributes", all(token in client for token in ('"ReducedMotion"', '"CountdownSeconds"', '"Fullscreen"', '"Presentation"', '"Status"')))
check("v8.5 release notes and example", '## New in 8.5.0' in readme and 'profile:TryGet("Coins")' in readme)
# Current README documents all exported public methods without requiring a historical release scroll.
public_methods = sorted(set(re.findall(r'^function (?:NexusDataStore|Session|OrderedStore):([A-Za-z][A-Za-z0-9_]*)\(', data, flags=re.MULTILINE)))
missing_public = [method for method in public_methods if not re.search(r'\b' + re.escape(method) + r'\(', readme)]
check("current README covers every public colon-method", not missing_public)
if missing_public:
    print("Undocumented public methods:", ", ".join(missing_public))
check("current README has quick start, all API families, compression, migration and safety", all(section in readme for section in ("## Install and quick start", "## Complete profile API examples", "## Complete store API examples", "## Ordered leaderboards", "## Compression and record size", "## Schemas and migrations", "## Restart and cross-server handoff", "## Configuration reference", "## API reference", "## Testing and troubleshooting")))
check("legacy release history is archived separately", "# NexusDataStore" in historical_docs and "## Previously in 8.4.3" not in readme and "## New in 8.4.3" in historical_docs)
check("Luau style checker is included", (ROOT / "tools" / "check_luau_style.py").is_file())
failures = [name for name, passed in checks if not passed]
print(f"\nStatic release gate: {len(checks) - len(failures)}/{len(checks)} passed")
if failures:
    raise SystemExit("Failed checks: " + ", ".join(failures))
print("This gate cannot replace Luau analysis or Roblox Studio runtime tests.")
