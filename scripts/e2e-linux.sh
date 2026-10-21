#!/usr/bin/env bash
# Run scripts/e2e.sh in a throwaway Ubuntu container, as a normal user with
# passwordless sudo (the "admin" path). Set IGNITE_NO_ADMIN=1 for the other one.
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
docker run --rm \
  -v "$repo":/src:ro \
  -e IGNITE_NO_ADMIN="${IGNITE_NO_ADMIN:-}" \
  -e IGNITE_SKIP="${IGNITE_SKIP:-docker-engine,multipass}" \
  ubuntu:24.04 bash -euc '
    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq sudo curl ca-certificates git >/dev/null
    useradd -m -s /bin/bash ignite
    echo "ignite ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/ignite
    cp -r /src /home/ignite/src
    chown -R ignite:ignite /home/ignite/src
    su ignite -c "cd ~ && IGNITE_NO_ADMIN=$IGNITE_NO_ADMIN IGNITE_SKIP=$IGNITE_SKIP IGNITE_LOCAL_SOURCE=/home/ignite/src bash /home/ignite/src/scripts/e2e.sh"
  '
