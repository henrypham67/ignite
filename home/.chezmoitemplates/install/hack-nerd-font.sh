# Hack Nerd Font into the per-user font folder (no admin needed).
tmp=$(mktemp -d)
curl -fsSL -o "$tmp/Hack.zip" https://github.com/ryanoasis/nerd-fonts/releases/latest/download/Hack.zip
{{- if eq .ignite.os "darwin" }}
dest="$HOME/Library/Fonts"
{{- else }}
dest="$HOME/.local/share/fonts"
{{- end }}
mkdir -p "$dest"
unzip -o -q "$tmp/Hack.zip" '*.ttf' -d "$dest"
if command -v fc-cache >/dev/null 2>&1; then
  fc-cache -f "$dest"
fi
rm -rf "$tmp"
