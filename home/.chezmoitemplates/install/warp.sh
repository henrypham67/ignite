# Warp on Linux: Warp's .deb package, installed with apt.
tmp=$(mktemp -d)
curl -fsSL -o "$tmp/warp.deb" 'https://app.warp.dev/download?package=deb'
ig_sudo apt-get install -y "$tmp/warp.deb"
rm -rf "$tmp"
