#!/bin/bash
# ignite bootstrap for macOS, Linux and WSL.
#
#   curl -fsSL https://raw.githubusercontent.com/henrypham67/ignite/main/bootstrap.sh | bash
#   curl -fsSL .../bootstrap.sh | bash -s -- <extra chezmoi init flags>
#
# Environment:
#   IGNITE_CA_CERT       company root CA (PEM) for TLS-inspecting proxies
#   IGNITE_NO_ADMIN=1    take the no-admin path even if sudo works
#   IGNITE_SKIP          comma-separated catalog entries to skip
#   IGNITE_NO_GUM=1      ask the setup questions as plain text (chezmoi's prompts)
#   IGNITE_REPO, IGNITE_REF, IGNITE_LOCAL_SOURCE   where the dotfiles come from
#
# Runs under macOS /bin/bash 3.2: no associative arrays, mapfile or ${x,,}.
set -euo pipefail

IG_BIN="$HOME/.local/bin"
IG_CONFIG="$HOME/.config/ignite"
IG_GUM_VERSION=2.0.2
# Where gum reads keys from. `curl | bash` leaves stdin on the script pipe.
IG_TTY=${IG_TTY:-/dev/tty}

ig_log() {
  printf '==> ignite: %s\n' "$*"
}

ig_die() {
  printf 'ignite: %s\n' "$*" >&2
  exit 1
}

# ---------------------------------------------------------------- report
# Same format as lib.sh (which is a chezmoi template and doesn't exist yet).

ig_report_file() {
  printf '%s/ignite/report.tsv\n' "${XDG_STATE_HOME:-$HOME/.local/state}"
}

ig_report_reset() {
  local report
  report=$(ig_report_file)
  [ -f "$report" ] || return 0
  awk -F '\t' '$1 != "bootstrap"' "$report" > "$report.tmp.$$" && mv "$report.tmp.$$" "$report"
}

# ig_report <status> <item> <detail>
ig_report() {
  local report
  report=$(ig_report_file)
  mkdir -p "$(dirname "$report")"
  printf 'bootstrap\t%s\t%s\t%s\n' "$1" "$2" "$3" >> "$report"
}

# ------------------------------------------------------------- detection

ig_detect_os() {
  case "$(uname -s)" in
    Darwin) echo darwin ;;
    Linux)
      if grep -qi microsoft "${IGNITE_PROC_VERSION_FILE:-/proc/version}" 2>/dev/null; then
        echo wsl
      else
        echo linux
      fi
      ;;
    *) ig_die "unsupported OS: $(uname -s)" ;;
  esac
}

# ig_detect_admin <os>: 1 if this user can get root, else 0.
ig_detect_admin() {
  if [ "${IGNITE_NO_ADMIN:-}" = 1 ]; then
    echo 0
    return
  fi
  if [ "$(id -u 2>/dev/null)" = 0 ] || sudo -n true 2>/dev/null; then
    echo 1
    return
  fi
  local groups
  groups=" $(id -Gn 2>/dev/null) "
  case "$1" in
    darwin) case "$groups" in *" admin "*) echo 1; return ;; esac ;;
    *) case "$groups" in *" sudo "* | *" wheel "*) echo 1; return ;; esac ;;
  esac
  echo 0
}

# ig_sudo <cmd...>: run as root; plain when already root (containers).
ig_sudo() {
  if [ "$(id -u 2>/dev/null)" = 0 ]; then
    "$@"
  else
    sudo "$@"
  fi
}

# --------------------------------------------------------------------- CA

ig_system_roots() {
  if [ -n "${IGNITE_SYSTEM_ROOTS:-}" ]; then
    echo "$IGNITE_SYSTEM_ROOTS"
  elif [ "$1" = darwin ]; then
    echo /etc/ssl/cert.pem
  else
    echo /etc/ssl/certs/ca-certificates.crt
  fi
}

