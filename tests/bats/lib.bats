#!/usr/bin/env bats
# lib.sh: the report helpers rendered into every unix install script.

load helper

setup() {
  export XDG_STATE_HOME="$BATS_TEST_TMPDIR/state"
  unset IGNITE_SKIP
  LIB="$BATS_TEST_TMPDIR/lib.sh"
  render_file darwin-admin "$REPO/home/.chezmoitemplates/lib.sh" > "$LIB"
  REPORT="$XDG_STATE_HOME/ignite/report.tsv"
}

# rows: the report file, or nothing when it doesn't exist.
rows() {
  [ -f "$REPORT" ] && cat "$REPORT" || true
}

@test "lib.sh: ig_report_path follows XDG_STATE_HOME" {
  . "$LIB"
  [ "$(ig_report_path)" = "$REPORT" ]
}

@test "lib.sh: ig_try records failure and returns 0" {
  . "$LIB"
  run ig_try mise k9s sh -c 'echo first; echo boom >&2; exit 3'
  [ "$status" -eq 0 ]
  [ "$(rows)" = "$(printf 'mise\tfailed\tk9s\tboom')" ]
}

@test "lib.sh: ig_try success writes no row" {
  . "$LIB"
  run ig_try mise jq true
  [ "$status" -eq 0 ]
  [ -z "$(rows)" ]
}

@test "lib.sh: ig_try keeps going under set -euo pipefail" {
  run bash -c "set -euo pipefail; . '$LIB'; ig_try brew tree false; echo after"
  [ "$status" -eq 0 ]
  [[ "$output" == *after ]]
  [[ "$(rows)" == "brew"$'\t'"failed"$'\t'"tree"* ]]
}

@test "lib.sh: ig_reset removes only its source" {
  . "$LIB"
  ig_report mise failed k9s one
  ig_report brew failed tree two
  ig_report mise needs-it helm three
  ig_reset mise
  [ "$(rows)" = "$(printf 'brew\tfailed\ttree\ttwo')" ]
}

@test "lib.sh: ig_reset without a report file is a no-op" {
  . "$LIB"
  run ig_reset mise
  [ "$status" -eq 0 ]
  [ ! -e "$REPORT" ]
}

@test "lib.sh: IGNITE_SKIP records skipped and does not run cmd" {
  . "$LIB"
  IGNITE_SKIP="docker-desktop,k9s" ig_try mise k9s touch "$BATS_TEST_TMPDIR/marker"
  [ ! -e "$BATS_TEST_TMPDIR/marker" ]
  [ "$(rows)" = "$(printf 'mise\tskipped\tk9s\tIGNITE_SKIP')" ]
}

@test "lib.sh: IGNITE_SKIP matches whole names only" {
  . "$LIB"
  IGNITE_SKIP="k9" ig_try mise k9s touch "$BATS_TEST_TMPDIR/marker"
  [ -e "$BATS_TEST_TMPDIR/marker" ]
  [ -z "$(rows)" ]
}

@test "lib.sh: rate-limit failure adds GITHUB_TOKEN hint" {
  . "$LIB"
  ig_try mise kubectl sh -c 'echo "mise ERROR GitHub API rate limit exceeded for 203.0.113.9"; exit 1'
  [[ "$(rows)" == *"rate limit exceeded"*"set GITHUB_TOKEN and retry" ]]
}

@test "lib.sh: detail strips tabs and newlines" {
  . "$LIB"
  ig_report brew failed tree "$(printf 'a\tb\nc')"
  [ "$(wc -l < "$REPORT" | tr -d ' ')" -eq 1 ]
  [ "$(awk -F '\t' '{ print NF }' "$REPORT")" -eq 4 ]
}

@test "lib.sh: ig_path_setup with IG_BREW_SEARCH empty never runs a real brew" {
  stubs="$BATS_TEST_TMPDIR/stubs"
  mkdir -p "$stubs"
  printf '#!/bin/sh\necho brew-was-called >&2\nexit 1\n' > "$stubs/brew"
  chmod +x "$stubs/brew"
  path=$(env HOME="$BATS_TEST_TMPDIR/h" IG_BREW_SEARCH="" PATH="$stubs:/usr/bin:/bin" \
    bash -c ". '$LIB'; ig_path_setup; printf '%s' \"\$PATH\"" 2>&1)
  [[ "$path" != *brew-was-called* ]]
  [[ ":$path:" != *":/opt/homebrew/bin:"* ]]
  # The stub dir stays ahead of anything ig_path_setup adds from the system.
  [[ "$path" == *"$stubs:/usr/bin:/bin" ]]
}

