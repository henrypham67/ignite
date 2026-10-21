#!/usr/bin/env bats
# VS Code, Neovim and Ghostty config.

load helper

TARGETS=(
  "home/Library/Application Support/Code/User/settings.json.tmpl"
  "home/AppData/Roaming/Code/User/settings.json.tmpl"
  "home/dot_config/Code/User/settings.json.tmpl"
)

@test "vscode: settings render as valid JSON for darwin, windows, linux" {
  fixtures=(darwin-admin windows-admin linux-admin)
  for i in 0 1 2; do
    render_file "${fixtures[$i]}" "$REPO/${TARGETS[$i]}" > "$BATS_TEST_TMPDIR/settings.json"
    jq -e 'type == "object"' "$BATS_TEST_TMPDIR/settings.json" > /dev/null || { echo "${TARGETS[$i]}"; false; }
  done
}

@test "vscode: no dropped keys present" {
  settings="$REPO/home/.chezmoitemplates/vscode-settings.json"
  for pattern in atlascode jenkins-jack jenkins.pipeline grammarly cSpell.userWords path-linux executable yaml.schemas '/Users/'; do
    ! grep -q "$pattern" "$settings" || { echo "found $pattern"; false; }
  done
}

@test "vscode: terminal font is Hack Nerd Font and vim keys are kept" {
  settings="$REPO/home/.chezmoitemplates/vscode-settings.json"
  [ "$(jq -r '."terminal.integrated.fontFamily"' "$settings")" = "Hack Nerd Font" ]
  [ "$(jq -r '."vim.leader"' "$settings")" = "<space>" ]
  [ "$(jq -r '."workbench.iconTheme"' "$settings")" = "material-icon-theme" ]
}

@test "managed: wsl has no VS Code settings or ghostty" {
  run --separate-stderr managed wsl-admin
  [ "$status" -eq 0 ]
  ! grep -q 'Code/User/settings.json' <<< "$output"
  ! grep -q '^.config/ghostty' <<< "$output"
  grep -qx '.config/nvim/init.lua' <<< "$output"
}

@test "managed: windows has AppData/Roaming/Code/User/settings.json" {
  run --separate-stderr managed windows-admin
  [ "$status" -eq 0 ]
  grep -qx 'AppData/Roaming/Code/User/settings.json' <<< "$output"
  ! grep -q '^Library' <<< "$output"
  ! grep -q '^.config/Code' <<< "$output"
  ! grep -q '^.config/ghostty' <<< "$output"
  grep -qx '.config/nvim/init.lua' <<< "$output"
}

@test "managed: darwin and linux each get their own VS Code path and ghostty" {
  run --separate-stderr managed darwin-admin
  grep -qx 'Library/Application Support/Code/User/settings.json' <<< "$output"
  ! grep -q '^.config/Code' <<< "$output"
  grep -qx '.config/ghostty/config' <<< "$output"
  run --separate-stderr managed linux-admin
  grep -qx '.config/Code/User/settings.json' <<< "$output"
  ! grep -q '^Library' <<< "$output"
  grep -qx '.config/ghostty/config' <<< "$output"
}

@test "managed: zed choice drops the VS Code settings" {
  run --separate-stderr managed darwin-custom
  ! grep -q 'Code/User/settings.json' <<< "$output"
}

@test "ghostty: exactly one background-blur-radius line" {
  config="$REPO/home/dot_config/ghostty/config"
  [ "$(grep -c '^background-blur-radius' "$config")" -eq 1 ]
  grep -qx 'theme = Catppuccin Mocha' "$config"
  grep -qx 'macos-option-as-alt = true' "$config"
}

@test "nvim: LazyVim config is present without the starter extras" {
  [ -f "$REPO/home/dot_config/nvim/init.lua" ]
  [ -f "$REPO/home/dot_config/nvim/lua/config/lazy.lua" ]
  [ ! -e "$REPO/home/dot_config/nvim/README.md" ]
  [ ! -e "$REPO/home/dot_config/nvim/lua/plugins/example.lua" ]
}

@test "denylist passes on home/" {
  cd "$REPO"
  run scripts/check-denylist.sh
  [ "$status" -eq 0 ]
}
