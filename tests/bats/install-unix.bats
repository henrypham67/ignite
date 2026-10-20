#!/usr/bin/env bats
# Unix install scripts rendered per fixture machine and run against stubs.

load helper

SCRIPTS="$REPO/home/.chezmoiscripts"

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  export XDG_STATE_HOME="$HOME/.local/state"
  REPORT="$XDG_STATE_HOME/ignite/report.tsv"
  STUBS="$BATS_TEST_TMPDIR/stubs"
  CALLS="$BATS_TEST_TMPDIR/calls.log"
  mkdir -p "$STUBS"
  : > "$CALLS"
  unset IGNITE_SKIP
  # Guard: anything that installs software fails loudly unless a test stubs it
  # on purpose. These rendered scripts must never reach the real tools.
  for tool in brew mise kubectl code apt-get sudo curl snap hdiutil wget; do
    stub "$tool" "echo 'unexpected call: $tool' >&2; exit 97"
  done
}

# stub <name> [body]: fake command that logs "name args" to $CALLS.
stub() {
  printf '#!/bin/bash\necho "%s $*" >> "%s"\n%s\n' "$1" "$CALLS" "${2:-exit 0}" > "$STUBS/$1"
  chmod +x "$STUBS/$1"
}

# render_script <fixture> <script file name>: render into $BATS_TEST_TMPDIR.
render_script() {
  local out
  out="$BATS_TEST_TMPDIR/$(basename "$1" .toml)-$2"
  render_file "$1" "$SCRIPTS/$2" > "$out"
  echo "$out"
}

# run_script <path>: run a rendered script with only the stubs and base tools
# on PATH, and with Homebrew's shellenv disabled (it would put the real
# /opt/homebrew/bin ahead of the stubs).
run_script() {
  run env PATH="$STUBS:/usr/bin:/bin:/usr/sbin:/sbin" IG_BREW_SEARCH="" bash "$1"
  ! grep -q '^unexpected call' <<< "$output" || { echo "$output"; return 1; }
}

is_empty() {
  [ -z "$(tr -d '[:space:]' < "$1")" ]
}

# fixture_with_choice <fixture> <job> <option>: path to a copy of a fixture
# with one tool choice set (the fixtures end with [data.ignite.choices]).
fixture_with_choice() {
  local path="$BATS_TEST_TMPDIR/$1-$2-$3.toml"
  cp "$FIXTURES/config/$1.toml" "$path"
  printf '%s = "%s"\n' "$2" "$3" >> "$path"
  echo "$path"
}

@test "install: brew script empty on noadmin and non-darwin" {
  for fixture in darwin-noadmin linux-admin wsl-admin windows-admin; do
    is_empty "$(render_script "$fixture" run_onchange_after_10-brew.sh.tmpl)" || { echo "$fixture not empty"; false; }
  done
}

@test "install: darwin-admin brew script installs casks with --cask" {
  script=$(render_script darwin-admin run_onchange_after_10-brew.sh.tmpl)
  grep -qx 'ig_try brew vscode brew install --cask visual-studio-code' "$script"
  stub brew
  run_script "$script"
  [ "$status" -eq 0 ]
  grep -qx 'brew install --cask visual-studio-code' "$CALLS"
  grep -qx 'brew install --cask ghostty' "$CALLS"
  grep -qx 'brew install --formula colima' "$CALLS"
  ! grep -q 'zed' "$CALLS"
}

@test "install: brew failure is recorded and the script carries on" {
  script=$(render_script darwin-admin run_onchange_after_10-brew.sh.tmpl)
  stub brew 'case "$*" in *ghostty*) echo "Error: cask ghostty download failed"; exit 1 ;; esac'
  run_script "$script"
  [ "$status" -eq 0 ]
  grep -qx 'brew install --cask visual-studio-code' "$CALLS"
  grep -q "^brew"$'\t'"failed"$'\t'"ghostty"$'\t'"Error: cask ghostty download failed$" "$REPORT"
}

@test "install: apt script runs apt-get update once then installs zsh" {
  script=$(render_script linux-admin run_onchange_after_10-apt.sh.tmpl)
  stub sudo 'exec "$@"'
  stub apt-get
  stub id 'echo 1000'
  run_script "$script"
  [ "$status" -eq 0 ]
  [ "$(grep -c '^apt-get update' "$CALLS")" -eq 1 ]
  [ "$(grep '^apt-get' "$CALLS" | head -n 1)" = "apt-get update -y" ]
  grep -qx 'apt-get install -y zsh' "$CALLS"
  is_empty "$(render_script darwin-admin run_onchange_after_10-apt.sh.tmpl)"
}

