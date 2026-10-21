# shellcheck shell=bash
# Shared helpers for the bats suite. Load with: load helper

bats_require_minimum_version 1.5.0

REPO="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../.." && pwd)"
FIXTURES="$REPO/tests/fixtures"
SRC="$REPO"

# Run chezmoi against $SRC with a fixture machine config, isolated from the
# real home directory and the real chezmoi state. The fixture is a name under
# tests/fixtures/config, or a path to a config file.
_chezmoi() {
  local config="$FIXTURES/config/$1.toml"
  [ -f "$1" ] && config=$1
  shift
  chezmoi --source "$SRC" \
    --config "$config" \
    --persistent-state "$BATS_TEST_TMPDIR/state.boltdb" \
    --cache "$BATS_TEST_TMPDIR/chezmoi-cache" \
    --destination "$BATS_TEST_TMPDIR/home" \
    "$@"
}

# render_file <fixture> <path>: render a template file for a fixture machine.
render_file() {
  _chezmoi "$1" execute-template < "$2"
}

# render_tpl <fixture> '<template text>': render inline template text.
render_tpl() {
  printf '%s' "$2" | _chezmoi "$1" execute-template
}

# render_init <template> [execute-template flags...]: render a config file
# template the way `chezmoi init` would, with no existing config. Prompts are
# answered with --promptString/--promptBool/--promptChoice "<prompt>=<value>".
render_init() {
  local template=$1
  shift
  chezmoi --source "$SRC" \
    --config "$BATS_TEST_TMPDIR/no-config.toml" \
    --persistent-state "$BATS_TEST_TMPDIR/state.boltdb" \
    execute-template --init --no-tty "$@" < "$template"
}

# value_of <toml> <key>: value of the first "key = value" line, unquoted.
value_of() {
  printf '%s\n' "$1" | sed -n "s/^[[:space:]]*$2[[:space:]]*=[[:space:]]*//p" | head -n 1 | tr -d "'\""
}

# mode_of <path>: octal permissions, on GNU (Linux) and BSD (macOS) stat.
# GNU first: GNU `stat -f` means "filesystem", so it would succeed wrongly.
mode_of() {
  stat -c %a "$1" 2>/dev/null || stat -f %Lp "$1"
}

# managed <fixture>: list the targets chezmoi manages for a fixture machine.
# Runs on a copy of the source without .chezmoiexternal.toml.tmpl: chezmoi
# would otherwise download every external archive just to list targets.
managed() {
  local copy="$BATS_TEST_TMPDIR/managed-src"
  if [ ! -d "$copy" ]; then
    mkdir -p "$copy"
    cp "$SRC/.chezmoiroot" "$copy/"
    cp -R "$SRC/home" "$copy/home"
    rm -f "$copy/home/.chezmoiexternal.toml.tmpl"
  fi
  SRC="$copy" _chezmoi "$1" managed --path-style relative
}

# with_catalog <catalog.yaml> [choices.yaml]: point $SRC at a temporary source
# dir that uses the repo's templates with a fixture catalog.
with_catalog() {
  local catalog=$1
  local choices=${2:-$FIXTURES/catalogs/choices.yaml}
  local src="$BATS_TEST_TMPDIR/src"
  mkdir -p "$src/home/.chezmoidata"
  printf 'home\n' > "$src/.chezmoiroot"
  if [ -d "$REPO/home/.chezmoitemplates" ]; then
    ln -s "$REPO/home/.chezmoitemplates" "$src/home/.chezmoitemplates"
  fi
  cp "$catalog" "$src/home/.chezmoidata/packages.yaml"
  cp "$choices" "$src/home/.chezmoidata/choices.yaml"
  SRC="$src"
}
