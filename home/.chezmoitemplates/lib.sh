# ignite install helpers, rendered into each unix install script.
# bash 3.2 compatible. Nothing here may exit the calling script: a failed
# install is written to the report and the run carries on.
#
# Report: ${XDG_STATE_HOME:-~/.local/state}/ignite/report.tsv, one row per
# problem: source<TAB>status<TAB>item<TAB>detail, status failed|needs-it|skipped.

ig_report_path() {
  printf '%s/ignite/report.tsv\n' "${XDG_STATE_HOME:-$HOME/.local/state}"
}

# ig_field <text>: one report field: tabs and line breaks become spaces.
ig_field() {
  printf '%s' "$1" | tr '\t\r\n' '   '
}

# ig_reset <source>: drop the rows a script wrote last time, so a retry that
# succeeds leaves no stale failure behind.
ig_reset() {
  local report
  report=$(ig_report_path)
  [ -f "$report" ] || return 0
  awk -F '\t' -v source="$1" '$1 != source' "$report" > "$report.tmp.$$" &&
    mv "$report.tmp.$$" "$report"
}

# ig_report <source> <status> <item> <detail>
ig_report() {
  local report
  report=$(ig_report_path)
  mkdir -p "$(dirname "$report")"
  printf '%s\t%s\t%s\t%s\n' "$(ig_field "$1")" "$(ig_field "$2")" "$(ig_field "$3")" "$(ig_field "$4")" >> "$report"
}

# ig_skipped <item>: true when item is listed in IGNITE_SKIP (comma-separated).
ig_skipped() {
  case ",${IGNITE_SKIP:-}," in
    *",$1,"*) return 0 ;;
  esac
  return 1
}

# ig_try <source> <item> <cmd...>: run cmd, showing its output. On failure,
# record the last line it printed. Always returns 0.
ig_try() {
  local source=$1 item=$2
  shift 2
  if ig_skipped "$item"; then
    ig_report "$source" skipped "$item" "IGNITE_SKIP"
    return 0
  fi
  printf '==> ignite %s: %s\n' "$source" "$item"
  local log rc_file rc detail
  log=$(mktemp)
  rc_file=$(mktemp)
  ( set +e; "$@" 2>&1; echo $? > "$rc_file" ) | tee "$log"
  rc=$(cat "$rc_file")
  if [ "${rc:-1}" != 0 ]; then
    detail=$(grep -v '^[[:space:]]*$' "$log" | tail -n 1 || true)
    [ -n "$detail" ] || detail="exit status $rc"
    if grep -qi 'rate limit' "$log"; then
      detail="$detail; set GITHUB_TOKEN and retry"
    fi
    ig_report "$source" failed "$item" "$detail"
  fi
  rm -f "$log" "$rc_file"
  return 0
}

# ig_sudo <cmd...>: run as root; plain when already root (containers).
ig_sudo() {
  if [ "$(id -u)" = 0 ]; then
    "$@"
  else
    sudo "$@"
  fi
}

# ig_path_setup: make freshly installed tools visible to the rest of the script.
# IG_BREW_SEARCH overrides where to look for Homebrew; tests set it empty so a
# rendered script can never reach the real brew on the machine running them.
ig_path_setup() {
  local brew candidates
  read -r -a candidates <<< "${IG_BREW_SEARCH-/opt/homebrew/bin/brew /usr/local/bin/brew}"
  for brew in ${candidates[@]+"${candidates[@]}"}; do
    if [ -x "$brew" ]; then
      eval "$("$brew" shellenv)"
      break
    fi
  done
  PATH="$HOME/.local/bin:${XDG_DATA_HOME:-$HOME/.local/share}/mise/shims:${KREW_ROOT:-$HOME/.krew}/bin:$PATH"
  export PATH
}
