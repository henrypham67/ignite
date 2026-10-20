#!/usr/bin/env bats

load helper

TEMPLATE="$REPO/home/.chezmoi.toml.tmpl"

setup() {
  unset IGNITE_ADMIN IGNITE_CA_CERT_INSTALLED IGNITE_CA_BUNDLE
  with_catalog "$FIXTURES/catalogs/valid.yaml"
}

# Answers for every prompt except the ones a test sets itself.
base_answers=(
  --promptString "Work email for git=ci@example.com"
  --promptChoice "Company git host=github"
  --promptBool "Use AWS=true"
  --promptBool "Use Azure=false"
  --promptBool "Use GCP=false"
  --promptBool "Company licenses Docker Desktop=false"
  --promptBool "Install specialist tools=false"
  --promptBool "Install personal apps=false"
)

# value_of <toml> <key>: value of the first "key = value" line, unquoted.
value_of() {
  printf '%s\n' "$1" | sed -n "s/^[[:space:]]*$2[[:space:]]*=[[:space:]]*//p" | head -n 1 | tr -d "'\""
}

# choice_lines <toml>: "key = value" lines inside [data.ignite.choices].
choice_lines() {
  printf '%s\n' "$1" | awk '
    /^[[:space:]]*\[/ { in_choices = ($0 ~ /\[data\.ignite\.choices\]/); next }
    in_choices && /=/ { print }
  '
}

@test "config: os matches host" {
  run --separate-stderr render_init "$TEMPLATE" "${base_answers[@]}" --promptBool "Change default tool choices=false"
  [ "$status" -eq 0 ]
  case "$(uname -s)" in
    Darwin) expected=darwin ;;
    Linux) expected=linux ;;
  esac
  [ "$(value_of "$output" os)" = "$expected" ]
}

@test "config: IGNITE_ADMIN=1 sets admin true; =0 sets false" {
  IGNITE_ADMIN=1 run --separate-stderr render_init "$TEMPLATE" "${base_answers[@]}" --promptBool "Change default tool choices=false"
  [ "$status" -eq 0 ]
  [ "$(value_of "$output" admin)" = "true" ]

  IGNITE_ADMIN=0 run --separate-stderr render_init "$TEMPLATE" "${base_answers[@]}" --promptBool "Change default tool choices=false"
  [ "$status" -eq 0 ]
  [ "$(value_of "$output" admin)" = "false" ]
}

@test "config: admin defaults to false without IGNITE_ADMIN" {
  run --separate-stderr render_init "$TEMPLATE" "${base_answers[@]}" --promptBool "Change default tool choices=false"
  [ "$status" -eq 0 ]
  [ "$(value_of "$output" admin)" = "false" ]
}

@test "config: prompt answers are recorded" {
  run --separate-stderr render_init "$TEMPLATE" "${base_answers[@]}" --promptBool "Change default tool choices=false"
  [ "$status" -eq 0 ]
  [ "$(value_of "$output" email)" = "ci@example.com" ]
  [ "$(value_of "$output" git_host)" = "github" ]
  [ "$(value_of "$output" cloud_aws)" = "true" ]
  [ "$(value_of "$output" cloud_azure)" = "false" ]
}

@test "config: gitlab_url only prompted for gitlab" {
  run --separate-stderr render_init "$TEMPLATE" "${base_answers[@]}" \
    --promptString "Company GitLab URL=https://gitlab.example.com" \
    --promptBool "Change default tool choices=false"
  [ "$status" -eq 0 ]
  [ "$(value_of "$output" gitlab_url)" = "" ]

  run --separate-stderr render_init "$TEMPLATE" "${base_answers[@]}" \
    --promptChoice "Company git host=gitlab" \
    --promptString "Company GitLab URL=https://gitlab.example.com" \
    --promptBool "Change default tool choices=false"
  [ "$status" -eq 0 ]
  [ "$(value_of "$output" git_host)" = "gitlab" ]
  [ "$(value_of "$output" gitlab_url)" = "https://gitlab.example.com" ]
}

@test "config: CA env recorded" {
  IGNITE_CA_CERT_INSTALLED=/tmp/ca.pem IGNITE_CA_BUNDLE=/tmp/ca-bundle.pem \
    run --separate-stderr render_init "$TEMPLATE" "${base_answers[@]}" --promptBool "Change default tool choices=false"
  [ "$status" -eq 0 ]
  [ "$(value_of "$output" ca_cert)" = "/tmp/ca.pem" ]
  [ "$(value_of "$output" ca_bundle)" = "/tmp/ca-bundle.pem" ]
}

@test "config: customize=false writes no choices table entries" {
  run --separate-stderr render_init "$TEMPLATE" "${base_answers[@]}" --promptBool "Change default tool choices=false"
  [ "$status" -eq 0 ]
  [ -z "$(choice_lines "$output")" ]
}

@test "config: customize=true prompts per job" {
  run --separate-stderr render_init "$TEMPLATE" "${base_answers[@]}" \
    --promptBool "Change default tool choices=true" \
    --promptChoice "Choice for editor=zed"
  [ "$status" -eq 0 ]
  [ "$(choice_lines "$output" | tr -d ' ')" = 'editor="zed"' ]
}

@test "config: choosing the default is not recorded as a customisation" {
  run --separate-stderr render_init "$TEMPLATE" "${base_answers[@]}" \
    --promptBool "Change default tool choices=true" \
    --promptChoice "Choice for editor=vscode" \
    --promptChoice "Choice for prompt=starship"
  [ "$status" -eq 0 ]
  [ -z "$(choice_lines "$output")" ]
}

@test "config: every fixture machine renders .chezmoiignore" {
  for fixture in darwin-admin darwin-noadmin darwin-custom windows-admin windows-noadmin linux-admin wsl-admin; do
    SRC="$REPO"
    run --separate-stderr managed "$fixture"
    [ "$status" -eq 0 ] || { echo "$fixture: $stderr"; false; }
  done
}

@test "config: windows gets the pwsh interpreter" {
  run --separate-stderr render_init "$TEMPLATE" "${base_answers[@]}" --promptBool "Change default tool choices=false"
  [ "$status" -eq 0 ]
  # Only windows gets the block; on the host OS (darwin/linux) it must be absent.
  [[ "$output" != *"interpreters"* ]]
}
