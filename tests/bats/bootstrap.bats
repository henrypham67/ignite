#!/usr/bin/env bats
# bootstrap.sh: functions tested by sourcing with IGNITE_SOURCE_ONLY=1, and
# main tested end to end against stub commands on PATH.

load helper

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  export XDG_STATE_HOME="$HOME/.local/state"
  STUBS="$BATS_TEST_TMPDIR/stubs"
  CALLS="$BATS_TEST_TMPDIR/calls.log"
  mkdir -p "$STUBS"
  : > "$CALLS"
  unset IGNITE_NO_ADMIN IGNITE_CA_CERT IGNITE_LOCAL_SOURCE IGNITE_REPO IGNITE_REF IGNITE_PROC_VERSION_FILE IGNITE_SYSTEM_ROOTS IGNITE_NO_GUM
  # gum questions go to the stub gum, and /dev/null stands in for the terminal.
  export IG_GUM="$STUBS/gum" IG_TTY=/dev/null
  # Defaults: a Mac, sudo needs a password, user is not in any admin group.
  stub uname 'echo Darwin'
  stub sudo 'exit 1'
  stub id 'echo staff everyone'
  stub xcode-select 'echo /Library/Developer/CommandLineTools'
  stub curl 'exit 0'
}

# stub <name> <body>: a fake command that logs its call, then runs body.
stub() {
  printf '#!/bin/bash\necho "%s $*" >> "%s"\n%s\n' "$1" "$CALLS" "$2" > "$STUBS/$1"
  chmod +x "$STUBS/$1"
}

# gum_answers <rc|output>...: the stub gum answers each call with the next
# entry: exit code, then what it prints (\n separates multi-select picks).
gum_answers() {
  printf '%s\n' "$@" > "$BATS_TEST_TMPDIR/gum-answers"
  stub gum '
answers="'"$BATS_TEST_TMPDIR"'/gum-answers"
line=$(head -n 1 "$answers")
[ -n "$line" ] || { echo "gum stub: no answer queued for: $*" >&2; exit 99; }
tail -n +2 "$answers" > "$answers.next" && mv "$answers.next" "$answers"
[ -z "${line#*|}" ] || printf "%b\n" "${line#*|}"
exit "${line%%|*}"'
}

# stub_mise <gum path>: a mise in ~/.local/bin that "installs" gum at that path.
stub_mise() {
  mkdir -p "$HOME/.local/bin"
  printf '#!/bin/bash\necho "mise $*" >> "%s"\ncase " $* " in *" which "*) echo "%s" ;; esac\n' "$CALLS" "$1" > "$HOME/.local/bin/mise"
  chmod +x "$HOME/.local/bin/mise"
}

# ASK: ig_ask with a one-job tool menu instead of the config template's.
ASK='ig_choice_menu() { printf "editor\tvscode\tvscode zed\n"; }; ig_ask'
PRINT_ANSWERS='printf "%s\n" "${IG_ANSWERS[@]}"'

