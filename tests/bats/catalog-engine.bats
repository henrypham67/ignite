#!/usr/bin/env bats
# The catalog engine (validate-catalog, effective-choices.json, selected.json)
# run against small fixture catalogs.

load helper

# select_for <fixture>: render selected.json for a fixture machine into $output.
select_for() {
  run --separate-stderr render_tpl "$1" '{{ includeTemplate "selected.json" . }}'
}

# method <name>: method of an entry in the last select_for output, or "absent".
method() {
  jq -r --arg n "$1" '.[$n].method // "absent"' <<< "$output"
}

# problems: the "- " lines of the last validation failure.
problems() {
  grep -c '^- ' <<< "$stderr" || true
}

@test "validator: duplicate job without options fails" {
  with_catalog "$FIXTURES/catalogs/dup-job.yaml"
  select_for darwin-admin
  [ "$status" -ne 0 ]
  [[ "$stderr" == *"ignite catalog invalid (1 problems)"* ]]
  [[ "$stderr" == *'- b: job "editor_cli" also provided by a'* ]]
}

@test "validator: reports all violations at once" {
  with_catalog "$FIXTURES/catalogs/two-errors.yaml"
  select_for darwin-admin
  [ "$status" -ne 0 ]
  [ "$(problems)" -eq 2 ]
  [[ "$stderr" == *'- c: '*'group'* ]]
}

@test "validator: mixed option/non-option in one job fails" {
  with_catalog "$FIXTURES/catalogs/mixed-option.yaml"
  select_for darwin-admin
  [ "$status" -ne 0 ]
  [[ "$stderr" == *'- editor: '* ]]
  [ "$(problems)" -eq 1 ]
}

@test "validator: no usable source on a platform fails" {
  with_catalog "$FIXTURES/catalogs/no-source.yaml"
  select_for darwin-admin
  [ "$status" -ne 0 ]
  [[ "$stderr" == *'- maconly: no install source for windows'* ]]
}

@test "validator: requires chain fails" {
  with_catalog "$FIXTURES/catalogs/bad-requires.yaml"
  select_for darwin-admin
  [ "$status" -ne 0 ]
  [[ "$stderr" == *'- c: '*'b'* ]]
  [[ "$stderr" == *'- d: '*'missing'* ]]
  [[ "$stderr" != *'- b: '* ]]
  [ "$(problems)" -eq 2 ]
}

@test "validator: default not an option fails" {
  with_catalog "$FIXTURES/catalogs/bad-default.yaml"
  select_for darwin-admin
  [ "$status" -ne 0 ]
  [[ "$stderr" == *'- editor: '*'vscode'* ]]
}

@test "validator: valid catalog passes on every fixture" {
  with_catalog "$FIXTURES/catalogs/valid.yaml"
  for fixture in darwin-admin darwin-noadmin darwin-custom windows-admin windows-noadmin linux-admin wsl-admin; do
    select_for "$fixture"
    [ "$status" -eq 0 ] || { echo "$fixture: $stderr"; false; }
    jq -e 'type == "object"' <<< "$output" > /dev/null
  done
}

@test "selection: option entry follows choice" {
  with_catalog "$FIXTURES/catalogs/valid.yaml"
  select_for darwin-admin
  [ "$(method vscode)" != absent ]
  [ "$(method zed)" = absent ]
  [ "$(method starship)" = mise ]
  [ "$(method powerlevel10k)" = absent ]

  select_for darwin-custom
  [ "$(method vscode)" = absent ]
  [ "$(method zed)" = cask ]
  [ "$(method starship)" = absent ]
  [ "$(method powerlevel10k)" = archive ]
}

@test "selection: per-os default choice" {
  with_catalog "$FIXTURES/catalogs/valid.yaml"
  select_for darwin-admin
  [ "$(method ghostty)" = cask ]
  [ "$(method windows-terminal)" = absent ]
  select_for windows-admin
  [ "$(method windows-terminal)" = winget ]
  [ "$(method ghostty)" = absent ]
  select_for wsl-admin
  [ "$(method ghostty)" = absent ]
}

