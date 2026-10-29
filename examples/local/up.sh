#!/usr/bin/env sh
# Starts a throwaway NFS host on 127.0.0.1:$PORT (default 2222) that Conn3x
# can configure, with a fresh SSH key and its host key in ./known_hosts.
# CONTAINERFILE picks another image, such as one of Conn3x's test images.
# Needs rootful Podman: the host runs systemd and the kernel's NFS server.
#
# The container sits at 10.89.63.2 on a network of its own, so client
# containers can mount from it. It's privileged, since nfsd is in the
# kernel, and its root file system is a plain directory in a volume rather
# than overlayfs, which NFS can't export.
set -eu
cd "$(dirname "$0")"
port=${PORT:-2222}
containerfile=${CONTAINERFILE:-Containerfile}
name=${NAME:-circuit-nfs}
subnet=${SUBNET:-10.89.63}

podman=${PODMAN:-podman}
[ -f id_ed25519 ] || ssh-keygen -q -t ed25519 -N '' -C "$name" -f id_ed25519
$podman build -q -f "$containerfile" -t "$name" "$(dirname "$containerfile")" >/dev/null
$podman rm -f -v "$name" >/dev/null 2>&1 || true
$podman volume rm -f "$name-root" >/dev/null 2>&1 || true
$podman network exists "$name" || $podman network create --subnet "$subnet.0/24" "$name" >/dev/null

$podman volume create "$name-root" >/dev/null
tmp=$($podman create "$name")
$podman export "$tmp" | $podman volume import "$name-root" -
$podman rm "$tmp" >/dev/null
root=$($podman volume inspect -f '{{.Mountpoint}}' "$name-root")

$podman run -d --name "$name" --privileged --systemd=always \
  --network "$name" --ip "$subnet.2" -p "127.0.0.1:$port:22" \
  --rootfs "$root" /sbin/init >/dev/null
$podman exec -i "$name" sh -c 'cat > /root/.ssh/authorized_keys && chmod 600 /root/.ssh/authorized_keys' < id_ed25519.pub
$podman exec "$name" timeout 60 systemctl is-system-running --wait >/dev/null 2>&1 || true

for _ in 1 2 3 4 5 6 7 8 9 10; do
  if ssh-keyscan -p "$port" 127.0.0.1 > known_hosts 2>/dev/null && [ -s known_hosts ]; then
    echo "Ready on 127.0.0.1:$port. Now run: conn3x init && conn3x apply -var port=$port"
    exit 0
  fi
  sleep 1
done
echo "The container started, but SSH didn't answer on 127.0.0.1:$port." >&2
exit 1
