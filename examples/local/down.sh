#!/usr/bin/env sh
# Removes the containers and everything up.sh and Conn3x created here.
# Clients go first: one with a mount left on a server that's gone hangs
# until the server comes back.
set -eu
cd "$(dirname "$0")"
name=${NAME:-circuit-nfs}
podman=${PODMAN:-podman}
for c in $($podman ps -a -q --filter "network=$name"); do
  [ "$($podman inspect -f '{{.Name}}' "$c")" = "$name" ] && continue
  $podman exec "$c" umount -a -f -l -t nfs4,nfs >/dev/null 2>&1 || true
  $podman rm -f -v "$c" >/dev/null 2>&1 || true
done
$podman rm -f -v "$name" >/dev/null 2>&1 || true
$podman volume rm -f "$name-root" >/dev/null 2>&1 || true
$podman network rm -f "$name" >/dev/null 2>&1 || true
rm -rf id_ed25519 id_ed25519.pub known_hosts .terraform .terraform.lock.hcl terraform.tfstate terraform.tfstate.backup
echo "Removed."
