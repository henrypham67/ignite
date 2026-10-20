#!/usr/bin/env bats
# Windows install scripts, rendered per fixture. They only run on Windows, so
# these tests check the rendered text; tests/pester checks that they parse.

load helper

SCRIPTS="$REPO/home/.chezmoiscripts"

render_script() {
  local out
  out="$BATS_TEST_TMPDIR/$(basename "$1" .toml)-$2"
  render_file "$1" "$SCRIPTS/$2" > "$out"
  echo "$out"
}

is_empty() {
  [ -z "$(tr -d '[:space:]' < "$1")" ]
}

@test "windows: winget script empty on windows-noadmin" {
  is_empty "$(render_script windows-noadmin run_onchange_after_10-winget.ps1.tmpl)"
}

@test "windows: winget script installs from one elevated batch" {
  script=$(render_script windows-admin run_onchange_after_10-winget.ps1.tmpl)
  [ "$(grep -c -- '-Verb RunAs' "$script")" -eq 1 ]
  grep -qx "Install-IgniteWinget -Name 'vscode' -Id 'Microsoft.VisualStudioCode'" "$script"
  grep -qx "Install-IgniteWinget -Name 'rancher-desktop' -Id 'SUSE.RancherDesktop'" "$script"
  grep -q -- '--scope machine' "$script"
  ! grep -q 'ZedIndustries' "$script"
}

@test "windows: scoop script on noadmin includes vscode via winget --scope user" {
  script=$(render_script windows-noadmin run_onchange_after_25-scoop.ps1.tmpl)
  grep -qx "Install-IgniteWingetUser -Name 'vscode' -Id 'Microsoft.VisualStudioCode'" "$script"
  grep -q -- '--scope user' "$script"
  grep -qx "Install-IgniteScoop -Name 'awscli' -App 'main/aws'" "$script"
  ! grep -q 'Microsoft.VisualStudioCode' "$(render_script windows-admin run_onchange_after_25-scoop.ps1.tmpl)"
}

@test "windows: mise script orders runtimes first and keeps windows-skipped tools out" {
  script=$(render_script windows-admin run_onchange_after_20-mise.ps1.tmpl)
  items=$(sed -n "s/^Install-IgniteMise -Name '\([^']*\)'.*/\1/p" "$script")
  [ "$(head -n 4 <<< "$items" | tr '\n' ' ')" = "node python go uv " ]
  grep -qx kubectl <<< "$items"
  ! grep -qx awscli <<< "$items"
}

@test "windows: krew, scripts and vscode-ext render for windows-admin" {
  grep -qx "Install-IgniteKrew -Name 'krew-ctx' -Plugin 'ctx'" "$(render_script windows-admin run_onchange_after_50-krew.ps1.tmpl)"
  scripts=$(render_script windows-admin run_onchange_after_40-scripts.ps1.tmpl)
  grep -q "Invoke-IgniteTry -Source script -Item 'claude-code'" "$scripts"
  grep -q "Invoke-IgniteTry -Source script -Item 'hack-nerd-font'" "$scripts"
  ext=$(render_script windows-admin run_onchange_after_60-vscode-ext.ps1.tmpl)
  grep -q "'ms-vscode-remote.remote-wsl'" "$ext"
  grep -q 'code.cmd' "$ext"
}

@test "windows: ps1 scripts empty on darwin-admin" {
  for template in "$SCRIPTS"/*.ps1.tmpl; do
    is_empty "$(render_script darwin-admin "$(basename "$template")")" || { echo "$(basename "$template")"; false; }
  done
}