@test "lib.sh: ig_path_setup puts ~/.local/bin and mise shims on PATH" {
  path=$(env -u XDG_DATA_HOME -u KREW_ROOT HOME="$BATS_TEST_TMPDIR/h" IG_BREW_SEARCH="" \
    bash -c ". '$LIB'; ig_path_setup; printf '%s' \"\$PATH\"")
  [[ ":$path:" == *":$BATS_TEST_TMPDIR/h/.local/bin:"* ]]
  [[ ":$path:" == *":$BATS_TEST_TMPDIR/h/.local/share/mise/shims:"* ]]
  [[ ":$path:" == *":$BATS_TEST_TMPDIR/h/.krew/bin:"* ]]
}

@test "lib.sh: ig_retry tries again after a failure, and gives up after the limit" {
  . "$LIB"
  counter="$BATS_TEST_TMPDIR/count"
  flaky() { echo x >> "$counter"; [ "$(wc -l < "$counter")" -ge 2 ]; }
  IG_RETRY_DELAY=0 run ig_retry 2 flaky
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$counter" | tr -d ' ')" -eq 2 ]
  rm -f "$counter"
  IG_RETRY_DELAY=0 run ig_retry 3 false
  [ "$status" -ne 0 ]
}

@test "lib.sh: ig_sudo runs through sudo, or directly as root" {
  stubs="$BATS_TEST_TMPDIR/stubs"
  mkdir -p "$stubs"
  printf '#!/bin/sh\necho "sudo $*"\n' > "$stubs/sudo"
  printf '#!/bin/sh\necho 1000\n' > "$stubs/id"
  chmod +x "$stubs/sudo" "$stubs/id"
  run env PATH="$stubs:$PATH" bash -c ". '$LIB'; ig_sudo echo hi"
  [ "$output" = "sudo echo hi" ]
  printf '#!/bin/sh\necho 0\n' > "$stubs/id"
  run env PATH="$stubs:$PATH" bash -c ". '$LIB'; ig_sudo echo hi"
  [ "$output" = "hi" ]
}

@test "needs-it: script records needs_it entries for darwin-noadmin" {
  script="$BATS_TEST_TMPDIR/needs-it.sh"
  render_file darwin-noadmin "$REPO/home/.chezmoiscripts/run_onchange_after_05-needs-it.sh.tmpl" > "$script"
  grep -q '^ig_report plan needs-it rectangle ' "$script"
  run bash "$script"
  [ "$status" -eq 0 ]
  grep -q "^plan"$'\t'"needs-it"$'\t'"rectangle"$'\t'"needs admin$" "$REPORT"
  grep -q "^plan"$'\t'"needs-it"$'\t'"homebrew"$'\t' "$REPORT"
}

@test "needs-it: re-running replaces the previous plan rows" {
  script="$BATS_TEST_TMPDIR/needs-it.sh"
  render_file darwin-noadmin "$REPO/home/.chezmoiscripts/run_onchange_after_05-needs-it.sh.tmpl" > "$script"
  bash "$script"
  bash "$script"
  [ "$(grep -c $'\trectangle\t' "$REPORT")" -eq 1 ]
}

@test "needs-it: sh script is empty on windows and has no rows on darwin-admin" {
  [ -z "$(render_file windows-noadmin "$REPO/home/.chezmoiscripts/run_onchange_after_05-needs-it.sh.tmpl" | tr -d '[:space:]')" ]
  ! render_file darwin-admin "$REPO/home/.chezmoiscripts/run_onchange_after_05-needs-it.sh.tmpl" | grep -q '^ig_report '
}

@test "needs-it: ps1 script is empty off windows" {
  [ -z "$(render_file darwin-noadmin "$REPO/home/.chezmoiscripts/run_onchange_after_05-needs-it.ps1.tmpl" | tr -d '[:space:]')" ]
}
