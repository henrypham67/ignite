#!/usr/bin/env bats
# Git config, SSH and the local secrets file.

load helper

SCRIPTS="$REPO/home/.chezmoiscripts"

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  GITCONFIG="$BATS_TEST_TMPDIR/gitconfig"
}

# gitconfig <fixture>: render .gitconfig to $GITCONFIG.
gitconfig() {
  render_file "$1" "$REPO/home/dot_gitconfig.tmpl" > "$GITCONFIG"
}

get() {
  git config -f "$GITCONFIG" --get-all "$@"
}

@test "gitconfig: work email and github helper on darwin-admin" {
  gitconfig darwin-admin
  [ "$(get user.name)" = "Henry Pham" ]
  [ "$(get user.email)" = "ci@example.com" ]
  [ "$(get core.editor)" = "nvim" ]
  [ "$(get core.hooksPath)" = "~/.git-hooks" ]
  [ "$(get core.excludesfile)" = "~/.gitignore_global" ]
  [ "$(get http.postBuffer)" = "157286400" ]
  [ "$(get credential.https://github.com.helper | tail -n 1)" = "!gh auth git-credential" ]
  [ "$(get credential.https://gist.github.com.helper | tail -n 1)" = "!gh auth git-credential" ]
  ! grep -q glab "$GITCONFIG"
}

@test "gitconfig: glab helper and gitlab url on linux-admin" {
  gitconfig linux-admin
  [ "$(get credential.https://gitlab.example.com.helper | tail -n 1)" = "!glab auth git-credential" ]
  ! grep -q 'gh auth' "$GITCONFIG"
}

@test "gitconfig: includeIf points at noreply identity" {
  gitconfig darwin-admin
  [ "$(get 'includeIf.gitdir:~/.local/share/chezmoi/.path')" = "~/.config/git/ignite-identity" ]
  [ "$(git config -f "$REPO/home/dot_config/git/ignite-identity" --get user.email)" = "43398131+henrypham67@users.noreply.github.com" ]
}

@test "gitconfig: the identity include wins inside the chezmoi source dir" {
  gitconfig darwin-admin
  mkdir -p "$HOME/.config/git" "$HOME/.local/share/chezmoi" "$HOME/work"
  cp "$REPO/home/dot_config/git/ignite-identity" "$HOME/.config/git/ignite-identity"
  cp "$GITCONFIG" "$HOME/.gitconfig"
  git -C "$HOME/.local/share/chezmoi" init -q
  git -C "$HOME/work" init -q
  [ "$(HOME="$HOME" GIT_CONFIG_NOSYSTEM=1 git -C "$HOME/.local/share/chezmoi" config user.email)" = "43398131+henrypham67@users.noreply.github.com" ]
  [ "$(HOME="$HOME" GIT_CONFIG_NOSYSTEM=1 git -C "$HOME/work" config user.email)" = "ci@example.com" ]
}

@test "gitconfig: sslCAInfo only with CA" {
  gitconfig linux-admin
  [ "$(get http.sslCAInfo)" = "/home/u/.config/ignite/ca-bundle.pem" ]
  gitconfig darwin-admin
  ! get http.sslCAInfo
  ! get http.sslBackend
}

@test "gitconfig: windows with a CA uses the Windows certificate store" {
  config="$BATS_TEST_TMPDIR/windows-ca.toml"
  sed -e 's|^ca_cert = ""|ca_cert = "C:/Users/u/.config/ignite/ca.pem"|' \
      -e 's|^ca_bundle = ""|ca_bundle = "C:/Users/u/.config/ignite/ca-bundle.pem"|' \
      "$FIXTURES/config/windows-admin.toml" > "$config"
  gitconfig "$config"
  [ "$(get http.sslBackend)" = "schannel" ]
  ! get http.sslCAInfo
}

@test "gitconfig: global hook and ignore files are in place" {
  [ -x "$REPO/home/dot_git-hooks/executable_pre-commit" ] || [ -f "$REPO/home/dot_git-hooks/executable_pre-commit" ]
  grep -q 'Refusing to commit Claude-local files' "$REPO/home/dot_git-hooks/executable_pre-commit"
  grep -qx '\*\*/.claude/settings.local.json' "$REPO/home/dot_gitignore_global"
}

