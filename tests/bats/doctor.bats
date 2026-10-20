#!/usr/bin/env bats
# ignite-doctor (sh), rendered per fixture and run against stub commands.

load helper

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  export XDG_STATE_HOME="$HOME/.local/state"
  REPORT="$XDG_STATE_HOME/ignite/report.tsv"
  STUBS="$BATS_TEST_TMPDIR/stubs"
  mkdir -p "$STUBS" "$(dirname "$REPORT")"
  DOCTOR="$BATS_TEST_TMPDIR/ignite-doctor"
}

stub() {
  printf '#!/bin/bash\n%s\n' "${2:-exit 0}" > "$STUBS/$1"
  chmod +x "$STUBS/$1"
}

# install_everything <fixture>: render the doctor and fake every expected tool.
install_everything() {
  render_file "$1" "$REPO/home/dot_local/bin/executable_ignite-doctor.tmpl" > "$DOCTOR"
  chmod +x "$DOCTOR"
  local checks kind value
  checks=$(render_file "$1" "$REPO/home/.chezmoitemplates/doctor-checks.tsv")
  while IFS=$'\t' read -r row _name _job _method kind value _spec; do
    [ "$row" = expect ] || continue
    case "$kind" in
      bin) stub "$value" ;;
      path) mkdir -p "$HOME/$value" ;;
    esac
  done <<< "$checks"
  plugins=$(awk -F'\t' '$1 == "expect" && $5 == "krew" { print $6 }' <<< "$checks")
  extensions=$(awk -F'\t' '$1 == "expect" && $5 == "vscode" { print $6 }' <<< "$checks")
  stub kubectl "[ \"\$1 \$2\" = 'krew list' ] && printf '%s\n' $(printf "'%s' " $plugins); exit 0"
  stub code "[ \"\$1\" = --list-extensions ] && printf '%s\n' $(printf "'%s' " $extensions); exit 0"
  stub mise "[ \"\$1\" = current ] && echo 9.9.9; exit 0"
  stub gh 'exit 0'
  stub aws "echo default"
  mkdir -p "$HOME/.ssh"
  printf 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITestKey ci@example.com laptop\n' > "$HOME/.ssh/id_ed25519.pub"
  : > "$HOME/.ssh/id_ed25519"
  # Reading the key with an empty passphrase works: it has no passphrase.
  stub ssh-keygen 'exit 0'
}

doctor() {
  run env PATH="$STUBS:/usr/bin:/bin" IG_BREW_SEARCH="" IG_CODE_SEARCH="" "$DOCTOR"
}

@test "doctor: all present exits 0" {
  install_everything darwin-admin
  doctor
  [ "$status" -eq 0 ]
  [[ "$output" == *"ignite doctor"*"darwin, admin"* ]]
  [[ "$output" != *MISSING* ]]
  [[ "$output" == *"kubectl"*"9.9.9"* ]]
  [[ "$output" == *"Summary: "*" 0 missing"* ]]
}

@test "doctor: missing k9s exits 1 and prints MISSING k9s" {
  install_everything darwin-admin
  rm "$STUBS/k9s"
  doctor
  [ "$status" -eq 1 ]
  grep -Eq '^ +MISSING +k9s' <<< "$output"
  [[ "$output" == *"1 missing"* ]]
}

@test "doctor: needs-it row is listed and not counted missing" {
  install_everything darwin-noadmin
  rm -rf "$HOME/Applications/Rectangle.app"
  printf 'plan\tneeds-it\trectangle\tneeds admin\n' > "$REPORT"
  doctor
  [[ "$output" == *"Needs IT"*"rectangle"*"needs admin"* ]]
  ! grep -Eq '^ +MISSING +rectangle' <<< "$output"
  # /Applications on the machine running the tests may or may not have it.
  [ "$status" -eq 0 ]
}

@test "doctor: failed row prints retry command" {
  install_everything darwin-admin
  rm "$STUBS/k9s"
  printf 'mise\tfailed\tk9s\tGitHub API rate limit exceeded; set GITHUB_TOKEN and retry\n' > "$REPORT"
  doctor
  [ "$status" -eq 1 ]
  [[ "$output" == *"Failed installs"*"k9s"*"set GITHUB_TOKEN and retry"* ]]
  grep -qF "chezmoi state delete --bucket=entryState --key='$HOME/.chezmoiscripts/20-mise.sh'" <<< "$output"
  grep -qx '    chezmoi apply' <<< "$output"
  [[ "$output" != *delete-bucket* ]]
}

