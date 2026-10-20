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
#   IGNITE_REPO, IGNITE_REF, IGNITE_LOCAL_SOURCE   where the dotfiles come from
#
# Runs under macOS /bin/bash 3.2: no associative arrays, mapfile or ${x,,}.
set -euo pipefail

IG_BIN="$HOME/.local/bin"
IG_CONFIG="$HOME/.config/ignite"

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

# ig_chezmoi_args <forwarded args...>: fill IG_CHEZMOI_ARGS. Uses $OS.
ig_chezmoi_args() {
  IG_CHEZMOI_ARGS=()
  local git_missing=0
  if [ "$OS" = darwin ]; then
    xcode-select -p >/dev/null 2>&1 || git_missing=1
  else
    command -v git >/dev/null 2>&1 || git_missing=1
  fi
  if [ "$git_missing" = 1 ]; then
    IG_CHEZMOI_ARGS+=(--use-builtin-git on)
  fi
  IG_CHEZMOI_ARGS+=(init --apply)
  if [ -n "${IGNITE_LOCAL_SOURCE:-}" ]; then
    IG_CHEZMOI_ARGS+=(--source "$IGNITE_LOCAL_SOURCE")
  else
    IG_CHEZMOI_ARGS+=("https://github.com/${IGNITE_REPO:-henrypham67/ignite}.git")
  fi
  if [ -n "${IGNITE_REF:-}" ]; then
    IG_CHEZMOI_ARGS+=(--branch "$IGNITE_REF")
  fi
  if [ $# -gt 0 ]; then
    IG_CHEZMOI_ARGS+=("$@")
  fi
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

  ig_chezmoi_args "$@"
  ig_log "chezmoi ${IG_CHEZMOI_ARGS[*]}"
  "$IG_BIN/chezmoi" "${IG_CHEZMOI_ARGS[@]}" || ig_die "chezmoi init --apply failed"

  if [ -x "$IG_BIN/ignite-doctor" ]; then
    "$IG_BIN/ignite-doctor"
    exit $?
  fi
  ig_log "done (ignite-doctor not found)"
}

[ "${IGNITE_SOURCE_ONLY:-}" = 1 ] || main "$@"
