#!/bin/sh
# Run every test from the repo root: sh tests/run.sh
#   - Lua tests for the simple packages (tests/*_test.lua)
#   - manifest lint + Node simulation tests for the muddler packages (packages/*/mfile)
cd "$(dirname "$0")/.." || exit 1
status=0

for t in tests/*_test.lua; do
  if out=$(lua "$t" 2>&1); then
    echo "PASS  $t"
  else
    echo "FAIL  $t"; echo "$out" | tail -8; status=1
  fi
done

for mfile in packages/*/mfile; do
  pkg=$(dirname "$mfile")
  if out=$(python3 tools/lint_manifests.py "$pkg/src" 2>&1); then
    echo "PASS  $pkg lint"
  else
    echo "FAIL  $pkg lint"; echo "$out" | tail -8; status=1
  fi
  # muddler puts README.md into config.lua's description; some clients can't parse non-ASCII there
  if bad=$(LC_ALL=C grep -n '[^ -~	]' "$pkg/README.md" 2>/dev/null); then
    echo "FAIL  $pkg README.md is not plain ASCII (it ends up in config.lua)"; echo "$bad" | head -5; status=1
  fi
  if [ ! -f "$pkg/tests/runner.js" ]; then
    echo "SKIP  $pkg simulation (no tests)"; continue
  fi
  if ! command -v node >/dev/null 2>&1; then
    echo "SKIP  $pkg simulation (node not installed)"; continue
  fi
  [ -d "$pkg/tests/node_modules" ] || (cd "$pkg/tests" && npm install --silent --no-audit --no-fund >/dev/null 2>&1)
  if out=$(cd "$pkg/tests" && node runner.js driver.lua 2>&1); then
    echo "PASS  $pkg simulation ($(echo "$out" | tail -1 | sed 's/=== RESULT: //; s/ ===//'))"
  else
    echo "FAIL  $pkg simulation"; echo "$out" | tail -8; status=1
  fi
done
# Plugins for the CKMud client (one XML for Mudlet and the client): build from the package's
# mpackage plus packages/<Pkg>/<Pkg>-plugin/{head,tail}.lua, then run its test.lua in Lua 5.1
# (the client's Lua) against the built file
for dir in packages/*/*-plugin; do
  [ -f "$dir/test.lua" ] || continue
  pkg=$(basename "$(dirname "$dir")")
  if ! command -v node >/dev/null 2>&1 || ! command -v lua5.1 >/dev/null 2>&1; then
    echo "SKIP  $dir (needs node and lua5.1)"; continue
  fi
  xml="dist/$(echo "$pkg" | tr 'A-Z' 'a-z').xml"
  if ! out=$(python3 tools/build.py "$pkg" 2>&1 && node tools/plugin/build-plugin.cjs -o "$xml" "$dir/head.lua" "dist/$pkg.mpackage" "$dir/tail.lua" 2>&1); then
    echo "FAIL  $dir build"; echo "$out" | tail -8; status=1; continue
  fi
  if out=$(cd "$dir" && lua5.1 test.lua "$OLDPWD/$xml" 2>&1); then
    echo "PASS  $dir ($xml)"
  else
    echo "FAIL  $dir"; echo "$out" | grep -v "^ok " | tail -8; status=1
  fi
done
exit $status
