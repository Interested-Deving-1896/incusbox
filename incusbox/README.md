# incusbox

Use any Linux distribution inside your terminal, with tight host integration,
backed by [Incus](https://linuxcontainers.org/incus/) system containers instead
of Docker or Podman.

Inspired by [distrobox](https://github.com/89luca89/distrobox). Replaces the
OCI application container backend with Incus system containers, gaining full
init system support, ZFS/Btrfs-native storage, and VM capability — while
keeping the same user-facing workflow.

---

## Requirements

| Dependency | Purpose | Required |
|---|---|---|
| `incus` ≥ 6.0 | Container runtime | Always |
| `skopeo` | OCI image pull from Docker Hub / GHCR / Quay | OCI images only |
| `cloud-init` | In-container first-boot setup | In OCI images |
| `zfs` / `zpool` | ZFS dataset management for home dirs | ZFS storage only |
| `btrfs-progs` | Btrfs subvolume management for home dirs | Btrfs storage only |
| `incus-user` | Rootless container daemon | Rootless mode only |

---

## Installation

### System-wide (requires root)

```sh
git clone https://github.com/Interested-Deving-1896/incusbox
cd incusbox/incusbox
sudo ./install
```

### User install (no root required)

```sh
git clone https://github.com/Interested-Deving-1896/incusbox
cd incusbox/incusbox
./install --user
# Add ~/.local/bin to PATH if not already present
export PATH="${PATH}:${HOME}/.local/bin"
```

The install script:
- Copies all scripts to `{prefix}/bin/`
- Copies Incus profiles to `{prefix}/share/incusbox/profiles/`
- Registers profiles with the running Incus daemon (if available)
- Registers OCI remotes: `docker` (docker.io), `ghcr` (ghcr.io), `quay` (quay.io)

---

## Quick start

```sh
# Create a container from a Docker Hub image
incusbox create --image docker:ubuntu:22.04 --name mybox

# Enter it
incusbox enter mybox

# Create from an Incus native image
incusbox create --image images:fedora/40 --name fedbox

# Create with NVIDIA GPU passthrough
incusbox create --image docker:ubuntu:22.04 --name gpubox --nvidia

# List all incusbox containers
incusbox list

# Stop a container
incusbox stop mybox

# Remove a container
incusbox rm mybox
```

---

## Storage

incusbox auto-detects the Incus storage pool driver and applies
storage-specific behaviour for the container's home directory.

### ZFS

```sh
# Use a specific pool
incusbox create --image docker:ubuntu:22.04 --name mybox \
    --storage-pool tank

# Create a dedicated ZFS dataset for the home directory
# (separate from the Incus-managed rootfs dataset)
incusbox create --image docker:ubuntu:22.04 --name mybox \
    --storage-pool tank \
    --storage-dataset tank/incusbox
```

When `--storage-dataset` is set, incusbox creates
`<dataset>/<name>/home` with `compression=zstd,atime=off` and mounts it
as the container's home directory. The container rootfs dataset is always
managed by Incus itself.

### Btrfs

```sh
# Default compression (zstd)
incusbox create --image docker:ubuntu:22.04 --name mybox \
    --home-prefix /data/incusbox

# Custom compression
incusbox create --image docker:ubuntu:22.04 --name mybox \
    --home-prefix /data/incusbox \
    --btrfs-compress lzo
```

When the home directory path lives on a Btrfs filesystem, incusbox creates
a subvolume at that path and sets the compression property.

### dir (default)

No special handling — plain directories are used.

---

## Rootless mode

Rootless containers run via the `incus-user` per-user daemon. Run the
setup helper first:

```sh
incusbox-setup-rootless
```

This checks for and configures:
- `incus-user` systemd user service
- AppArmor profiles (required on Ubuntu 24.04+)
- `/dev/fuse` access (required for fuse-overlayfs)
- UID/GID mapping

Once set up, all `incusbox` commands work without `sudo` or `--root`.

---

## Namespace sharing

By default, incusbox shares the host's PID, IPC, and network namespaces
so the container feels like a native part of the host system. Each can be
disabled individually:

```sh
incusbox create --image docker:ubuntu:22.04 --name isolated \
    --unshare-netns \   # own network namespace (bridged NIC)
    --unshare-ipc \     # own IPC namespace
    --unshare-process   # own PID namespace (no host process visibility)

# Or disable all at once
incusbox create --image docker:ubuntu:22.04 --name isolated \
    --unshare-all
```

---

## Init system support

For containers that need a full init system (systemd, OpenRC):

```sh
incusbox create --image docker:ubuntu:22.04 --name svcbox --init
```

This applies the `incusbox-init` Incus profile which mounts the tmpfs
paths systemd requires (`/run`, `/run/lock`, `/var/lib/journal`) and
enables user lingering.

---

## Exporting applications

From inside a container, export apps, binaries, or services to the host:

```sh
# Export a .desktop application (appears in host app launcher)
incusbox-export --app firefox

# Export a binary to ~/.local/bin on the host
incusbox-export --bin /usr/bin/htop

# Export a systemd user service
incusbox-export --service syncthing

# Remove an export
incusbox-export --delete --app firefox
```

---

## Running host commands from inside a container

```sh
# From inside an incusbox container:
incusbox-host-exec flatpak run org.mozilla.firefox
incusbox-host-exec systemctl --user status
incusbox-host-exec bash
```

Uses `nsenter` to escape into the host's namespaces. Falls back to
`chroot /run/host` when the PID namespace is unshared.

---

## Declarative containers (incusbox-assemble)

Define containers in YAML and create them all at once:

```yaml
# myboxes.yaml
containers:
  - name: ubuntu-dev
    image: docker:ubuntu:22.04
    additional_packages: git curl build-essential
    init_hooks: "curl -fsSL https://get.docker.com | sh"

  - name: fedora-tools
    image: images:fedora/40
    nvidia: true
    home_prefix: /data/incusbox

  - name: arch-gaming
    image: docker:archlinux
    init: true
    storage_pool: tank
    storage_dataset: tank/incusbox
```

```sh
incusbox-assemble --file myboxes.yaml
```

---

## Supported images

Any image accessible via an OCI registry or Incus image server:

```sh
# Docker Hub
incusbox create --image docker:ubuntu:22.04
incusbox create --image docker:fedora:40
incusbox create --image docker:archlinux
incusbox create --image docker:alpine:3.19
incusbox create --image docker:debian:bookworm

# GitHub Container Registry
incusbox create --image ghcr:someorg/someimage:latest

# Quay.io
incusbox create --image quay:fedora/fedora:40

# Incus image servers (no skopeo required)
incusbox create --image images:ubuntu/24.04
incusbox create --image images:fedora/40
incusbox create --image images:archlinux
incusbox create --image images:alpine/3.19
```

---

## Profiles

Incus profiles are stored in `profiles/` and registered at install time.
They can be inspected or modified directly:

```sh
incus profile show incusbox-base
incus profile edit incusbox-base
```

| Profile | Applied when |
|---|---|
| `incusbox-base` | All containers |
| `incusbox-init` | `--init` flag |
| `incusbox-nvidia` | `--nvidia` flag |
| `incusbox-unshare-net` | `--unshare-netns` flag |
| `incusbox-gui` | GUI app containers |
| `incusbox-rootless` | Rootless (`incus-user`) mode |

---

## Known limitations

- **OCI images without cloud-init**: Images that don't include cloud-init
  (Alpine, Arch, minimal Ubuntu) use a direct `incus exec` injection
  fallback instead of cloud-init. This is less reliable on first boot
  timing — see `incusbox-init` for details.
- **`lxc.namespace.share.pid`**: Host PID namespace sharing requires a
  non-hardened kernel. Some distributions (e.g. certain Fedora/RHEL
  configurations) reject this even for privileged containers.
- **Rootless OCI images**: Pulling OCI images in rootless mode goes through
  the `incus-user` daemon (which runs as root internally), so it works
  transparently. If you encounter permission errors, run
  `incusbox-setup-rootless` to verify your setup.

---

## License

GPL-3.0-only — same as distrobox, from which this project draws inspiration.
