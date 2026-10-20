#!/usr/bin/env bash
# Render every chezmoi script for each fixture machine and lint the result
# (.sh with ShellCheck, .ps1 with PSScriptAnalyzer). Empty renders, which are
# scripts meant for another OS, are skipped.
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT

render() { # render <fixture> <template> <dest>
  chezmoi --source "$repo" --config "$repo/tests/fixtures/config/$1.toml" \
    --persistent-state "$out/state.boltdb" execute-template < "$2" > "$3"
}

sh_files=()
ps_count=0
for fixture in darwin-admin darwin-noadmin darwin-custom linux-admin wsl-admin windows-admin windows-noadmin; do
  mkdir -p "$out/$fixture"
  for template in "$repo"/home/.chezmoiscripts/*.tmpl "$repo"/home/dot_local/bin/*.tmpl; do
    [ -e "$template" ] || continue
    name=$(basename "$template" .tmpl)
    dest="$out/$fixture/$name"
    render "$fixture" "$template" "$dest"
    if [ -z "$(tr -d '[:space:]' < "$dest")" ]; then
      rm -f "$dest"
      continue
    fi
    case "$name" in
      *.ps1) ps_count=$((ps_count + 1)) ;;
      *) sh_files+=("$dest") ;;
    esac
  done
done

if [ "${#sh_files[@]}" -gt 0 ]; then
  shellcheck --shell=bash "${sh_files[@]}"
fi
echo "shellcheck: ${#sh_files[@]} rendered script(s) clean"

if [ "$ps_count" -gt 0 ]; then
  pwsh -NoLogo -NoProfile -Command "
    Import-Module PSScriptAnalyzer
    \$findings = Get-ChildItem -Recurse -Filter '*.ps1' -Path '$out' | ForEach-Object {
      # Rendered scripts are run once by chezmoi: console output is the point,
      # and their small helper functions don't need -WhatIf support.
      Invoke-ScriptAnalyzer -Path \$_.FullName -Severity Warning, Error \`
        -ExcludeRule PSAvoidUsingWriteHost, PSUseShouldProcessForStateChangingFunctions
    }
    if (\$findings) { \$findings | Format-Table -AutoSize RuleName, ScriptName, Line, Message | Out-String -Width 200; exit 1 }
  "
fi
echo "PSScriptAnalyzer: $ps_count rendered script(s) clean"
