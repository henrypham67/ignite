#!/usr/bin/env bash
# Fail if any tracked file mentions a denylisted term (employer names, company
# domains, internal hostnames). The terms themselves are never committed: they
# come from $IGNITE_DENYLIST (newline- or comma-separated) or from
# ~/.config/ignite/denylist.txt. Hits are printed as file:line only, so the
# terms never show up in logs.
set -euo pipefail

terms_file=$(mktemp)
trap 'rm -f "$terms_file"' EXIT

if [ -n "${IGNITE_DENYLIST:-}" ]; then
  printf '%s\n' "$IGNITE_DENYLIST" | tr ',' '\n' > "$terms_file"
elif [ -f "$HOME/.config/ignite/denylist.txt" ]; then
  cat "$HOME/.config/ignite/denylist.txt" > "$terms_file"
fi

# Drop blank lines and surrounding whitespace.
cleaned=$(sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' "$terms_file" | grep -v '^$' || true)
printf '%s\n' "$cleaned" > "$terms_file"

if [ -z "$cleaned" ]; then
  if [ "${IGNITE_DENYLIST_REQUIRED:-}" = 1 ]; then
    echo "denylist: no terms configured but IGNITE_DENYLIST_REQUIRED=1" >&2
    exit 1
  fi
  echo "denylist empty: skipped (set IGNITE_DENYLIST or ~/.config/ignite/denylist.txt)"
  exit 0
fi

hits=$(git ls-files -z | xargs -0 grep -I -n -i -F -f "$terms_file" -- 2>/dev/null | cut -d: -f1,2 || true)

if [ -n "$hits" ]; then
  echo "denylist: tracked files mention a denylisted term:"
  printf '%s\n' "$hits"
  exit 1
fi
