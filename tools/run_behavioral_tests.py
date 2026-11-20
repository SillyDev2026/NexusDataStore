#!/usr/bin/env python3
"""Run real module methods in Luau with service stubs; not a Roblox emulator."""
import argparse
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser()
parser.add_argument('--luau', default='luau')
args = parser.parse_args()
source = (ROOT / 'DataStore.lua').read_text()
source = source.replace('local PlayersData = require(script.PlayersData)', 'local PlayersData = {}', 1)
prelude = '''local services = {}
local game = {GetService = function(_self, name)
    if services[name] == nil then services[name] = {} end
    return services[name]
end}
local Enum = {DataStoreRequestType = {}}
local task = {spawn = function(callback, ...) callback(...) end}
local DataStore = (function()
'''
tests = (ROOT / 'tests/PortableSessionRegression.luau').read_text() + '\n' + (ROOT / 'tests/PortableCompressionPolicyRegression.luau').read_text() + '\n' + (ROOT / 'tests/PortableSoftShutdownRegression.luau').read_text() + '\n' + (ROOT / 'tests/PortableFramePacingRegression.luau').read_text() + '\n' + (ROOT / 'tests/PortableAutoPublishRegression.luau').read_text() + '\n' + (ROOT / 'tests/PortableV9Regression.luau').read_text() + '\n' + (ROOT / 'tests/PortableReceiptRegression.luau').read_text()
receipts_source = (ROOT / 'NexusReceipts.lua').read_text()
with tempfile.TemporaryDirectory(prefix='nexus-tests-') as directory:
    bundle = Path(directory) / 'suite.luau'
    bundle.write_text(prelude + source + '\nend)()\nlocal NexusReceipts = (function()\n' + receipts_source + '\nend)()\n' + tests)
    session_result = subprocess.run([args.luau, str(bundle)])
    codec = (ROOT / 'Compression.lua').read_text()
    regression = (ROOT / 'tests/CompressionRegression.server.lua').read_text()
    regression = regression.replace('local Compression = require(script.Parent:WaitForChild("Compression"))', '', 1)
    bundle.write_text('local Compression = (function()\n' + codec + '\nend)()\n' + regression)
    codec_result = subprocess.run([args.luau, str(bundle)])
    modern_source = (ROOT / 'CompressionLatest.lua').read_text()
    modern_test = (ROOT / 'tests/ModernCompressionRoundTrip.server.lua').read_text()
    modern_test = modern_test.replace('local Legacy = require(script.Parent:WaitForChild("Compression"))', '', 1)
    modern_test = modern_test.replace('local Modern = require(script.Parent:WaitForChild("CompressionLatest"))', '', 1)
    bundle.write_text('local Legacy = (function()\n' + codec + '\nend)()\nlocal Modern = (function()\n' + modern_source + '\nend)()\n' + modern_test)
    modern_result = subprocess.run([args.luau, str(bundle)])
    raise SystemExit(1 if session_result.returncode or codec_result.returncode or modern_result.returncode else 0)