# ig_setup_ca <os> <admin>: install IGNITE_CA_CERT before anything is downloaded.
ig_setup_ca() {
  local os=$1 admin=$2 path=${IGNITE_CA_CERT:-}
  [ -n "$path" ] || return 0
  case "$path" in
    \~/*) path="$HOME/${path#\~/}" ;;
    /*) ;;
    *) path="$PWD/$path" ;;
  esac
  [ -r "$path" ] || ig_die "IGNITE_CA_CERT not found: $path"

  mkdir -p "$IG_CONFIG"
  local ca="$IG_CONFIG/ca.pem" bundle="$IG_CONFIG/ca-bundle.pem" roots
  [ "$path" = "$ca" ] || cp "$path" "$ca"
  roots=$(ig_system_roots "$os")
  {
    if [ -r "$roots" ]; then
      cat "$roots"
      echo
    fi
    cat "$ca"
  } > "$bundle"

  if [ "$admin" = 1 ]; then
    if [ "$os" = darwin ]; then
      ig_sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain "$ca" ||
        ig_report failed company-ca "could not add the CA to the System keychain"
    else
      { ig_sudo cp "$ca" /usr/local/share/ca-certificates/ignite-company.crt &&
        ig_sudo update-ca-certificates; } ||
        ig_report failed company-ca "could not add the CA to the system trust store"
    fi
  fi

  export IGNITE_CA_CERT_INSTALLED="$ca" IGNITE_CA_BUNDLE="$bundle"
  export CURL_CA_BUNDLE="$bundle" SSL_CERT_FILE="$bundle"
  ig_log "company CA installed: $ca"
}

# ---------------------------------------------------------- prerequisites

ig_sudo_keepalive() {
  sudo -v || return 0
  ( while kill -0 "$$" 2>/dev/null; do sudo -n true 2>/dev/null; sleep 50; done ) &
}

# ig_install_prereqs <os> <admin>
ig_install_prereqs() {
  local os=$1 admin=$2
  if [ "$os" = darwin ]; then
    if ! xcode-select -p >/dev/null 2>&1; then
      if [ "$admin" = 1 ]; then
        ig_log "installing Xcode Command Line Tools (confirm the dialog)"
        xcode-select --install >/dev/null 2>&1 || true
        local waited=0
        until xcode-select -p >/dev/null 2>&1; do
          [ "$waited" -lt 1800 ] || ig_die "Xcode Command Line Tools did not finish installing"
          sleep 5
          waited=$((waited + 5))
        done
      else
        ig_report needs-it xcode-command-line-tools "needs admin; git falls back to chezmoi's built-in git"
      fi
    fi
    if [ "$admin" = 1 ] && [ ! -x /opt/homebrew/bin/brew ] && [ ! -x /usr/local/bin/brew ]; then
      ig_log "installing Homebrew"
      NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" ||
        ig_report failed homebrew "Homebrew installer failed"
    fi
  else
    if [ "$admin" = 1 ]; then
      ig_log "installing base packages with apt"
      ig_sudo apt-get update -y
      ig_sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y git curl zsh ca-certificates unzip fontconfig
      local zsh_path
      zsh_path=$(command -v zsh || true)
      if [ -n "$zsh_path" ] && [ "${SHELL:-}" != "$zsh_path" ]; then
        ig_sudo chsh -s "$zsh_path" "$(id -un)" || ig_report failed zsh "could not make zsh the login shell"
      fi
    elif ! command -v zsh >/dev/null 2>&1; then
      ig_report needs-it zsh "needs admin; bash gets the ignite profile instead"
    fi
  fi
}

ig_install_tools() {
  mkdir -p "$IG_BIN"
  if [ ! -x "$IG_BIN/chezmoi" ]; then
    ig_log "installing chezmoi"
    sh -c "$(curl -fsLS https://get.chezmoi.io)" -- -b "$IG_BIN"
  fi
  if [ ! -x "$IG_BIN/mise" ]; then
    ig_log "installing mise"
    curl -fsSL https://mise.run | MISE_INSTALL_PATH="$IG_BIN/mise" sh
  fi
  PATH="$IG_BIN:$PATH"
  export PATH
}

# ------------------------------------------------------------------ chezmoi

# ig_chezmoi_args <forwarded args...>: fill IG_CHEZMOI_GLOBAL (flags for every
# chezmoi call: init, managed, apply) and IG_CHEZMOI_INIT. Uses $OS. Apply
# runs separately so the first run can back files up before replacing them.
ig_chezmoi_args() {
  IG_CHEZMOI_GLOBAL=()
  IG_CHEZMOI_INIT=(init)
  local git_missing=0 arg
  if [ "$OS" = darwin ]; then
    xcode-select -p >/dev/null 2>&1 || git_missing=1
  else
    command -v git >/dev/null 2>&1 || git_missing=1
  fi
  if [ "$git_missing" = 1 ]; then
    IG_CHEZMOI_GLOBAL+=(--use-builtin-git on)
    # Recorded in the chezmoi config so later `chezmoi update` runs use it too.
    export IGNITE_BUILTIN_GIT=1
  fi
  if [ -n "${IGNITE_LOCAL_SOURCE:-}" ]; then
    IG_CHEZMOI_GLOBAL+=(--source "$IGNITE_LOCAL_SOURCE")
  else
    IG_CHEZMOI_INIT+=("https://github.com/${IGNITE_REPO:-henrypham67/ignite}.git")
  fi
  if [ -n "${IGNITE_REF:-}" ]; then
    IG_CHEZMOI_INIT+=(--branch "$IGNITE_REF")
  fi
  for arg in "$@"; do
    IG_CHEZMOI_INIT+=("$arg")
    if [ "$arg" = --no-tty ]; then
      IG_CHEZMOI_GLOBAL+=(--no-tty)
    fi
  done
}

# ig_backup_targets: read paths (relative to $HOME) on stdin and copy the ones
# that already exist into ~/.config/ignite/backup-<time>/, so nothing a
# company image shipped (.zshrc, .gitconfig, .ssh/config) is lost on the first
# apply. Prints the backup folder, or nothing when there was nothing to save.
ig_backup_targets() {
  local backup path saved=""
  backup="$IG_CONFIG/backup-$(date +%Y%m%d-%H%M%S)"
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    if [ -f "$HOME/$path" ] || [ -L "$HOME/$path" ]; then
      mkdir -p "$(dirname "$backup/$path")"
      cp -P "$HOME/$path" "$backup/$path"
      saved=1
    fi
  done
  if [ -n "$saved" ]; then
    echo "$backup"
  fi
}

# ---------------------------------------------------------------- questions
# The first run asks the setup questions with gum (arrow keys, checkboxes) and
# hands the answers to chezmoi init as --prompt* flags. The flag keys are the
# prompt texts in home/.chezmoi.toml.tmpl; tests/bats/bootstrap.bats renders
# that template with these flags to catch a key that no longer matches.

# ig_use_gum <first_run> <forwarded args...>: succeed when the questions should
# be asked with gum: the first run, a terminal to ask on, no --no-tty and no
# IGNITE_NO_GUM=1. Later runs have their answers already.
ig_use_gum() {
  local first_run=$1 arg
  shift
  [ -n "$first_run" ] || return 1
  [ "${IGNITE_NO_GUM:-}" != 1 ] || return 1
  for arg in "$@"; do
    [ "$arg" != --no-tty ] || return 1
  done
  { : < "$IG_TTY"; } 2>/dev/null
}

# ig_install_gum: install gum with mise and print its path. Prints nothing
# when that fails; chezmoi then asks the questions itself. Runs from $HOME, so
# a mise.toml where the bootstrap was started can't stop it with a trust prompt.
ig_install_gum() {
  "$IG_BIN/mise" -C "$HOME" install "gum@$IG_GUM_VERSION" >&2 || return 0
  "$IG_BIN/mise" -C "$HOME" which gum --tool "gum@$IG_GUM_VERSION" 2>/dev/null || true
}

# ig_pick <gum args...>: print what was picked. Ctrl-C (exit 130) or a gum
# error stops the setup; callers add `|| exit 1`, as this runs in $(...).
ig_pick() {
  "$IG_GUM" "$@" < "$IG_TTY" || ig_die "setup cancelled"
}

# ig_yes <gum confirm args...>: succeed on yes, fail on no; Ctrl-C stops the setup.
ig_yes() {
  local rc=0
  "$IG_GUM" confirm "$@" < "$IG_TTY" || rc=$?
  [ "$rc" -le 1 ] || ig_die "setup cancelled"
  return "$rc"
}

# ig_ok <value> <glob>: the value matches the glob and is safe in a chezmoi
# --prompt* flag, which splits on commas and quotes.
ig_ok() {
  case "$1" in *[,\"[:space:]]*) return 1 ;; esac
  # shellcheck disable=SC2254 # the glob is the point
  case "$1" in $2) return 0 ;; esac
  return 1
}

# ig_has <word> <lines>: "true" when word is one of the lines, else "false".
ig_has() {
  if printf '%s\n' "$2" | grep -qx "$1"; then echo true; else echo false; fi
}

# ig_group_label <group> <os>: the gum option for an optional tool group,
# "label|value". The tools named are examples from the catalog; tests check
# that each one is in the group and available on the OS.
ig_group_label() {
  case "$1:$2" in
    specialist:*) echo "Specialist tools: vault, istioctl, cilium-cli, k6, kops, java|specialist" ;;
    personal:darwin) echo "Personal apps: obsidian, telegram, anki, ffmpeg, yt-dlp|personal" ;;
    personal:*) echo "Personal apps: ffmpeg, yt-dlp, hugo, imagemagick|personal" ;;
  esac
}

# ig_choice_menu: one "job<TAB>default<TAB>options" line per tool choice this
# machine can make, printed by the config template itself (IGNITE_CHOICE_MENU=1)
# so the menus match what chezmoi init accepts. A remote repo is fetched first;
# that init writes its config to a throwaway file and gets the answers so far,
# because --promptDefaults can't answer the email (it has no default).
ig_choice_menu() {
  local tmp src
  if [ -z "${IGNITE_LOCAL_SOURCE:-}" ]; then
    tmp=$(mktemp -d)
    if ! "$IG_BIN/chezmoi" ${IG_CHEZMOI_GLOBAL[@]+"${IG_CHEZMOI_GLOBAL[@]}"} "${IG_CHEZMOI_INIT[@]}" \
      ${IG_ANSWERS[@]+"${IG_ANSWERS[@]}"} --promptDefaults --config-path "$tmp/chezmoi.toml" >&2; then
      rm -rf "$tmp"
      return 1
    fi
    rm -rf "$tmp"
  fi
  src=$("$IG_BIN/chezmoi" ${IG_CHEZMOI_GLOBAL[@]+"${IG_CHEZMOI_GLOBAL[@]}"} source-path) || return 1
  IGNITE_CHOICE_MENU=1 "$IG_BIN/chezmoi" ${IG_CHEZMOI_GLOBAL[@]+"${IG_CHEZMOI_GLOBAL[@]}"} execute-template \
    --init --promptBool "Change default tool choices=true" --file "$src/.chezmoi.toml.tmpl"
}

# ig_ask_choices: a radio list for each tool choice, the default preselected.
ig_ask_choices() {
  local menu job default options pick
  if ! menu=$(ig_choice_menu); then
    ig_log "could not list the tool choices; chezmoi asks them instead"
    return 0
  fi
  while IFS=$'\t' read -r job default options; do
    [ -n "$job" ] || continue
    # shellcheck disable=SC2086 # options is a space-separated list
    pick=$(ig_pick choose --header "Tool for: ${job//_/ }" --selected "$default" $options) || exit 1
    IG_ANSWERS+=(--promptChoice "Choice for $job=$pick")
  done <<EOF
$menu
EOF
}

# ig_ask <os>: ask the setup questions with gum and fill IG_ANSWERS with the
# chezmoi --prompt* flags that answer them.
ig_ask() {
  local os=$1 email="" host url="" clouds groups licensed=false customize=false
  IG_ANSWERS=()
  until ig_ok "$email" '?*@?*'; do
    email=$(ig_pick input --header "Work email for git" --placeholder "you@company.com") || exit 1
  done
  host=$(ig_pick choose --header "Company git host" --label-delimiter "|" \
    "github.com|github" "Self-hosted GitLab|gitlab") || exit 1
  IG_ANSWERS+=(--promptString "Work email for git=$email"
    --promptChoice "Company git host: github.com or a self-hosted GitLab=$host")
  if [ "$host" = gitlab ]; then
    until ig_ok "$url" 'https://?*'; do
      url=$(ig_pick input --header "Company GitLab URL (starts with https://)" \
        --placeholder "https://gitlab.example.com") || exit 1
    done
    IG_ANSWERS+=(--promptString "Company GitLab URL=$url")
  fi

  clouds=$(ig_pick choose --no-limit --header "Clouds you use: x to tick, enter when done (none is fine)" --label-delimiter "|" \
    "AWS|aws" "Azure|azure" "GCP|gcp") || exit 1
  IG_ANSWERS+=(--promptBool "Use AWS=$(ig_has aws "$clouds")"
    --promptBool "Use Azure=$(ig_has azure "$clouds")"
    --promptBool "Use GCP=$(ig_has gcp "$clouds")")
  if [ "$os" = darwin ]; then
    if ig_yes --default=false "Does the company license Docker Desktop?"; then licensed=true; fi
    IG_ANSWERS+=(--promptBool "Company licenses Docker Desktop=$licensed")
  fi

  groups=$(ig_pick choose --no-limit --header "Optional tool groups: x to tick, enter when done (none is fine)" --label-delimiter "|" \
    "$(ig_group_label specialist "$os")" "$(ig_group_label personal "$os")") || exit 1
  IG_ANSWERS+=(--promptBool "Install specialist tools=$(ig_has specialist "$groups")"
    --promptBool "Install personal apps=$(ig_has personal "$groups")")

  if ig_yes --default=false "Change the default tools (editor, terminal, prompt, ...)?"; then
    customize=true
    ig_ask_choices
  fi
  IG_ANSWERS+=(--promptBool "Change default tool choices=$customize")
}

# ig_ask_with_gum <first_run> <forwarded args...>: on a first run with a
# terminal, ask the questions with gum and add the answers to IG_CHEZMOI_INIT.
ig_ask_with_gum() {
  ig_use_gum "$@" || return 0
  IG_GUM=$(ig_install_gum)
  if [ -z "$IG_GUM" ]; then
    ig_log "gum is not available; chezmoi asks the questions instead"
    return 0
  fi
  ig_ask "$OS"
  IG_CHEZMOI_INIT+=("${IG_ANSWERS[@]}")
}

main() {
  OS=$(ig_detect_os)
  IGNITE_ADMIN=$(ig_detect_admin "$OS")
  export IGNITE_ADMIN
  if [ "$IGNITE_ADMIN" = 1 ]; then
    ig_log "$OS, with admin"
  else
    ig_log "$OS, without admin"
  fi

  ig_report_reset
  ig_setup_ca "$OS" "$IGNITE_ADMIN"
  if [ "$IGNITE_ADMIN" = 1 ]; then
    ig_sudo_keepalive
  fi
  ig_install_prereqs "$OS" "$IGNITE_ADMIN"
  ig_install_tools

  local first_run="" backup
  [ -f "${XDG_CONFIG_HOME:-$HOME/.config}/chezmoi/chezmoi.toml" ] || first_run=1
  ig_chezmoi_args "$@"
  ig_ask_with_gum "$first_run" "$@"
  ig_log "chezmoi ${IG_CHEZMOI_GLOBAL[*]+${IG_CHEZMOI_GLOBAL[*]}} ${IG_CHEZMOI_INIT[*]}"
  "$IG_BIN/chezmoi" ${IG_CHEZMOI_GLOBAL[@]+"${IG_CHEZMOI_GLOBAL[@]}"} "${IG_CHEZMOI_INIT[@]}" || ig_die "chezmoi init failed"
  if [ -n "$first_run" ]; then
    backup=$("$IG_BIN/chezmoi" ${IG_CHEZMOI_GLOBAL[@]+"${IG_CHEZMOI_GLOBAL[@]}"} managed --include=files,symlinks --path-style=relative | ig_backup_targets)
    if [ -n "$backup" ]; then
      ig_log "existing files ignite will replace were copied to $backup"
    fi
  fi
  "$IG_BIN/chezmoi" ${IG_CHEZMOI_GLOBAL[@]+"${IG_CHEZMOI_GLOBAL[@]}"} apply || ig_die "chezmoi apply failed"

  if [ -x "$IG_BIN/ignite-doctor" ]; then
    "$IG_BIN/ignite-doctor"
    exit $?
  fi
  ig_log "done (ignite-doctor not found)"
}

[ "${IGNITE_SOURCE_ONLY:-}" = 1 ] || main "$@"
