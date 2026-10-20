#!/usr/bin/env bats
# zsh, bash and prompt config rendered per fixture machine.

load helper

zshrc() { render_file "$1" "$REPO/home/dot_zshrc.tmpl"; }
bashrc() { render_file "$1" "$REPO/home/dot_bashrc.tmpl"; }

# fixture_with_choice <fixture> <job> <option>: path to a fixture copy with one choice set.
fixture_with_choice() {
  local path="$BATS_TEST_TMPDIR/$1-$2-$3.toml"
  cp "$FIXTURES/config/$1.toml" "$path"
  printf '%s = "%s"\n' "$2" "$3" >> "$path"
  echo "$path"
}

@test "zshrc: default plugin list and order" {
  run zshrc darwin-admin
  [ "$status" -eq 0 ]
  grep -qx 'plugins=(direnv docker docker-compose history git kubectl helm terraform encode64 jsontools aws ansible you-should-use zsh-autosuggestions zsh-bat zsh-syntax-highlighting)' <<< "$output"
}

@test "zshrc: cloud and ansible plugins follow the machine" {
  run zshrc linux-admin
  plugins=$(grep '^plugins=' <<< "$output")
  [[ "$plugins" != *" aws "* ]]
  [[ "$plugins" == *" ansible "* ]]
}

@test "zshrc: syntax-highlighting last" {
  fixture=$(fixture_with_choice darwin-admin zsh_completion_menu zsh-autocomplete)
  run zshrc "$fixture"
  [ "$status" -eq 0 ]
  [[ "$(grep '^plugins=' <<< "$output")" == *" zsh-syntax-highlighting)" ]]
  # zsh-autocomplete is sourced before oh-my-zsh runs compinit, not loaded as a plugin.
  [[ "$(grep '^plugins=' <<< "$output")" != *zsh-autocomplete* ]]
  autocomplete=$(grep -n 'zsh-autocomplete.plugin.zsh' <<< "$output" | cut -d: -f1)
  omz=$(grep -n 'source "$ZSH/oh-my-zsh.sh"' <<< "$output" | cut -d: -f1)
  [ "$autocomplete" -lt "$omz" ]
  ! grep -q "menu select" <<< "$output"
}

@test "zshrc: zsh-completions goes on fpath before oh-my-zsh" {
  run zshrc darwin-admin
  fpath=$(grep -n 'zsh-completions/src' <<< "$output" | cut -d: -f1)
  omz=$(grep -n 'source "$ZSH/oh-my-zsh.sh"' <<< "$output" | cut -d: -f1)
  [ -n "$fpath" ] && [ "$fpath" -lt "$omz" ]
  grep -q "zstyle ':completion:\*' menu select" <<< "$output"
}

@test "zshrc: starship by default, p10k with darwin-custom" {
  run zshrc darwin-admin
  grep -qx 'ZSH_THEME=""' <<< "$output"
  [[ "$(grep -v '^[[:space:]]*$' <<< "$output" | tail -n 1)" == *'eval "$(starship init zsh)"'* ]]
  ! grep -q p10k <<< "$output"

  run zshrc darwin-custom
  grep -qx 'ZSH_THEME="powerlevel10k/powerlevel10k"' <<< "$output"
  ! grep -q 'starship init' <<< "$output"
  [[ "$(grep -v '^[[:space:]]*\(#.*\)\{0,1\}$' <<< "$output" | head -n 1)" == *p10k-instant-prompt* ]]
}

@test "zshrc: tools are on PATH before oh-my-zsh loads its plugins" {
  run zshrc darwin-admin
  path_line=$(grep -n 'mise/shims' <<< "$output" | head -n 1 | cut -d: -f1)
  omz=$(grep -n 'source "$ZSH/oh-my-zsh.sh"' <<< "$output" | cut -d: -f1)
  [ "$path_line" -lt "$omz" ]
  grep -q 'mise activate zsh' <<< "$output"
}

@test "zshrc: no lazy completion for kubectl, has one for flux" {
  run zshrc darwin-admin
  grep -q "_lazy_completion flux 'flux completion zsh'" <<< "$output"
  grep -q "_lazy_completion helm 'helm completion zsh'" <<< "$output"
  ! grep -q '_lazy_completion kubectl' <<< "$output"
  ! grep -q '_lazy_completion cilium' <<< "$output"
  run zshrc darwin-custom
  grep -q "_lazy_completion cilium 'cilium completion zsh'" <<< "$output"
  grep -q 'complete -C vault vault' <<< "$output"
}