@test "doctor: retry re-runs exactly the script that failed" {
  install_everything darwin-admin
  printf 'mise\tfailed\tk9s\tboom\nbrew\tfailed\tghostty\tboom\n' > "$REPORT"
  doctor
  keys=$(grep -o "key='[^']*'" <<< "$output" | sed "s/key='//; s/'\$//")
  [ "$(wc -l <<< "$keys" | tr -d ' ')" -eq 2 ]
  # The printed keys really re-run those onchange scripts in chezmoi.
  sandbox="$BATS_TEST_TMPDIR/sandbox"
  mkdir -p "$sandbox/src/home/.chezmoiscripts"
  printf 'home\n' > "$sandbox/src/.chezmoiroot"
  for name in 20-mise 10-brew 50-krew; do
    printf '#!/bin/sh\necho %s >> "$HOME/runs"\n' "$name" > "$sandbox/src/home/.chezmoiscripts/run_onchange_after_$name.sh"
  done
  : > "$sandbox/c.toml"
  sbx() { chezmoi --source "$sandbox/src" --destination "$HOME" --config "$sandbox/c.toml" \
    --persistent-state "$sandbox/state.db" --cache "$sandbox/cache" "$@"; }
  sbx apply
  : > "$HOME/runs"
  while read -r key; do sbx state delete --bucket=entryState --key="$key"; done <<< "$keys"
  sbx apply
  [ "$(sort "$HOME/runs" | tr '\n' ' ')" = "10-brew 20-mise " ]
}

@test "doctor: skipped entries don't count as missing" {
  install_everything darwin-admin
  rm "$STUBS/colima"
  printf 'brew\tskipped\tcolima\tIGNITE_SKIP\n' > "$REPORT"
  doctor
  [ "$status" -eq 0 ]
  [[ "$output" == *"Skipped"*"colima"* ]]
}

@test "doctor: zed present while editor=vscode reports duplicate" {
  install_everything darwin-admin
  stub zed
  doctor
  [[ "$output" == *"Duplicates"*"editor: vscode (selected) and zed (also installed)"* ]]
}

@test "doctor: a system binary is not a duplicate" {
  install_everything darwin-admin
  # vim (an alternative to neovim) ships with the OS in /usr/bin.
  [ -x /usr/bin/vim ] || skip "no /usr/bin/vim"
  doctor
  [[ "$output" != *"and vim (also installed)"* ]]
}

@test "doctor: empty GITLAB_PRIVATE_TOKEN listed by name, value never printed" {
  install_everything linux-admin
  stub glab 'exit 0'
  mkdir -p "$HOME/.config/ignite"
  printf '%s\n' 'GITLAB_PRIVATE_TOKEN=' 'GITLAB_USERNAME=secretvalue' > "$HOME/.config/ignite/secrets.env"
  doctor
  [[ "$output" == *"Fill in"*"GITLAB_PRIVATE_TOKEN"* ]]
  [[ "$output" != *secretvalue* ]]
  [[ "$output" != *"GITLAB_USERNAME"* ]]
}

@test "doctor: prints ssh pubkey" {
  install_everything darwin-admin
  doctor
  [[ "$output" == *"ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITestKey"* ]]
  [[ "$output" == *"https://github.com/settings/ssh/new"* ]]
  [[ "$output" == *"ssh-keygen -p -f ~/.ssh/id_ed25519"* ]]
}

@test "doctor: gitlab machines point at the GitLab key page and glab login" {
  install_everything linux-admin
  stub glab 'exit 1'
  doctor
  [[ "$output" == *"https://gitlab.example.com/-/user_settings/ssh_keys"* ]]
  [[ "$output" == *"glab auth login --hostname gitlab.example.com"* ]]
}

@test "doctor: sign-in steps appear when not signed in" {
  install_everything darwin-admin
  stub gh 'exit 1'
  stub aws 'exit 0'
  doctor
  [[ "$output" == *"gh auth login"* ]]
  [[ "$output" == *"aws configure sso"* ]]
}

@test "doctor: only the matching doctor is managed per OS" {
  SRC="$REPO"
  run --separate-stderr managed darwin-admin
  grep -qx '.local/bin/ignite-doctor' <<< "$output"
  ! grep -q 'ignite-doctor.ps1' <<< "$output"
  run --separate-stderr managed windows-admin
  grep -qx '.local/bin/ignite-doctor.ps1' <<< "$output"
  ! grep -qx '.local/bin/ignite-doctor' <<< "$output"
}
