# Local example

Applies circuit-nfs to a throwaway Rocky Linux 10 container with systemd: `/srv/nfs/projects`, read-write for one client at 10.89.63.10, and `/srv/nfs/public`, read-only for the whole 10.89.63.0/24 network. You need Conn3x and rootful Podman.

The NFS server lives in the kernel, so the container runs privileged, and NFS can't export folders on overlayfs, so `up.sh` unpacks the image into a volume and boots the container from that directory instead. It puts the container at 10.89.63.2 on a Podman network of its own, so other containers can mount from it. On a Mac, use the Podman machine's root connection. On Linux, use `sudo podman`:

```sh
export CONTAINER_CONNECTION=podman-machine-default-root   # macOS
export PODMAN="sudo podman"                               # Linux
./up.sh
conn3x init
conn3x apply
conn3x plan
```

The second plan says `No changes.` To mount from a client, start one at the allowed address, install the NFS tools and write a file:

```sh
podman run -d --name circuit-nfs-client --privileged --network circuit-nfs --ip 10.89.63.10 --entrypoint sleep circuit-nfs infinity
podman exec circuit-nfs-client dnf -y install nfs-utils
podman exec circuit-nfs-client sh -c 'mkdir -p /mnt/projects && mount -t nfs4 10.89.63.2:/srv/nfs/projects /mnt/projects && echo hello > /mnt/projects/hello.txt'
podman exec circuit-nfs ls -l /srv/nfs/projects
```

Start another at 10.89.63.11 and the same mount is refused, while `/srv/nfs/public` mounts read-only.

`up.sh` listens on `127.0.0.1:2222` for SSH. Set `PORT` to use another port, and pass the same port to Conn3x with `-var port=PORT`. Set `SUBNET` (default `10.89.63`) if that network is taken, and change the addresses in `main.tf` to match. Set `CONTAINERFILE` to test another distro, such as one of the images in Conn3x's `test/images`, which CI uses.

`./down.sh` unmounts and removes any client containers on the network, then the server, its volume and network, the key and the state. Remove clients before the server, as `down.sh` does: a client with a mount on a server that's gone hangs until the server comes back.