@test "install: mise config for windows omits mise_skip entries" {
  win=$(render_file windows-admin "$REPO/home/dot_config/mise/config.toml.tmpl")
  mac=$(render_file darwin-admin "$REPO/home/dot_config/mise/config.toml.tmpl")
  grep -qx '"kubectl" = "latest"' <<< "$win"
  grep -qx '"node" = "lts"' <<< "$win"
  ! grep -q 'aws-cli' <<< "$win"
  grep -qx '"aws-cli" = "latest"' <<< "$mac"
  grep -qx '\[tools\]' <<< "$mac"
}

@test "install: mise script orders node,python,go first and npm: last" {
  fixture=$(fixture_with_choice darwin-admin ai_assistant gemini-cli)
  script=$(render_script "$fixture" run_onchange_after_20-mise.sh.tmpl)
  stub mise
  run_script "$script"
  [ "$status" -eq 0 ]
  installs=$(grep '^mise install' "$CALLS" | sed 's/^mise install //')
  [ "$(head -n 4 <<< "$installs" | tr '\n' ' ')" = "node@lts python@3.13 go@latest uv@latest " ]
  [ "$(tail -n 1 <<< "$installs")" = "npm:@google/gemini-cli@latest" ]
  grep -qx 'kubectl@latest' <<< "$installs"
}

@test "install: mise script is empty on windows" {
  is_empty "$(render_script windows-admin run_onchange_after_20-mise.sh.tmpl)"
}

@test "install: user-apps only on darwin-noadmin and includes vscode zip" {
  for fixture in darwin-admin linux-admin wsl-admin windows-noadmin; do
    is_empty "$(render_script "$fixture" run_onchange_after_30-user-apps.sh.tmpl)" || { echo "$fixture"; false; }
  done
  script=$(render_script darwin-noadmin run_onchange_after_30-user-apps.sh.tmpl)
  grep -q 'https://update.code.visualstudio.com/latest/darwin-universal/stable' "$script"
  grep -q 'Ghostty.dmg' "$script"
}

@test "install: user-apps unpacks a zip into ~/Applications and links the CLI" {
  [ "$(uname -s)" = Darwin ] || skip "macOS only"
  script=$(render_script darwin-noadmin run_onchange_after_30-user-apps.sh.tmpl)
  # A fake VS Code download: a zip holding an .app with its bundled CLI.
  pkg="$BATS_TEST_TMPDIR/pkg"
  mkdir -p "$pkg/Visual Studio Code.app/Contents/Resources/app/bin"
  printf '#!/bin/sh\necho code\n' > "$pkg/Visual Studio Code.app/Contents/Resources/app/bin/code"
  chmod +x "$pkg/Visual Studio Code.app/Contents/Resources/app/bin/code"
  (cd "$pkg" && /usr/bin/zip -qr "$BATS_TEST_TMPDIR/vscode.zip" "Visual Studio Code.app")
  stub curl "out=''; while [ \$# -gt 0 ]; do [ \"\$1\" = -o ] && out=\$2; shift; done; case \"\$out\" in *) cp '$BATS_TEST_TMPDIR/vscode.zip' \"\$out\" ;; esac"
  stub hdiutil 'exit 1'
  IGNITE_SKIP=ghostty run_script "$script"
  [ "$status" -eq 0 ]
  [ -x "$HOME/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code" ]
  [ -L "$HOME/.local/bin/code" ]
  [ "$("$HOME/.local/bin/code")" = code ]
  ! grep -q $'\tfailed\tvscode\t' "$REPORT" 2>/dev/null
}

@test "install: vscode-ext empty on wsl-admin" {
  is_empty "$(render_script wsl-admin run_onchange_after_60-vscode-ext.sh.tmpl)"
  is_empty "$(render_script darwin-custom run_onchange_after_60-vscode-ext.sh.tmpl)"
}