# in_bootstrap [bash] <code>: source bootstrap.sh with stubs first on PATH, then run code.
in_bootstrap() {
  local shell=bash
  if [ $# -eq 2 ]; then shell=$1; shift; fi
  PATH="$STUBS:$PATH" IGNITE_SOURCE_ONLY=1 "$shell" -c ". '$REPO/bootstrap.sh'; $1"
}

@test "bootstrap.sh: detects darwin, linux, wsl" {
  run in_bootstrap 'ig_detect_os'
  [ "$output" = darwin ]

  stub uname 'echo Linux'
  printf 'Linux version 6.8.0-45-generic (buildd@lcy02)\n' > "$BATS_TEST_TMPDIR/version"
  IGNITE_PROC_VERSION_FILE="$BATS_TEST_TMPDIR/version" run in_bootstrap 'ig_detect_os'
  [ "$output" = linux ]

  printf 'Linux version 5.15.153.1-microsoft-standard-WSL2 (root@1c602f52c2e4)\n' > "$BATS_TEST_TMPDIR/version"
  IGNITE_PROC_VERSION_FILE="$BATS_TEST_TMPDIR/version" run in_bootstrap 'ig_detect_os'
  [ "$output" = wsl ]
}

@test "bootstrap.sh: no admin when sudo needs a password and no admin group" {
  run in_bootstrap 'ig_detect_admin darwin'
  [ "$output" = 0 ]
}

@test "bootstrap.sh: passwordless sudo counts as admin" {
  stub sudo 'exit 0'
  run in_bootstrap 'ig_detect_admin linux'
  [ "$output" = 1 ]
}

@test "bootstrap.sh: IGNITE_NO_ADMIN=1 forces 0 even if sudo works" {
  stub sudo 'exit 0'
  stub id 'echo staff admin'
  IGNITE_NO_ADMIN=1 run in_bootstrap 'ig_detect_admin darwin'
  [ "$output" = 0 ]
}

@test "bootstrap.sh: admin group without passwordless sudo counts as admin" {
  stub id 'echo staff everyone admin'
  run in_bootstrap 'ig_detect_admin darwin'
  [ "$output" = 1 ]

  stub id 'echo henry adm sudo'
  run in_bootstrap 'ig_detect_admin linux'
  [ "$output" = 1 ]

  # "admin" means nothing on Linux, "sudo" means nothing on macOS.
  stub id 'echo henry admin'
  run in_bootstrap 'ig_detect_admin wsl'
  [ "$output" = 0 ]
  stub id 'echo staff sudo'
  run in_bootstrap 'ig_detect_admin darwin'
  [ "$output" = 0 ]
}

@test "bootstrap.sh: CA path resolution" {
  printf 'COMPANY CA\n' > "$HOME/company.pem"
  printf 'SYSTEM ROOTS\n' > "$BATS_TEST_TMPDIR/roots.pem"
  export IGNITE_SYSTEM_ROOTS="$BATS_TEST_TMPDIR/roots.pem"

  IGNITE_CA_CERT='~/company.pem' run in_bootstrap 'ig_setup_ca darwin 0; echo "$IGNITE_CA_CERT_INSTALLED"'
  [ "$status" -eq 0 ]
  [ "${lines[${#lines[@]}-1]}" = "$HOME/.config/ignite/ca.pem" ]
  [ "$(cat "$HOME/.config/ignite/ca.pem")" = "COMPANY CA" ]

  rm -rf "$HOME/.config/ignite"
  mkdir -p "$BATS_TEST_TMPDIR/cwd"
  cp "$HOME/company.pem" "$BATS_TEST_TMPDIR/cwd/rel.pem"
  run bash -c "cd '$BATS_TEST_TMPDIR/cwd' && PATH='$STUBS:$PATH' IGNITE_SOURCE_ONLY=1 IGNITE_CA_CERT=rel.pem bash -c \". '$REPO/bootstrap.sh'; ig_setup_ca darwin 0; echo \\\$IGNITE_CA_CERT_INSTALLED\""
  [ "$status" -eq 0 ]
  [ "${lines[${#lines[@]}-1]}" = "$HOME/.config/ignite/ca.pem" ]
  [ "$(cat "$HOME/.config/ignite/ca.pem")" = "COMPANY CA" ]
}

@test "bootstrap.sh: no IGNITE_CA_CERT means no CA handling" {
  run in_bootstrap 'ig_setup_ca darwin 0; echo "[${IGNITE_CA_CERT_INSTALLED:-}]"'
  [ "$status" -eq 0 ]
  [ "$output" = "[]" ]
  [ ! -e "$HOME/.config/ignite/ca.pem" ]
}

@test "bootstrap.sh: missing CA fails before any download" {
  run env PATH="$STUBS:$PATH" IGNITE_CA_CERT="$HOME/nope.pem" bash "$REPO/bootstrap.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"IGNITE_CA_CERT not found: $HOME/nope.pem"* ]]
  ! grep -q '^curl ' "$CALLS"
}

@test "bootstrap.sh: bundle contains system roots then company CA" {
  printf 'COMPANY CA\n' > "$HOME/company.pem"
  printf 'SYSTEM ROOTS\n' > "$BATS_TEST_TMPDIR/roots.pem"
  IGNITE_SYSTEM_ROOTS="$BATS_TEST_TMPDIR/roots.pem" IGNITE_CA_CERT="$HOME/company.pem" \
    run in_bootstrap 'ig_setup_ca darwin 0; echo "$IGNITE_CA_BUNDLE|$CURL_CA_BUNDLE|$SSL_CERT_FILE"'
  [ "$status" -eq 0 ]
  bundle="$HOME/.config/ignite/ca-bundle.pem"
  [ "${lines[${#lines[@]}-1]}" = "$bundle|$bundle|$bundle" ]
  [ "$(grep -v '^$' "$bundle" | tr '\n' '|')" = "SYSTEM ROOTS|COMPANY CA|" ]
}

@test "bootstrap.sh: admin trusts the CA system-wide" {
  printf 'COMPANY CA\n' > "$HOME/company.pem"
  printf 'SYSTEM ROOTS\n' > "$BATS_TEST_TMPDIR/roots.pem"
  stub sudo 'exit 0'
  IGNITE_SYSTEM_ROOTS="$BATS_TEST_TMPDIR/roots.pem" IGNITE_CA_CERT="$HOME/company.pem" \
    run in_bootstrap 'ig_setup_ca darwin 1'
  [ "$status" -eq 0 ]
  grep -q '^sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain ' "$CALLS"
}

# show_args: global flags (used for init, managed and apply) and init args,
# each joined with "|" so arguments with spaces stay visible.
SHOW_ARGS='printf "global:"; for a in ${IG_CHEZMOI_GLOBAL[@]+"${IG_CHEZMOI_GLOBAL[@]}"}; do printf "%s|" "$a"; done; printf "\ninit:"; for a in "${IG_CHEZMOI_INIT[@]}"; do printf "%s|" "$a"; done; echo'

@test "bootstrap.sh: chezmoi args default to https://github.com/henrypham67/ignite.git" {
  run in_bootstrap "OS=darwin; ig_chezmoi_args; $SHOW_ARGS"
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf 'global:\ninit:init|https://github.com/henrypham67/ignite.git|')" ]
}

