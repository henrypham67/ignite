#!/usr/bin/env bash
# Validate the package catalog by resolving it for every fixture machine.
# Usage: scripts/validate-catalog.sh [SOURCE_DIR]   (default: the repo)
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
src="${1:-$repo}"
root="$src"
if [ -f "$src/.chezmoiroot" ]; then
  root="$src/$(tr -d '[:space:]' < "$src/.chezmoiroot")"
fi

if [ ! -f "$root/.chezmoidata/packages.yaml" ]; then
  echo "validate: no catalog at $root/.chezmoidata/packages.yaml, skipped"
  exit 0
fi

state=$(mktemp -d)
trap 'rm -rf "$state"' EXIT

status=0
for config in "$repo"/tests/fixtures/config/*.toml; do
  fixture=$(basename "$config" .toml)
  [ "$fixture" = empty ] && continue
  if count=$(chezmoi --source "$src" --config "$config" \
      --persistent-state "$state/$fixture.boltdb" \
      execute-template '{{ includeTemplate "selected.json" . | fromJson | len }}'); then
    echo "validate: $fixture ok ($count entries)"
  else
    status=1
  fi
done
exit "$status"
