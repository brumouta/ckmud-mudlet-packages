#!/bin/sh
# Run every test from the repo root: sh tests/run.sh
#   - Lua tests for the simple packages (tests/*_test.lua)
#   - every package builds
cd "$(dirname "$0")/.." || exit 1
status=0

for t in tests/*_test.lua; do
  if out=$(lua "$t" 2>&1); then
    echo "PASS  $t"
  else
    echo "FAIL  $t"; echo "$out" | tail -8; status=1
  fi
done

# every package builds (build.py stops on a missing file or a key it doesn't know)
if out=$(python3 tools/build.py 2>&1); then
  echo "PASS  build ($(echo "$out" | grep -c '^built') packages)"
else
  echo "FAIL  build"; echo "$out" | tail -8; status=1
fi
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