@test "bootstrap.sh: IGNITE_REPO and IGNITE_REF pick another repo and branch" {
  IGNITE_REPO=someone/fork IGNITE_REF=dev run in_bootstrap "OS=darwin; ig_chezmoi_args; $SHOW_ARGS"
  [ "${lines[1]}" = "init:init|https://github.com/someone/fork.git|--branch|dev|" ]
}

@test "bootstrap.sh: use --source when IGNITE_LOCAL_SOURCE set" {
  IGNITE_LOCAL_SOURCE=/src run in_bootstrap "OS=darwin; ig_chezmoi_args; $SHOW_ARGS"
  [ "$output" = "$(printf 'global:--source|/src|\ninit:init|')" ]
}

@test "bootstrap.sh: forward extra args in order" {
  run in_bootstrap "OS=darwin; ig_chezmoi_args --no-tty --promptString 'Work email for git=ci@example.com'; $SHOW_ARGS"
  [ "${lines[1]}" = "init:init|https://github.com/henrypham67/ignite.git|--no-tty|--promptString|Work email for git=ci@example.com|" ]
}

@test "bootstrap.sh: builtin git only when CLT missing on darwin" {
  stub xcode-select 'exit 2'
  run in_bootstrap "OS=darwin; ig_chezmoi_args; $SHOW_ARGS; echo \"builtin=\$IGNITE_BUILTIN_GIT\""
  [ "${lines[0]}" = "global:--use-builtin-git|on|" ]
  [ "${lines[2]}" = "builtin=1" ]

  stub xcode-select 'echo /Library/Developer/CommandLineTools'
  run in_bootstrap "OS=darwin; ig_chezmoi_args; $SHOW_ARGS"
  [ "${lines[0]}" = "global:" ]
}

