#!/usr/bin/env python3
"""Catch the 'called but never defined' bug class before push.

Scans every .lua file under src/ for:
  definitions:  function Module.Method(...)   (module table methods)
  calls:        Module.Method(...)            (where Module is a known module)

Reports any call where the module is known but no matching definition exists
anywhere in src/. Skips Roblox API calls, instance method calls (obj:Method),
and definitions themselves.

Exit code: 0 if clean, 1 if any undefined calls found.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent / "src"

# Known module table names: every `local Name = {}` at top level of a .lua file,
# plus shared modules and ProfileStore (vendored package).
KNOWN_MODULES = set()
for f in ROOT.rglob("*.lua"):
    try:
        text = f.read_text(encoding="utf-8", errors="replace")
    except OSError:
        continue
    for m in re.finditer(r"^local\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*\{\}", text, re.M):
        KNOWN_MODULES.add(m.group(1))
    for m in re.finditer(r"require\(.*:WaitForChild\(\"([A-Za-z_][A-Za-z0-9_]*)\"\)\)", text):
        KNOWN_MODULES.add(m.group(1))

defined = set()   # (module, method)
calls = []        # (file, line, module, method)

for f in ROOT.rglob("*.lua"):
    text = f.read_text(encoding="utf-8", errors="replace")
    for i, line in enumerate(text.splitlines(), 1):
        # definitions: function Module.Method(   (also `local function` variants)
        for m in re.finditer(r"\bfunction\s+([A-Za-z_][A-Za-z0-9_]*)\.([A-Za-z_][A-Za-z0-9_]*)\s*\(", line):
            defined.add((m.group(1), m.group(2)))
        # calls: Module.Method(  — but skip lines that are definitions
        if re.search(r"\bfunction\s+[A-Za-z_][A-Za-z0-9_]*\.", line):
            continue
        for m in re.finditer(r"(?<![\w.])([A-Za-z_][A-Za-z0-9_]*)\.([A-Za-z_][A-Za-z0-9_]*)\s*\(", line):
            mod, meth = m.group(1), m.group(2)
            if mod in KNOWN_MODULES:
                calls.append((f.relative_to(ROOT.parent), i, mod, meth))

# A call like Config.X is fine if X is a config VALUE, not a function.
# Config.lua holds data fields, not methods — skip method checks on it.
DATA_MODULES = {"Config", "FishRegistry", "BuildCatalog", "Types"}

problems = []
for file, line, mod, meth in calls:
    if mod in DATA_MODULES:
        continue
    if (mod, meth) not in defined:
        problems.append(f"{file}:{line}: {mod}.{meth}() called but never defined")

if problems:
    print("UNDEFINED CALLS FOUND:")
    for p in sorted(set(problems)):
        print("  " + p)
    sys.exit(1)

print(f"OK: {len(set(calls))} module calls checked, all defined "
      f"({len(KNOWN_MODULES)} modules).")
