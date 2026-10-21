#!/usr/bin/env bats

load helper

@test "validate: invalid catalog fails and names the problem" {
  with_catalog "$FIXTURES/catalogs/dup-job.yaml"
  run --separate-stderr "$REPO/scripts/validate-catalog.sh" "$SRC"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *'- b: job "editor_cli" also provided by a'* ]]
}

@test "validate: valid catalog passes for every fixture machine" {
  with_catalog "$FIXTURES/catalogs/valid.yaml"
  run --separate-stderr "$REPO/scripts/validate-catalog.sh" "$SRC"
  [ "$status" -eq 0 ]
  [[ "$output" == *"wsl-admin"* ]]
}

@test "validate: source without a catalog is skipped" {
  mkdir -p "$BATS_TEST_TMPDIR/empty/home"
  printf 'home\n' > "$BATS_TEST_TMPDIR/empty/.chezmoiroot"
  run --separate-stderr "$REPO/scripts/validate-catalog.sh" "$BATS_TEST_TMPDIR/empty"
  [ "$status" -eq 0 ]
  [[ "$output" == *"no catalog"* ]]
}