@test "ssh: UseKeychain only on darwin" {
  run render_file darwin-admin "$REPO/home/private_dot_ssh/config.tmpl"
  grep -qx '  UseKeychain yes' <<< "$output"
  grep -qx '  IgnoreUnknown UseKeychain' <<< "$output"
  grep -qx '  AddKeysToAgent yes' <<< "$output"
  grep -qx '  IdentityFile ~/.ssh/id_ed25519' <<< "$output"
  run render_file linux-admin "$REPO/home/private_dot_ssh/config.tmpl"
  ! grep -q UseKeychain <<< "$output"
  grep -qx '  AddKeysToAgent yes' <<< "$output"
  run render_file windows-admin "$REPO/home/private_dot_ssh/config.tmpl"
  ! grep -q 'UseKeychain\|AddKeysToAgent' <<< "$output"
  grep -qx '  IdentityFile ~/.ssh/id_ed25519' <<< "$output"
}

@test "ssh-key: generates once, second run leaves key unchanged" {
  render_file darwin-admin "$SCRIPTS/run_after_70-ssh-key.sh.tmpl" > "$BATS_TEST_TMPDIR/ssh-key.sh"
  bash "$BATS_TEST_TMPDIR/ssh-key.sh"
  [ -f "$HOME/.ssh/id_ed25519" ]
  grep -q 'ci@example.com' "$HOME/.ssh/id_ed25519.pub"
  [ "$(mode_of "$HOME/.ssh")" = 700 ]
  before=$(shasum "$HOME/.ssh/id_ed25519" "$HOME/.ssh/id_ed25519.pub")
  bash "$BATS_TEST_TMPDIR/ssh-key.sh"
  [ "$(shasum "$HOME/.ssh/id_ed25519" "$HOME/.ssh/id_ed25519.pub")" = "$before" ]
}

secrets_script() {
  render_file "$1" "$SCRIPTS/run_after_80-secrets.sh.tmpl" > "$BATS_TEST_TMPDIR/secrets.sh"
  echo "$BATS_TEST_TMPDIR/secrets.sh"
}

@test "secrets: creates file with mode 600 and empty names" {
  bash "$(secrets_script linux-admin)"
  file="$HOME/.config/ignite/secrets.env"
  [ "$(mode_of "$file")" = 600 ]
  grep -qx 'GITLAB_PRIVATE_TOKEN=' "$file"
  grep -qx 'GITLAB_USERNAME=' "$file"
}

@test "secrets: existing values survive re-run byte-identical" {
  file="$HOME/.config/ignite/secrets.env"
  mkdir -p "$(dirname "$file")"
  printf '%s\n' "GITLAB_PRIVATE_TOKEN='a b\$c\"d'" '# my note' > "$file"
  cp "$file" "$BATS_TEST_TMPDIR/original"
  script=$(secrets_script linux-admin)
  bash "$script"
  bash "$script"
  printf 'GITLAB_USERNAME=\n' >> "$BATS_TEST_TMPDIR/original"
  cmp "$file" "$BATS_TEST_TMPDIR/original"
}

@test "secrets: a last line without a newline stays intact" {
  file="$HOME/.config/ignite/secrets.env"
  mkdir -p "$(dirname "$file")"
  printf '%s' "GITLAB_PRIVATE_TOKEN='a b\$c\"d'" > "$file"
  script=$(secrets_script linux-admin)
  bash "$script"
  bash "$script"
  [ "$(cat "$file")" = "$(printf '%s\n%s' "GITLAB_PRIVATE_TOKEN='a b\$c\"d'" 'GITLAB_USERNAME=')" ]
}

@test "secrets: a name set with export counts as present" {
  file="$HOME/.config/ignite/secrets.env"
  mkdir -p "$(dirname "$file")"
  printf '%s\n' 'export GITLAB_USERNAME=henry' > "$file"
  bash "$(secrets_script linux-admin)"
  [ "$(grep -c GITLAB_USERNAME "$file")" -eq 1 ]
  grep -qx 'GITLAB_PRIVATE_TOKEN=' "$file"
}

@test "secrets: github host writes no gitlab names" {
  bash "$(secrets_script darwin-admin)"
  file="$HOME/.config/ignite/secrets.env"
  [ -f "$file" ]
  ! grep -q GITLAB "$file"
}

@test "secrets/ssh: unix scripts are empty on windows" {
  for script in run_after_70-ssh-key.sh.tmpl run_after_80-secrets.sh.tmpl; do
    [ -z "$(render_file windows-admin "$SCRIPTS/$script" | tr -d '[:space:]')" ]
  done
}