@test "zshrc: gh and glab completions ask for the shell with -s" {
  run zshrc linux-admin
  grep -q "_lazy_completion gh 'gh completion -s zsh'" <<< "$output"
  grep -q "_lazy_completion glab 'glab completion -s zsh'" <<< "$output"
}

@test "zshrc: oh-my-zsh self-update is off (chezmoi updates it)" {
  run zshrc darwin-admin
  line=$(grep -n "zstyle ':omz:update' mode disabled" <<< "$output" | cut -d: -f1)
  omz=$(grep -n 'source "$ZSH/oh-my-zsh.sh"' <<< "$output" | cut -d: -f1)
  [ -n "$line" ] && [ "$line" -lt "$omz" ]
}

@test "zshrc: GITLAB_URL only on linux-admin" {
  run zshrc linux-admin
  grep -qx "export GITLAB_URL='https://gitlab.example.com'" <<< "$output"
  run zshrc darwin-admin
  ! grep -q GITLAB_URL <<< "$output"
}

@test "zshrc: CA exports only when ca_cert set" {
  run zshrc linux-admin
  for var in SSL_CERT_FILE REQUESTS_CA_BUNDLE CURL_CA_BUNDLE AWS_CA_BUNDLE; do
    grep -qx "export $var='/home/u/.config/ignite/ca-bundle.pem'" <<< "$output"
  done
  grep -qx "export NODE_EXTRA_CA_CERTS='/home/u/.config/ignite/ca.pem'" <<< "$output"
  run zshrc darwin-admin
  ! grep -q 'CA_BUNDLE\|SSL_CERT_FILE\|NODE_EXTRA_CA_CERTS' <<< "$output"
}

@test "zshrc: zz uses code by default, zed with darwin-custom" {
  run zshrc darwin-admin
  grep -qx 'zz() { z "$@" && code . && exit }' <<< "$output"
  run zshrc darwin-custom
  grep -qx 'zz() { z "$@" && zed . && exit }' <<< "$output"
}

@test "zshrc: EDITOR follows the terminal editor choice" {
  run zshrc darwin-admin
  grep -qx "export EDITOR='nvim'" <<< "$output"
  fixture=$(fixture_with_choice darwin-admin terminal_editor vim)
  run zshrc "$fixture"
  grep -qx "export EDITOR='vim'" <<< "$output"
}

@test "zshrc: history settings" {
  run zshrc darwin-admin
  grep -qx 'HISTSIZE=50000' <<< "$output"
  grep -qx 'SAVEHIST=50000' <<< "$output"
  for opt in SHARE_HISTORY HIST_IGNORE_ALL_DUPS HIST_SAVE_NO_DUPS HIST_FIND_NO_DUPS HIST_EXPIRE_DUPS_FIRST HIST_REDUCE_BLANKS INC_APPEND_HISTORY AUTO_CD AUTO_PUSHD PUSHD_IGNORE_DUPS INTERACTIVE_COMMENTS; do
    grep -qx "setopt $opt" <<< "$output"
  done
}

@test "zshrc: secrets file is loaded" {
  run zshrc darwin-admin
  grep -qF '[ -f ~/.config/ignite/secrets.env ] && { set -a; . ~/.config/ignite/secrets.env; set +a; }' <<< "$output"
}

@test "zshrc: aliases oh-my-zsh doesn't define are added" {
  run zshrc darwin-admin
  grep -qx "alias kctx='kubectl ctx'" <<< "$output"
  grep -qx "alias kns='kubectl ns'" <<< "$output"
  # k comes from the oh-my-zsh kubectl plugin already.
  ! grep -q "^alias k=" <<< "$output"
}

@test "zshrc: nvm is loaded only when chosen" {
  run zshrc darwin-admin
  ! grep -q 'nvm.sh' <<< "$output"
  fixture=$(fixture_with_choice darwin-admin node_versions nvm)
  run zshrc "$fixture"
  grep -q 'NVM_DIR/nvm.sh' <<< "$output"
}

