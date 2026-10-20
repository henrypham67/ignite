#!/usr/bin/env bats

load helper

@test "helper: render_tpl renders inline template text" {
  run --separate-stderr render_tpl empty '{{ "ok" }}'
  [ "$status" -eq 0 ]
  [ "$output" = "ok" ]
}

@test "helper: render_tpl sees fixture config data" {
  run --separate-stderr render_tpl empty '{{ .probe }}'
  [ "$status" -eq 0 ]
  [ "$output" = "from-fixture" ]
}
