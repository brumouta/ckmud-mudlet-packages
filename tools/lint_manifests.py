#!/usr/bin/env python3
"""Lint muddler manifests: every trigger/alias/key entry must have either an
inline "script" or a matching <name>.lua file (spaces -> underscores), because
muddler silently attaches an EMPTY script when the .lua file is missing.

Usage: lint_manifests.py [src-dir]   (defaults to ./src)
Exits non-zero if any entry has no script at all.
"""
import json
import sys
from pathlib import Path

src = Path(sys.argv[1] if len(sys.argv) > 1 else "src")
problems = []
checked = 0

# muddler substitutes __PKGNAME__ with the package name from mfile; two
# entries whose names collide AFTER substitution silently shadow each other
try:
    pkgname = json.loads((src.parent / "mfile").read_text()).get("package", "")
except OSError:
    pkgname = ""


def check_entry(entry, directory, manifest, seen):
    global checked
    checked += 1
    name = entry.get("name", "<unnamed>")
    has_inline = isinstance(entry.get("script"), str)
    lua_file = directory / (name.replace(" ", "_") + ".lua")
    if not has_inline and not lua_file.exists():
        problems.append(f"{manifest}: entry {name!r} has no inline script and no {lua_file.name}")
    resolved = name.replace("__PKGNAME__", pkgname)
    if resolved in seen:
        problems.append(
            f"{manifest}: sibling entries {seen[resolved]!r} and {name!r} both resolve to "
            f"{resolved!r} after __PKGNAME__ substitution - muddler will drop one")
    else:
        seen[resolved] = name
    child_seen = {}
    for child in entry.get("children", []):
        check_entry(child, directory, manifest, child_seen)


for manifest in sorted(src.rglob("*.json")):
    if manifest.name not in ("triggers.json", "aliases.json", "keys.json", "scripts.json"):
        continue
    entries = json.loads(manifest.read_text())
    seen = {}
    for entry in entries:
        check_entry(entry, manifest.parent, manifest, seen)

print(f"lint_manifests: checked {checked} entries in {src}")
if problems:
    for p in problems:
        print("ERROR:", p)
    sys.exit(1)
print("lint_manifests: OK")