@test "bootstrap.sh: builtin git on linux when git is missing" {
  run in_bootstrap "OS=linux; PATH='$STUBS:/usr/bin/false-dir'; ig_chezmoi_args; $SHOW_ARGS"
  [ "${lines[0]}" = "global:--use-builtin-git|on|" ]
}

@test "bootstrap.sh: chezmoi args never contain --force" {
  run in_bootstrap "OS=darwin; ig_chezmoi_args --no-tty; $SHOW_ARGS"
  [ "$status" -eq 0 ]
  [[ "$output" == *"init:init|"* ]]
  [[ "$output" != *--force* ]]
}

@test "bootstrap.sh: first-run backup copies existing targets, keeping their paths" {
  mkdir -p "$HOME/.ssh" "$HOME/.config/git"
  printf 'company zshrc\n' > "$HOME/.zshrc"
  printf 'Host corp\n' > "$HOME/.ssh/config"
  run in_bootstrap "printf '%s\n' .zshrc .ssh/config .gitconfig .config/git | ig_backup_targets"
  [ "$status" -eq 0 ]
  backup="${lines[${#lines[@]}-1]}"
  [[ "$backup" == "$HOME/.config/ignite/backup-"* ]]
  [ "$(cat "$backup/.zshrc")" = "company zshrc" ]
  [ "$(cat "$backup/.ssh/config")" = "Host corp" ]
  [ ! -e "$backup/.gitconfig" ]
  [ ! -e "$backup/.config/git" ]
}

@test "bootstrap.sh: first-run backup with nothing to save prints nothing" {
  run in_bootstrap "printf '%s\n' .zshrc .gitconfig | ig_backup_targets"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ ! -d "$HOME/.config/ignite" ]
}

@test "bootstrap.sh: no admin on darwin records missing CLT as needs-it" {
  stub xcode-select 'exit 2'
  run in_bootstrap 'ig_report_reset; ig_install_prereqs darwin 0; cat "$XDG_STATE_HOME/ignite/report.tsv"'
  [ "$status" -eq 0 ]
  [[ "$output" == *"bootstrap"$'\t'"needs-it"$'\t'"xcode-command-line-tools"$'\t'* ]]
  ! grep -q '^sudo ' "$CALLS"
}

