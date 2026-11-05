#!/usr/bin/env python3
"""Require right-hand-side expressions on the same line as Luau local assignments."""
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parent.parent
# Catches "local x =", "local x: T =", and "local x, y =" with a missing RHS.
SPLIT_LOCAL = re.compile(r"^[ \t]*local[ \t]+[^=\n]+=[ \t]*(?:--[^\n]*)?$", re.MULTILINE)
FENCE = re.compile(r"(?ms)^([~\x60]{3,})(?:lua|luau)\b[^\n]*\n(.*?)^\1[ \t]*$")

def bad_lines(source: str) -> list[int]:
    return [source.count("\n", 0, match.start()) + 1 for match in SPLIT_LOCAL.finditer(source)]

def self_test() -> None:
    assert bad_lines("local a =\nb\n") == [1]
    assert bad_lines("local a: number =\n1\n") == [1]
    assert bad_lines("local a, b =\n1, 2\n") == [1]
    assert bad_lines("local a = b\nlocal count: number = 2\n") == []
    assert bad_lines("local function doThing()\n    return true\nend\n") == []

def main() -> int:
    self_test()
    paths = sorted(path for path in ROOT.rglob("*") if path.is_file() and path.suffix in (".lua", ".luau") and ".git" not in path.parts)
    failures: list[str] = []
    for path in paths:
        for line in bad_lines(path.read_text(encoding="utf-8")):
            failures.append(f"{path.relative_to(ROOT)}:{line}: local assignment RHS starts on another line")
    readme = (ROOT / "README.md").read_text(encoding="utf-8")
    for match in FENCE.finditer(readme):
        base = readme.count("\n", 0, match.start(2)) + 1
        for line in bad_lines(match.group(2)):
            failures.append(f"README.md:{base + line - 1}: split local assignment in example")
    if failures:
        print("\n".join(failures))
        return 1
    print(f"PASS: {len(paths)} Luau files and README Luau examples have same-line local assignments")
    return 0

if __name__ == "__main__":
    sys.exit(main())
