# Ghostty on Linux: the snap is the packaged option on Ubuntu.
if ! command -v snap >/dev/null 2>&1; then
  echo "snap is not available; install Ghostty from https://ghostty.org/download"
  return 1
fi
ig_sudo snap install ghostty --classic
