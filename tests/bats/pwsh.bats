#!/usr/bin/env bats
# PowerShell side: completions script, Windows Terminal files, managed targets.

load helper

SCRIPTS="$REPO/home/.chezmoiscripts"

@test "pwsh: completions script lists flux and kubectl" {
  run render_file windows-admin "$SCRIPTS/run_onchange_after_87-pwsh-completions.ps1.tmpl"
  [ "$status" -eq 0 ]
  grep -qx "Save-IgniteCompletion -Name 'flux' -Bin 'flux'" <<< "$output"
  grep -qx "Save-IgniteCompletion -Name 'kubectl' -Bin 'kubectl'" <<< "$output"
  grep -qx "Save-IgniteCompletion -Name 'gh' -Bin 'gh'" <<< "$output"
  ! grep -q "'vault'" <<< "$output"
  run render_file darwin-admin "$SCRIPTS/run_onchange_after_87-pwsh-completions.ps1.tmpl"
  [ -z "$(tr -d '[:space:]' <<< "$output")" ]
}

@test "pwsh: profile shim and terminal scripts only render on windows" {
  for script in run_after_85-pwsh-profile-shim.ps1.tmpl run_after_86-windows-terminal.ps1.tmpl; do
    run render_file windows-admin "$SCRIPTS/$script"
    [ -n "$(tr -d '[:space:]' <<< "$output")" ] || { echo "$script empty on windows"; false; }
    run render_file darwin-admin "$SCRIPTS/$script"
    [ -z "$(tr -d '[:space:]' <<< "$output")" ] || { echo "$script not empty on darwin"; false; }
  done
  run render_file windows-admin "$SCRIPTS/run_after_85-pwsh-profile-shim.ps1.tmpl"
  grep -q 'Install-IgniteProfileShim -ProfilePath $PROFILE.CurrentUserAllHosts' <<< "$output"
}

@test "pwsh: terminal fragment is a valid Catppuccin Mocha scheme" {
  fragment="$REPO/home/AppData/Local/Microsoft/Windows Terminal/Fragments/ignite/ignite.json"
  [ "$(jq -r '.schemes[0].name' "$fragment")" = "Catppuccin Mocha" ]
  for color in black red green yellow blue purple cyan white brightBlack brightRed brightGreen brightYellow brightBlue brightPurple brightCyan brightWhite; do
    jq -e --arg c "$color" '.schemes[0][$c] | test("^#[0-9A-Fa-f]{6}$")' "$fragment" > /dev/null || { echo "bad $color"; false; }
  done
}

@test "managed: darwin-admin manages no AppData" {
  run --separate-stderr managed darwin-admin
  [ "$status" -eq 0 ]
  ! grep -q '^AppData' <<< "$output"
  ! grep -q '^.config/powershell' <<< "$output"
  run --separate-stderr managed windows-admin
  [ "$status" -eq 0 ]
  grep -qx '.config/powershell/profile.ps1' <<< "$output"
  grep -qx 'AppData/Local/Microsoft/Windows Terminal/Fragments/ignite/ignite.json' <<< "$output"
}
