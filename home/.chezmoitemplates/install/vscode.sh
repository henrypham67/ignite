# VS Code on Linux from Microsoft's tarball: per user, so it works without admin.
arch=x64
case "$(uname -m)" in
  aarch64 | arm64) arch=arm64 ;;
esac
tmp=$(mktemp -d)
curl -fsSL -o "$tmp/code.tar.gz" "https://update.code.visualstudio.com/latest/linux-$arch/stable"
dest="$HOME/.local/share/vscode"
rm -rf "$dest"
mkdir -p "$dest" "$HOME/.local/bin"
tar -xzf "$tmp/code.tar.gz" -C "$dest" --strip-components=1
ln -sf "$dest/bin/code" "$HOME/.local/bin/code"
rm -rf "$tmp"
