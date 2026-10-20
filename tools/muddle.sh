#!/bin/sh
# Build the muddler packages locally, like CI does: sh tools/muddle.sh [Package ...]
# Downloads the latest muddler release into ~/.cache/muddler on first use (needs Java).
# Each package is written to packages/<Package>/build/<Package>.mpackage.
set -e
cd "$(dirname "$0")/.."
cache="$HOME/.cache/muddler"
version=$(curl -fsS https://api.github.com/repos/demonnic/muddler/releases/latest | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p')
[ -n "$version" ] || version=$(cat "$cache/version" 2>/dev/null)
muddle="$cache/muddle-shadow-$version/bin/muddle"
if [ ! -x "$muddle" ]; then
  echo "Downloading muddler $version"
  mkdir -p "$cache"
  curl -fsSL "https://github.com/demonnic/muddler/releases/download/$version/muddle-shadow-$version.tar" | tar -x -C "$cache"
  echo "$version" > "$cache/version"
fi

if [ $# -eq 0 ]; then
  set -- $(for m in packages/*/mfile; do basename "$(dirname "$m")"; done)
fi
for pkg in "$@"; do
  (cd "packages/$pkg" && rm -rf build && "$muddle" > /dev/null) || { echo "FAILED  $pkg"; exit 1; }
  echo "built   packages/$pkg/build/$pkg.mpackage"
done
