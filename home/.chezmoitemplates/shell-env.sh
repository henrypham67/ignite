{{- /*
  Environment shared by .zshrc and .bashrc: secrets, company GitLab, company
  CA. Rendered with the root context.
*/ -}}
# Secrets live outside the repo; fill them in ~/.config/ignite/secrets.env.
[ -f ~/.config/ignite/secrets.env ] && { set -a; . ~/.config/ignite/secrets.env; set +a; }
{{- if eq .ignite.git_host "gitlab" }}
export GITLAB_URL={{ .ignite.gitlab_url | squote }}
{{- end }}
{{- if .ignite.ca_cert }}

# Company CA (TLS-inspecting proxy): tools with their own CA lists use the bundle.
export SSL_CERT_FILE={{ .ignite.ca_bundle | squote }}
export REQUESTS_CA_BUNDLE={{ .ignite.ca_bundle | squote }}
export CURL_CA_BUNDLE={{ .ignite.ca_bundle | squote }}
export AWS_CA_BUNDLE={{ .ignite.ca_bundle | squote }}
export NODE_EXTRA_CA_CERTS={{ .ignite.ca_cert | squote }}
{{- end }}
