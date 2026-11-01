# NexusDataStore 7.3.0 validation

Date: 2026-11-01
Base: 4c0a611cd48755cac7356f72fbcb2556de5f4b79
Luau CLI source: 2a3d8937c19c8fd9f7b72b6ec9068c62760e6588

## Confirmed repairs

- Retained Mutate draft/returned nested references no longer own committed data.
- UpdatePath captures its input path before callback execution and returns INVALID_PATH for malformed paths.
- Callback mutations recheck session state before reporting success, cancellation, or no-op completion.

## Added helpers

- SetDefault: missing-only insertion, preserving false and zero, isolated input/output tables.
- GetDataSnapshot: detached data read without consuming retained snapshot slots.

## Executed checks

- 17 portable session cases passed, including a 10,000-operation deterministic mixed-operation sequence.
- 22 existing codec regression cases passed, including malformed packets and checksum failures.
- 33/33 static compatibility checks passed.
- All three root modules and all regression/benchmark scripts compiled with the official Luau compiler.
- Independent code review found no blocking regression.

The first pre-fix session run had 3 passes and 10 failures, including the reproduced bugs and absent helper methods. The codec suite passed before and after the changes.

## Limits

Portable tests stub service access and do not run the Roblox constructor/background scheduler or real DataStore calls. Studio integration suites, live-server load tests, strict Roblox-aware type analysis, and million-iteration benchmarks were not run. Compilation is not typechecking. No claim is made that every bug in the library has been eliminated. Successful Mutate now performs an additional deep copy to isolate callback-owned data; use path setters for frequent small changes.