@test "bootstrap.sh: gum answers reach the config template under its prompt keys" {
  gum_answers '0|dev@example.com' '0|gitlab' '0|https://gitlab.example.com' '0|aws\ngcp' '0|' \
    '0|specialist\npersonal' '0|' '0|zed'
  run --separate-stderr in_bootstrap "$ASK darwin && $PRINT_ANSWERS"
  [ "$status" -eq 0 ]
  flags=()
  while IFS= read -r line; do flags+=("$line"); done <<< "$output"

  run --separate-stderr render_init "$REPO/home/.chezmoi.toml.tmpl" "${flags[@]}"
  [ "$status" -eq 0 ]
  [ "$(value_of "$output" email)" = dev@example.com ]
  [ "$(value_of "$output" git_host)" = gitlab ]
  [ "$(value_of "$output" gitlab_url)" = https://gitlab.example.com ]
  [ "$(value_of "$output" cloud_aws)" = true ]
  [ "$(value_of "$output" cloud_azure)" = false ]
  [ "$(value_of "$output" cloud_gcp)" = true ]
  [ "$(value_of "$output" group_specialist)" = true ]
  [ "$(value_of "$output" group_personal)" = true ]
  [ "$(value_of "$output" customize_choices)" = true ]
  [ "$(value_of "$output" editor)" = zed ]
  # The template only asks about Docker Desktop on macOS and Windows hosts.
  if [ "$(uname -s)" = Darwin ]; then
    [ "$(value_of "$output" docker_licensed)" = true ]
  fi
}

@test "bootstrap.sh: asks again for an email without @ and a GitLab URL without https://" {
  gum_answers '0|' '0|dev@example.com' '0|gitlab' '0|gitlab.example.com' '0|https://gitlab.example.com' \
    '0|' '0|' '1|'
  run --separate-stderr in_bootstrap "ig_ask linux && $PRINT_ANSWERS"
  [ "$status" -eq 0 ]
  [ "$(grep -c '^gum input' "$CALLS")" -eq 4 ]
  printf '%s\n' "$output" | grep -qx 'Work email for git=dev@example.com'
  printf '%s\n' "$output" | grep -qx 'Company GitLab URL=https://gitlab.example.com'
  printf '%s\n' "$output" | grep -qx 'Change default tool choices=false'
  # No Docker Desktop question on Linux: the template doesn't ask it there.
  ! printf '%s\n' "$output" | grep -q 'Docker Desktop'
}

@test "bootstrap.sh: Ctrl-C in a gum question stops the setup" {
  gum_answers '130|'
  run --separate-stderr in_bootstrap 'ig_ask linux; echo still running'
  [ "$status" -ne 0 ]
  [[ "$stderr" == *"setup cancelled"* ]]
  [[ "$output" != *"still running"* ]]

  # A yes/no question: exit 1 is "no", 130 is Ctrl-C.
  gum_answers '0|dev@example.com' '0|github' '0|' '0|' '130|'
  run --separate-stderr in_bootstrap 'ig_ask linux; echo still running'
  [ "$status" -ne 0 ]
  [[ "$output" != *"still running"* ]]
}

@test "bootstrap.sh: tool-group labels name tools from that group on that OS" {
  for os in darwin linux wsl; do
    for group in specialist personal; do
      run in_bootstrap "ig_group_label $group $os"
      [ "$status" -eq 0 ]
      [ "${output##*|}" = "$group" ]
      names=${output#*: }
      names=${names%|*}
      for name in ${names//,/ }; do
        run render_tpl darwin-admin "{{ \$p := index .packages \"$name\" }}{{ \$p.group }} {{ if hasKey \$p \"platforms\" }}{{ \$p.platforms | join \" \" }}{{ else }}$os{{ end }}"
        [ "$status" -eq 0 ] || { echo "$name is not in the catalog"; false; }
        [ "${output%% *}" = "$group" ] || { echo "$name is in group ${output%% *}, not $group"; false; }
        [[ " ${output#* } " == *" $os "* ]] || { echo "$name is not available on $os"; false; }
      done
    done
  done
}

@test "bootstrap.sh: the tool-choice menu comes from the config template" {
  mkdir -p "$HOME/.local/bin"
  ln -s "$(command -v chezmoi)" "$HOME/.local/bin/chezmoi"
  IGNITE_LOCAL_SOURCE="$REPO" run --separate-stderr in_bootstrap 'OS=darwin; ig_chezmoi_args; ig_choice_menu'
  [ "$status" -eq 0 ]
  [[ "$output" == *"editor"$'\t'"vscode"$'\t'* ]]
}

@test "bootstrap.sh: a remote repo is fetched with the answers so far before the menu" {
  mkdir -p "$HOME/.local/bin"
  printf '#!/bin/bash\necho "chezmoi $*" >> "%s"\ncase " $* " in *" source-path "*) echo /src/home ;; *" execute-template "*) printf "editor\\tvscode\\tvscode zed\\n" ;; esac\n' \
    "$CALLS" > "$HOME/.local/bin/chezmoi"
  chmod +x "$HOME/.local/bin/chezmoi"
  run --separate-stderr in_bootstrap "OS=linux; ig_chezmoi_args; IG_ANSWERS=(--promptString 'Work email for git=dev@example.com'); ig_choice_menu"
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf 'editor\tvscode\tvscode zed')" ]
  # The email has no default, so --promptDefaults alone would stop at its prompt.
  grep -q '^chezmoi init https://github.com/henrypham67/ignite.git --promptString Work email for git=dev@example.com --promptDefaults --config-path ' "$CALLS"
  grep -q 'execute-template --init .*--file /src/home/.chezmoi.toml.tmpl' "$CALLS"
}

@test "bootstrap.sh: gum only on a first run with a terminal" {
  run in_bootstrap 'ig_use_gum 1'
  [ "$status" -eq 0 ]
  run in_bootstrap 'ig_use_gum ""'
  [ "$status" -ne 0 ]
  run in_bootstrap 'ig_use_gum 1 --no-tty'
  [ "$status" -ne 0 ]
  IGNITE_NO_GUM=1 run in_bootstrap 'ig_use_gum 1'
  [ "$status" -ne 0 ]
  IG_TTY="$BATS_TEST_TMPDIR/no-such-tty" run in_bootstrap 'ig_use_gum 1'
  [ "$status" -ne 0 ]
}

@test "bootstrap.sh: gum answers are added to chezmoi init on the first run" {
  stub_mise "$STUBS/gum"
  gum_answers '0|dev@example.com' '0|github' '0|' '0|' '1|'
  run --separate-stderr in_bootstrap "OS=linux; ig_chezmoi_args; ig_ask_with_gum 1; $SHOW_ARGS"
  [ "$status" -eq 0 ]
  [[ "${lines[1]}" == "init:init|https://github.com/henrypham67/ignite.git|--promptString|Work email for git=dev@example.com|"* ]]
  # From the home folder, so a mise.toml where the bootstrap was started can't
  # stop the install with a trust prompt.
  grep -q "^mise -C $HOME install gum@" "$CALLS"

  : > "$CALLS"
  run --separate-stderr in_bootstrap "OS=linux; ig_chezmoi_args; ig_ask_with_gum ''; $SHOW_ARGS"
  [ "${lines[1]}" = "init:init|https://github.com/henrypham67/ignite.git|" ]
  [ ! -s "$CALLS" ]
}

@test "bootstrap.sh: without gum, chezmoi asks the questions" {
  mkdir -p "$HOME/.local/bin"
  printf '#!/bin/bash\nexit 1\n' > "$HOME/.local/bin/mise"
  chmod +x "$HOME/.local/bin/mise"
  run --separate-stderr in_bootstrap "OS=linux; ig_chezmoi_args; ig_ask_with_gum 1; $SHOW_ARGS"
  [ "$status" -eq 0 ]
  [[ "$output" == *"chezmoi asks the questions"* ]]
  printf '%s\n' "$output" | grep -qx 'init:init|https://github.com/henrypham67/ignite.git|'
}

@test "bootstrap.sh: runs under /bin/bash 3.2" {
  [ -x /bin/bash ] || skip "no /bin/bash"
  /bin/bash -n "$REPO/bootstrap.sh"
  run in_bootstrap /bin/bash 'ig_detect_os; ig_detect_admin darwin'
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf 'darwin\n0')" ]
  run in_bootstrap /bin/bash "OS=darwin; ig_chezmoi_args --no-tty --promptString 'a b=c d'; $SHOW_ARGS"
  [ "$status" -eq 0 ]
  [ "${lines[1]}" = "init:init|https://github.com/henrypham67/ignite.git|--no-tty|--promptString|a b=c d|" ]
  printf 'x\n' > "$HOME/.zshrc"
  run in_bootstrap /bin/bash "printf '%s\n' .zshrc | ig_backup_targets"
  [ "$status" -eq 0 ]
  [ -f "${lines[0]}/.zshrc" ]
  printf 'C\n' > "$HOME/c.pem"
  printf 'R\n' > "$BATS_TEST_TMPDIR/roots.pem"
  IGNITE_SYSTEM_ROOTS="$BATS_TEST_TMPDIR/roots.pem" IGNITE_CA_CERT='~/c.pem' run in_bootstrap /bin/bash 'ig_setup_ca darwin 0; echo ok'
  [ "$status" -eq 0 ]
  [ "${lines[${#lines[@]}-1]}" = ok ]
  gum_answers '0|dev@example.com' '0|github' '0|aws' '0|personal' '0|' '0|vim'
  run --separate-stderr in_bootstrap /bin/bash "ig_choice_menu() { printf 'terminal_editor\tneovim\tneovim vim\n'; }; ig_ask linux && $PRINT_ANSWERS"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qx 'Choice for terminal_editor=vim'
  printf '%s\n' "$output" | grep -qx 'Install personal apps=true'
  grep -q 'terminal editor' "$CALLS"
}
