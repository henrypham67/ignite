#!/usr/bin/env bash
# End-to-end run on macOS or Linux: bootstrap from this checkout with fixed
# answers, then check that a second apply changes nothing and, without admin,
# that the needs-IT list is there and nothing failed. Used by CI and by
# `mise run e2e-linux`. It installs real software: run it on a throwaway
# machine or container, never on a laptop you care about.
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
export IGNITE_LOCAL_SOURCE="${IGNITE_LOCAL_SOURCE:-$repo}"

answers=(
  --no-tty
  --promptString "Work email for git=ci@example.com"
  --promptChoice "Company git host=github"
  --promptBool "Use AWS=true"
  --promptBool "Use Azure=false"
  --promptBool "Use GCP=false"
  --promptBool "Company licenses Docker Desktop=false"
  --promptBool "Install specialist tools=false"
  --promptBool "Install personal apps=false"
  --promptBool "Change default tool choices=false"
)

bash "$repo/bootstrap.sh" "${answers[@]}"

chezmoi=("$HOME/.local/bin/chezmoi" --source "$IGNITE_LOCAL_SOURCE" --no-tty)
"${chezmoi[@]}" apply
"${chezmoi[@]}" verify --exclude=scripts
changes=$("${chezmoi[@]}" status --exclude=scripts)
if [ -n "$changes" ]; then
  printf 'a second apply still has changes:\n%s\n' "$changes"
  exit 1
fi

if [ "${IGNITE_NO_ADMIN:-}" = 1 ]; then
  report="${XDG_STATE_HOME:-$HOME/.local/state}/ignite/report.tsv"
  grep -q $'\tneeds-it\t' "$report" || { echo "expected needs-IT rows in $report"; exit 1; }
  if grep $'\tfailed\t' "$report"; then
    echo "installs failed without admin"
    exit 1
  fi
fi
echo "e2e ok"
