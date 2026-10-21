#!/usr/bin/env bats
# The real catalog (home/.chezmoidata) resolved for each fixture machine.

load helper

FIXTURE_MACHINES="darwin-admin darwin-noadmin darwin-custom windows-admin windows-noadmin linux-admin wsl-admin"

select_for() {
  run --separate-stderr render_tpl "$1" '{{ includeTemplate "selected.json" . }}'
  [ "$status" -eq 0 ] || { echo "$1: $stderr"; return 1; }
}

method() {
  jq -r --arg n "$1" '.[$n].method // "absent"' <<< "$output"
}

@test "catalog: valid for every fixture" {
  for fixture in $FIXTURE_MACHINES; do
    select_for "$fixture"
    [ "$(jq 'length' <<< "$output")" -gt 10 ]
  done
}

@test "catalog: one selected entry per job on every fixture" {
  for fixture in $FIXTURE_MACHINES; do
    select_for "$fixture"
    dups=$(jq -r '[.[] | .job] | group_by(.) | map(select(length > 1) | .[0]) | join(",")' <<< "$output")
    [ -z "$dups" ] || { echo "$fixture: duplicate jobs: $dups"; false; }
  done
}

@test "catalog: darwin-admin defaults" {
  select_for darwin-admin
  [ "$(method vscode)" = cask ]
  [ "$(method ghostty)" != absent ]
  [ "$(method zed)" = absent ]
  [ "$(method starship)" = mise ]
  [ "$(method kind)" != absent ]
  [ "$(method minikube)" = absent ]
  [ "$(method colima)" != absent ]
  [ "$(method docker-cli)" != absent ]
  [ "$(method awscli)" != absent ]
  [ "$(method glab)" = absent ]
  [ "$(method cilium-cli)" = absent ]
  [ "$(method rectangle)" = cask ]
  [ "$(method claude-code)" = script ]
  [ "$(method oh-my-zsh)" = archive ]
  [ "$(method homebrew)" = bootstrap ]
}

@test "catalog: darwin-noadmin" {
  select_for darwin-noadmin
  [ "$(method vscode)" = user_app ]
  [ "$(method ghostty)" = user_app ]
  [ "$(method rectangle)" = needs_it ]
  [ "$(method homebrew)" = needs_it ]
  [ "$(method kubectl)" = mise ]
}

@test "catalog: windows-admin" {
  select_for windows-admin
  [ "$(method windows-terminal)" != absent ]
  [ "$(method ghostty)" = absent ]
  [ "$(method ansible)" = absent ]
  [ "$(method tmux)" = absent ]
  [ "$(method oh-my-zsh)" = absent ]
  [ "$(method ms-vscode-remote.remote-wsl)" = vscode_ext ]
  [ "$(method kubectl)" = mise ]
  [ "$(method pwsh)" = bootstrap ]
  [ "$(method rancher-desktop)" != absent ]
}

@test "catalog: krew's ctx, ns and neat stay off Windows; kubectx and kubens stand in" {
  select_for windows-admin
  [ "$(method krew-ctx)" = absent ]
  [ "$(method krew-ns)" = absent ]
  [ "$(method krew-neat)" = absent ]
  [ "$(method kubectx)" = mise ]
  [ "$(method kubens)" = mise ]
  select_for darwin-admin
  [ "$(method krew-ctx)" = krew ]
  [ "$(method kubectx)" = absent ]
}

@test "catalog: direnv comes from Scoop on Windows (aqua has no Windows build)" {
  for fixture in windows-admin windows-noadmin; do
    select_for "$fixture"
    [ "$(method direnv)" = scoop ]
  done
  select_for darwin-admin
  [ "$(method direnv)" = mise ]
}

@test "catalog: windows-noadmin uses no machine-wide winget installs" {
  select_for windows-noadmin
  [ "$(jq '[.[] | select(.method == "winget")] | length' <<< "$output")" -eq 0 ]
  [ "$(method vscode)" = winget_user ]
}

@test "catalog: wsl-admin" {
  select_for wsl-admin
  [ "$(method vscode)" = absent ]
  [ "$(jq '[.[] | select(.method == "vscode_ext")] | length' <<< "$output")" -eq 0 ]
  [ "$(jq '[.[] | select(.job == "terminal" or .job == "terminal_font" or .job == "container_engine")] | length' <<< "$output")" -eq 0 ]
  [ "$(method zsh)" = apt ]
  [ "$(method neovim)" = mise ]
}

@test "catalog: linux-admin" {
  select_for linux-admin
  [ "$(method glab)" != absent ]
  [ "$(method docker-engine)" = script ]
  [ "$(method hack-nerd-font)" = script ]
  [ "$(method vscode)" = script ]
  [ "$(method awscli)" = absent ]
}

@test "catalog: darwin-custom" {
  select_for darwin-custom
  [ "$(method zed)" != absent ]
  [ "$(method powerlevel10k)" = archive ]
  [ "$(method vscode)" = absent ]
  [ "$(method starship)" = absent ]
  [ "$(method docker-desktop)" = cask ]
  [ "$(method colima)" = absent ]
  [ "$(method docker-cli)" = absent ]
  [ "$(method cilium-cli)" != absent ]
}

@test "catalog: every entry named by later tasks exists" {
  names="vscode zed neovim vim ghostty windows-terminal warp starship powerlevel10k kind minikube multipass node nvm claude-code codex gemini-cli copilot-cli cursor opencode docker-desktop colima docker-cli rancher-desktop docker-engine hack-nerd-font oh-my-zsh zsh-autosuggestions zsh-syntax-highlighting zsh-bat you-should-use zsh-completions zsh-autocomplete krew kubectl chezmoi mise git homebrew pwsh scoop zsh"
  catalog=$(chezmoi --source "$REPO" --config "$FIXTURES/config/darwin-admin.toml" \
    --persistent-state "$BATS_TEST_TMPDIR/state.boltdb" \
    execute-template '{{ .packages | toJson }}')
  for name in $names; do
    jq -e --arg n "$name" 'has($n)' <<< "$catalog" > /dev/null || { echo "missing: $name"; false; }
  done
}