@test "zshrc: passes zsh -n" {
  command -v zsh > /dev/null || skip "zsh not installed"
  for fixture in darwin-admin darwin-noadmin darwin-custom linux-admin wsl-admin; do
    zshrc "$fixture" > "$BATS_TEST_TMPDIR/zshrc"
    zsh -n "$BATS_TEST_TMPDIR/zshrc" || { echo "$fixture"; false; }
  done
}

@test "zprofile: brew shellenv and mise shims" {
  run render_file darwin-admin "$REPO/home/dot_zprofile.tmpl"
  grep -q '/opt/homebrew/bin/brew' <<< "$output"
  grep -q 'shellenv' <<< "$output"
  grep -q 'mise/shims' <<< "$output"
  command -v zsh > /dev/null || skip "zsh not installed"
  render_file darwin-admin "$REPO/home/dot_zprofile.tmpl" > "$BATS_TEST_TMPDIR/zprofile"
  zsh -n "$BATS_TEST_TMPDIR/zprofile"
}

@test "bashrc: passes bash -n and has the shared setup" {
  for fixture in darwin-admin linux-admin wsl-admin; do
    bashrc "$fixture" > "$BATS_TEST_TMPDIR/bashrc"
    bash -n "$BATS_TEST_TMPDIR/bashrc" || { echo "$fixture"; false; }
  done
  run bashrc linux-admin
  grep -q 'starship init bash' <<< "$output"
  grep -q 'mise activate bash' <<< "$output"
  grep -q 'zoxide init bash' <<< "$output"
  grep -q 'direnv hook bash' <<< "$output"
  grep -qx "alias k='kubectl'" <<< "$output"
  grep -qx "export GITLAB_URL='https://gitlab.example.com'" <<< "$output"
  grep -q 'secrets.env' <<< "$output"
}

@test "bashrc: sources cleanly in a bash with none of the tools" {
  bashrc linux-admin > "$BATS_TEST_TMPDIR/bashrc"
  run env -i HOME="$BATS_TEST_TMPDIR" PATH=/usr/bin:/bin bash --norc -i -c ". '$BATS_TEST_TMPDIR/bashrc'; echo loaded" 2>&1
  [[ "$output" == *loaded ]]
  ! grep -qi 'command not found' <<< "$output"
}

@test "externals: oh-my-zsh and five plugins, no autocomplete by default" {
  run render_file darwin-admin "$REPO/home/.chezmoiexternal.toml.tmpl"
  [ "$status" -eq 0 ]
  for dest in .oh-my-zsh .oh-my-zsh/custom/plugins/zsh-autosuggestions .oh-my-zsh/custom/plugins/zsh-syntax-highlighting \
              .oh-my-zsh/custom/plugins/zsh-bat .oh-my-zsh/custom/plugins/you-should-use .oh-my-zsh/custom/plugins/zsh-completions; do
    grep -qx "\[\"$dest\"\]" <<< "$output" || { echo "missing $dest"; false; }
  done
  [ "$(grep -c 'type = "archive"' <<< "$output")" -eq 6 ]
  [ "$(grep -c 'stripComponents = 1' <<< "$output")" -eq 6 ]
  [ "$(grep -c 'refreshPeriod = "168h"' <<< "$output")" -eq 6 ]
  ! grep -q autocomplete <<< "$output"
  ! grep -q powerlevel10k <<< "$output"
  run render_file windows-admin "$REPO/home/.chezmoiexternal.toml.tmpl"
  [ -z "$(tr -d '[:space:]' <<< "$output")" ]
}

@test "starship.toml: kubernetes on and a 2s command timer" {
  run chezmoi --source "$REPO" --config "$FIXTURES/config/darwin-admin.toml" \
    --persistent-state "$BATS_TEST_TMPDIR/state.boltdb" \
    execute-template '{{ $c := include "dot_config/starship.toml" | fromToml }}{{ $c.kubernetes.disabled }} {{ $c.cmd_duration.min_time }}'
  [ "$output" = "false 2000" ]
}

@test "managed: windows-admin manages no .zshrc" {
  run --separate-stderr managed windows-admin
  [ "$status" -eq 0 ]
  ! grep -qx '.zshrc' <<< "$output"
  ! grep -qx '.bashrc' <<< "$output"
  run --separate-stderr managed darwin-admin
  [ "$status" -eq 0 ]
  grep -qx '.zshrc' <<< "$output"
  grep -qx '.zprofile' <<< "$output"
  grep -qx '.config/starship.toml' <<< "$output"
}
