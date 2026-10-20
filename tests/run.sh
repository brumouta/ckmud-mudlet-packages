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
exit $status
