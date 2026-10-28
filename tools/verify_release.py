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
local_declaration_pattern = re.compile(r"^[ \t]*local[ \t]+[^=\n]+=[ \t]*$", re.MULTILINE)
luau_files = [ROOT / "DataStore.lua", ROOT / "Compression.lua", *(ROOT / "tests").glob("*.lua")]
split_locals = [str(path.relative_to(ROOT)) for path in luau_files if local_declaration_pattern.search(path.read_text(encoding="utf-8"))]
check("Luau local assignments keep the RHS on the same line", len(split_locals) == 0)
if split_locals:
    print("Split local assignments found in:", ", ".join(split_locals))
check("typed public API retained", "export type Data = PlayersData.Data" in data and "export type Store<T>" in data and "export type Session<T>" in data)
check("record format compatible", "local RECORD_FORMAT = 700" in data)
check("compression codec compatible", "Compression.CodecVersion = 230" in codec and 'return "2.3.4"' in codec)
check("compact locks default disabled", "CompactSessionLocks = config.CompactSessionLocks == true" in data)
check("no-op suppression opt-in", "SkipUnchangedMutations = config.SkipUnchangedMutations == true" in data)
check("profiling opt-in", "ProfileOperations = config.ProfileOperations == true" in data)
check("coalesced save metric present", "SavesCoalesced += 1" in data)
check("snapshot protection retained", '"SNAPSHOT_NOT_OWNED"' in data)
check("key metadata preservation retained", "persistWithKeyInfo(encoded, keyInfo)" in data)
methods = [
    "NexusDataStore:OpenAsync", "NexusDataStore:OpenPlayerAsync",
    "NexusDataStore:SaveAsync", "NexusDataStore:ReleaseAsync",
    "NexusDataStore:_Commit", "NexusDataStore:GetMetrics",
    "NexusDataStore:GetPerformanceReport", "NexusDataStore:GetHealth",
    "Session:Get", "Session:Set", "Session:Delete", "Session:Patch",
    "Session:Mutate", "Session:Append", "Session:RemoveAt",
    "Session:Snapshot", "Session:Restore", "Session:SaveAsync",
    "Session:ReleaseAsync", "OrderedStore:GetAsync",
    "OrderedStore:SetAsync", "OrderedStore:UpdateAsync",
    "OrderedStore:GetTopAsync", "OrderedStore:GetRankAsync",
]
check("critical APIs have unique definitions", all(
    len(re.findall(r"^function " + re.escape(method) + r"\(", data, flags=re.MULTILINE)) == 1
    for method in methods
))
check("README reference retained", "## Configuration reference" in readme and "## API reference" in readme)
check("new features documented", "GetPerformanceReport()" in readme and "SkipUnchangedMutations" in readme)
test_dir = ROOT / "tests"
required = (
    "EfficiencyRegression.server.lua", "CopyOnWriteRegression.server.lua",
    "MutationSafetyRegression.server.lua", "PersistenceRecoveryRegression.server.lua",
    "SchemaMigrationRegression.server.lua", "CompressionRegression.server.lua",
    "MillionLocalBenchmark.server.lua", "MillionMockBackendBenchmark.server.lua",
)
check("core regression and benchmark scripts exist", all((test_dir / name).is_file() for name in required))
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
