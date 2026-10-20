# shellcheck shell=bash
# Shared helpers for the bats suite. Load with: load helper

bats_require_minimum_version 1.5.0

REPO="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../.." && pwd)"
FIXTURES="$REPO/tests/fixtures"
SRC="$REPO"

# Run chezmoi against $SRC with a fixture machine config, isolated from the
# real home directory and the real chezmoi state.
_chezmoi() {
  local fixture=$1
  shift
  chezmoi --source "$SRC" \
    --config "$FIXTURES/config/$fixture.toml" \
    --persistent-state "$BATS_TEST_TMPDIR/state.boltdb" \
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

# managed <fixture>: list the targets chezmoi manages for a fixture machine.
managed() {
  _chezmoi "$1" managed --path-style relative
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
