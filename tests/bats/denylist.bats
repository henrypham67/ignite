#!/usr/bin/env bats

load helper

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  unset IGNITE_DENYLIST IGNITE_DENYLIST_REQUIRED
  work="$BATS_TEST_TMPDIR/work"
  mkdir -p "$work"
  git -C "$work" init -q
  printf 'line one\nwe work at AcmeCorp here\n' > "$work/notes.md"
  printf 'nothing to see\n' > "$work/clean.md"
  git -C "$work" add notes.md clean.md
}

@test "denylist: hit prints file:line and exits 1" {
  cd "$work"
  IGNITE_DENYLIST=acmecorp run "$REPO/scripts/check-denylist.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"notes.md:2"* ]]
  [[ "$output" != *"clean.md"* ]]
  [[ "$output" != *[Aa]cme[Cc]orp* ]]
  while IFS= read -r line; do
    [[ "$line" =~ ^[^:]+:[0-9]+$ ]] || [[ "$line" == denylist:* ]]
  done <<< "$output"
}

@test "denylist: terms from the local file are used" {
  mkdir -p "$HOME/.config/ignite"
  printf 'someterm\nacmecorp\n' > "$HOME/.config/ignite/denylist.txt"
  cd "$work"
  run "$REPO/scripts/check-denylist.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"notes.md:2"* ]]
}

@test "denylist: comma-separated env terms" {
  cd "$work"
  IGNITE_DENYLIST="foo,acmecorp" run "$REPO/scripts/check-denylist.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"notes.md:2"* ]]
}

@test "denylist: no hits exits 0" {
  cd "$work"
  IGNITE_DENYLIST=othercorp run "$REPO/scripts/check-denylist.sh"
  [ "$status" -eq 0 ]
}

@test "denylist: no terms configured skips with notice" {
  cd "$work"
  run "$REPO/scripts/check-denylist.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"denylist empty"* ]]
}

@test "denylist: required but missing fails" {
  cd "$work"
  IGNITE_DENYLIST_REQUIRED=1 run "$REPO/scripts/check-denylist.sh"
  [ "$status" -eq 1 ]
}
