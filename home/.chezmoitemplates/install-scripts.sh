{{- /*
  Shared body of the 15-scripts-admin and 40-scripts runners. Call with
  (dict "root" $ "admin" true|false). Each catalog entry with method "script"
  gets its .chezmoitemplates/install/<name>.sh wrapped in a function, run
  through ig_try.
*/ -}}
{{- $root := .root -}}
{{- $source := ternary "script-admin" "script" .admin -}}
{{- $selected := includeTemplate "selected.json" $root | fromJson -}}
{{- $items := list -}}
{{- range $name, $entry := $selected -}}
{{-   $adminOnly := not (not (get $entry "admin_only")) -}}
{{-   if kindIs "slice" (get $entry "admin_only") }}{{ $adminOnly = has $root.ignite.os $entry.admin_only }}{{ end -}}
{{-   if and (eq $entry.method "script") (eq $adminOnly $.admin) }}{{ $items = append $items $name }}{{ end -}}
{{- end -}}
{{- if and (ne $root.ignite.os "windows") $items -}}
#!/bin/bash
# Catalog entries installed by their own script (.chezmoitemplates/install/).
set -uo pipefail
{{ template "lib.sh" $root }}
ig_path_setup
ig_reset {{ $source }}
{{- range $name := $items }}
{{-   $fn := printf "ig_install_%s" ($name | replace "-" "_" | replace "." "_") }}

{{ $fn }}() {
  set -eo pipefail
{{ includeTemplate (printf "install/%s.sh" $name) $root | trim | indent 2 }}
}
ig_try {{ $source }} {{ $name }} {{ $fn }}
{{- end }}
{{ end -}}
