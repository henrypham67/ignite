# Docker Engine on plain Linux (free, unlike Docker Desktop), via Docker's
# convenience script. Log out and back in for the docker group to apply.
tmp=$(mktemp -d)
curl -fsSL -o "$tmp/get-docker.sh" https://get.docker.com
ig_sudo sh "$tmp/get-docker.sh"
ig_sudo usermod -aG docker "$(id -un)"
rm -rf "$tmp"