@test "install: vscode-ext installs each extension with the code CLI" {
  script=$(render_script darwin-admin run_onchange_after_60-vscode-ext.sh.tmpl)
  stub code
  IG_CODE_SEARCH="" run_script "$script"
  [ "$status" -eq 0 ]
  grep -qx 'code --install-extension hashicorp.terraform' "$CALLS"
  grep -qx 'code --install-extension amazonwebservices.aws-toolkit-vscode' "$CALLS"
  ! grep -q 'remote-wsl' "$CALLS"
}

@test "install: vscode-ext without a code CLI records one failure per extension" {
  script=$(render_script darwin-admin run_onchange_after_60-vscode-ext.sh.tmpl)
  rm "$STUBS/code"
  IG_CODE_SEARCH="" run_script "$script"
  [ "$status" -eq 0 ]
  grep -qx "vscode-ext"$'\t'"failed"$'\t'"hashicorp.terraform"$'\t'"VS Code CLI not found" "$REPORT"
  [ "$(grep -c 'VS Code CLI not found' "$REPORT")" -gt 10 ]
}

@test "install: krew updates once then installs each plugin" {
  script=$(render_script darwin-admin run_onchange_after_50-krew.sh.tmpl)
  stub kubectl
  run_script "$script"
  [ "$status" -eq 0 ]
  [ "$(head -n 1 "$CALLS")" = "kubectl krew update" ]
  for plugin in ctx ns neat view-secret; do
    grep -qx "kubectl krew install $plugin" "$CALLS"
  done
  ! grep -q cnpg "$CALLS"
}

@test "install: script entries run as functions, admin-only ones in 15" {
  user=$(render_script linux-admin run_onchange_after_40-scripts.sh.tmpl)
  admin=$(render_script linux-admin run_onchange_after_15-scripts-admin.sh.tmpl)
  grep -qx 'ig_try script claude-code ig_install_claude_code' "$user"
  grep -qx 'ig_try script hack-nerd-font ig_install_hack_nerd_font' "$user"
  grep -qx 'ig_try script vscode ig_install_vscode' "$user"
  grep -qx 'ig_try script-admin docker-engine ig_install_docker_engine' "$admin"
  grep -qx 'ig_try script-admin ghostty ig_install_ghostty' "$admin"
  ! grep -q docker-engine "$user"
  ! grep -q 'ig_install_ghostty' "$user"
  is_empty "$(render_script darwin-admin run_onchange_after_15-scripts-admin.sh.tmpl)"
}

@test "install: every script entry has its install templates" {
  catalog=$(chezmoi --source "$REPO" --config "$FIXTURES/config/darwin-admin.toml" \
    --persistent-state "$BATS_TEST_TMPDIR/state.boltdb" execute-template '{{ .packages | toJson }}')
  missing=$(jq -r '
    to_entries[]
    | select(.value.script != null and .value.script != false)
    | .key as $name
    | (if (.value.script | type) == "array" then .value.script else (.value.platforms // ["darwin","windows","linux","wsl"]) end) as $where
    | select($where | index("windows"))
    | $name' <<< "$catalog" | while read -r name; do
      [ -f "$REPO/home/.chezmoitemplates/install/$name.ps1" ] || echo "$name"
    done)
  [ -z "$missing" ] || { echo "missing .ps1: $missing"; false; }
}

@test "install: every unix script entry has its .sh install template" {
  catalog=$(chezmoi --source "$REPO" --config "$FIXTURES/config/darwin-admin.toml" \
    --persistent-state "$BATS_TEST_TMPDIR/state.boltdb" execute-template '{{ .packages | toJson }}')
  missing=$(jq -r '
    to_entries[]
    | select(.value.script != null and .value.script != false)
    | .key as $name
    | (if (.value.script | type) == "array" then .value.script else (.value.platforms // ["darwin","windows","linux","wsl"]) end) as $where
    | select([$where[] | select(. != "windows")] | length > 0)
    | $name' <<< "$catalog" | while read -r name; do
      [ -f "$REPO/home/.chezmoitemplates/install/$name.sh" ] || echo "$name"
    done)
  [ -z "$missing" ] || { echo "missing .sh: $missing"; false; }
}

@test "install: all rendered sh scripts pass shellcheck" {
  for fixture in darwin-admin darwin-noadmin linux-admin wsl-admin; do
    for template in "$SCRIPTS"/*.sh.tmpl; do
      out=$(render_script "$fixture" "$(basename "$template")")
      is_empty "$out" && continue
      shellcheck --shell=bash "$out" || { echo "$fixture $(basename "$template")"; false; }
    done
  done
}