@test "selection: method order darwin" {
  with_catalog "$FIXTURES/catalogs/valid.yaml"
  select_for darwin-admin
  [ "$(method kubectl)" = mise ]
  [ "$(method vscode)" = cask ]
  [ "$(method rectangle)" = cask ]
  [ "$(method tree)" = brew ]
  select_for darwin-noadmin
  [ "$(method kubectl)" = mise ]
  [ "$(method vscode)" = user_app ]
  [ "$(method rectangle)" = needs_it ]
  [ "$(method tree)" = needs_it ]
}

@test "selection: method order windows" {
  with_catalog "$FIXTURES/catalogs/valid.yaml"
  select_for windows-noadmin
  [ "$(method vscode)" = winget_user ]
  [ "$(method sevenzip)" = scoop ]
  [ "$(method kubectl)" = mise ]
  select_for windows-admin
  [ "$(method vscode)" = winget ]
  [ "$(method sevenzip)" = winget ]
}

@test "selection: method order linux" {
  with_catalog "$FIXTURES/catalogs/valid.yaml"
  select_for linux-admin
  [ "$(method tree)" = apt ]
  [ "$(method vscode)" = script ]
  [ "$(method kubectl)" = mise ]
}

@test "selection: admin_only on noadmin gives needs_it" {
  with_catalog "$FIXTURES/catalogs/valid.yaml"
  select_for darwin-noadmin
  [ "$(method homebrew)" = needs_it ]
  select_for darwin-admin
  [ "$(method homebrew)" = bootstrap ]
}

@test "selection: container_engine computed" {
  with_catalog "$FIXTURES/catalogs/valid.yaml"
  select_for darwin-admin
  [ "$(method colima)" = brew ]
  [ "$(method docker-desktop)" = absent ]
  select_for darwin-custom
  [ "$(method docker-desktop)" = cask ]
  [ "$(method colima)" = absent ]
  select_for windows-noadmin
  [ "$(method rancher-desktop)" = needs_it ]
  select_for linux-admin
  [ "$(method docker-engine)" = script ]
  select_for wsl-admin
  [ "$(jq -r '[.[] | select(.job == "container_engine")] | length' <<< "$output")" -eq 0 ]
}

@test "selection: groups follow machine flags" {
  with_catalog "$FIXTURES/catalogs/valid.yaml"
  select_for linux-admin
  [ "$(method glab)" = mise ]
  [ "$(method awscli)" = absent ]
  [ "$(method cilium-cli)" = absent ]
  select_for darwin-admin
  [ "$(method glab)" = absent ]
  [ "$(method awscli)" = mise ]
  select_for darwin-custom
  [ "$(method cilium-cli)" = mise ]
}

@test "selection: other kinds keep their kind as method" {
  with_catalog "$FIXTURES/catalogs/valid.yaml"
  select_for darwin-admin
  [ "$(method krew-ctx)" = krew ]
  [ "$(method hashicorp.terraform)" = vscode_ext ]
}

@test "selection: requires drops dependents" {
  with_catalog "$FIXTURES/catalogs/valid.yaml"
  select_for wsl-admin
  [ "$(method vscode)" = absent ]
  [ "$(method hashicorp.terraform)" = absent ]
  select_for darwin-custom
  [ "$(method hashicorp.terraform)" = absent ]
}

@test "selection: entry fields are carried through" {
  with_catalog "$FIXTURES/catalogs/valid.yaml"
  select_for darwin-admin
  [ "$(jq -r '.vscode.bin' <<< "$output")" = code ]
  [ "$(jq -r '.vscode.job' <<< "$output")" = editor ]
}

@test "choices: unknown option in machine config fails with valid list" {
  with_catalog "$FIXTURES/catalogs/valid.yaml"
  cp "$FIXTURES/config/darwin-admin.toml" "$BATS_TEST_TMPDIR/bad.toml"
  printf 'editor = "emacs"\n' >> "$BATS_TEST_TMPDIR/bad.toml"
  run --separate-stderr chezmoi --source "$SRC" --config "$BATS_TEST_TMPDIR/bad.toml" \
    --persistent-state "$BATS_TEST_TMPDIR/state.boltdb" \
    execute-template '{{ includeTemplate "effective-choices.json" . }}'
  [ "$status" -ne 0 ]
  [[ "$stderr" == *'unknown option "emacs" for editor; valid: vscode, zed'* ]]
}
