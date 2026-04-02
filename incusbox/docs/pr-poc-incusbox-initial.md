# incusbox PoC: Incus-backed distrobox replacement

## Summary

Proof-of-concept implementation of `incusbox` — a distrobox-compatible tool
that uses [Incus](https://linuxcontainers.org/incus/) system containers as its
backend instead of Docker, Podman, or Lilipod.

Implements the full create/enter/list/rm/stop/upgrade/export lifecycle. All
10 scripts pass `sh -n` syntax validation. Not yet tested against a live Incus
daemon — this PR establishes the architecture for empirical validation.

---

## What was built

### Scripts

| Script | Role |
|---|---|
| `incusbox` | Top-level dispatcher |
| `incusbox-create` | Container creation — OCI/Incus images, storage detection, cloud-init generation |
| `incusbox-enter` | Start + enter — polls `/run/incusbox-ready` for readiness |
| `incusbox-init` | **Runs inside container** — replaces `distrobox-init`; injected via cloud-init |
| `incusbox-export` | **Runs inside container** — exports apps/binaries/systemd services to host |
| `incusbox-host-exec` | **Runs inside container** — escapes to host via `nsenter` |
| `incusbox-list/rm/stop/upgrade` | Lifecycle management |
| `install` | System-wide or user install; registers Incus profiles + OCI remotes |

### Incus profiles

| Profile | Purpose |
|---|---|
| `incusbox-base` | Nesting, syscall interception (`mknod`/`setxattr`/`bpf`), `/dev/fuse`, `/dev/net/tun` |
| `incusbox-init` | systemd-inside-container tmpfs mounts (`/run`, `/run/lock`, `/var/lib/journal`) |
| `incusbox-nvidia` | NVIDIA GPU device passthrough + `nvidia.runtime=true` |
| `incusbox-unshare-net` | Isolated bridge NIC instead of host network namespace |
| `incusbox-gui` | X11/Wayland/PipeWire/DRI passthrough for graphical apps |
| `incusbox-rootless` | AppArmor unconfined + fuse-overlayfs for `incus-user` daemon |

---

## Key design decisions

### OCI image support
`incusbox-create` detects OCI registry references by hostname pattern and
auto-registers `--protocol=oci` remotes with Incus. The `install` script
pre-registers `docker` (docker.io), `ghcr` (ghcr.io), and `quay` (quay.io).
`skopeo` is required and checked as a hard dependency before any OCI operation.

Usage:
```sh
incusbox create --image docker:ubuntu:22.04 --name mybox
incusbox create --image ghcr:someorg/someimage:latest --name ghcrbox
```

### Storage detection (ZFS / Btrfs / dir)
`incusbox-create` auto-detects the Incus pool driver and applies
storage-specific behaviour for the bind-mounted home directory:

- **ZFS** (`--storage-dataset tank/incusbox`): creates a dedicated dataset per
  container with `compression=zstd,atime=off`. The Incus rootfs dataset is
  always managed by Incus itself.
- **Btrfs**: creates a subvolume at the home path with configurable compression
  (`--btrfs-compress zstd|lzo|zlib`, default `zstd`).
- **dir**: plain directory, no special handling.

### Readiness signalling
`incusbox-enter` polls for `/run/incusbox-ready` (written by `incusbox-init`
at the end of setup) with a 120s timeout, falling back to checking
`cloud-init status`. This replaces distrobox's log-streaming IPC pattern which
has no equivalent in Incus.

### `--pid host` via `raw.lxc`
`incusbox-create` sets `lxc.namespace.share.pid = 1` unless `--unshare-process`
is passed. `incusbox-host-exec` uses `nsenter` into `/proc/1/ns/*` as the
primary escape path, with a `/run/host` chroot fallback when PID namespace is
unshared.

### Rootless path
The `incusbox-rootless` profile incorporates the AppArmor + fuse-overlayfs
patterns from [podclaw](https://github.com/mikestankavich/podclaw):
- `lxc.apparmor.profile = unconfined` — bypasses Ubuntu 24.04's default
  restriction on unprivileged user namespaces
- `/dev/fuse` device passthrough — enables fuse-overlayfs, avoiding the 10+
  minute recursive chown penalty with rootless Podman inside the container
- Syscall interception for `mknod`/`setxattr`/`bpf`

### `incusbox-init` distro coverage
Handles: `apt` (Debian/Ubuntu/Mint/Pop), `dnf`/`yum` (Fedora/RHEL/Alma/Rocky),
`pacman` (Arch/Manjaro/EndeavourOS), `apk` (Alpine), `zypper` (openSUSE/SLES),
`xbps` (Void), `emerge` (Gentoo). NixOS is detected and skipped with a note.

---

## Known limitations

### 1. `raw.lxc` accumulation bug (must fix before first live test)
`configure_container()` in `incusbox-create` calls `incus config set raw.lxc`
multiple times across separate code paths (PID namespace, IPC namespace, host
network). Each call overwrites the previous value. All `raw.lxc` directives
need to be assembled into a single string and set in one `incus config set`
call.

**Affected file:** `incusbox-create`, `configure_container()` function.

### 2. OCI export root requirement
Incus's Go client (`client/oci_images.go`) has a hard check:
```go
if os.Geteuid() != 0 {
    return nil, errors.New("OCI image export currently requires root access")
}
```
The `incus remote add --protocol=oci` + `incus launch` path used here goes
through the Incus daemon (which runs as root), so rootless users *should* be
able to pull OCI images via the `incusd`/`incus-user` daemon. This needs
empirical confirmation — if the check fires at the daemon level rather than
the client level, a `skopeo` + `umoci` pre-flight workaround will be needed.

### 3. `lxc.namespace.share.pid = 1` needs empirical testing
Host process visibility from inside the container (distrobox's `--pid host`
equivalent) is implemented via `raw.lxc = "lxc.namespace.share.pid = 1"`.
This works on most kernels but is rejected by some hardened configurations
even for privileged containers. Needs testing on the target host before
declaring the feature working.

### 4. `--storage-dataset` vs Incus pool name distinction
`--storage-dataset` takes a ZFS dataset path (e.g. `tank/incusbox`), not an
Incus pool name. These are different things. The help text should make this
explicit and the code should validate that the path looks like a ZFS dataset
rather than an Incus pool name.

---

## Testing checklist

Before merging, validate empirically:

- [ ] `incusbox create --image docker:ubuntu:22.04 --name test` — OCI pull + launch
- [ ] `incusbox enter test` — readiness wait + shell drop
- [ ] `incusbox enter test -- bash -c 'id && echo $HOME'` — correct UID/home
- [ ] `incusbox-host-exec ls /` from inside container — nsenter escape
- [ ] `incusbox create --image images:fedora/40 --name fedbox` — Incus native image
- [ ] `incusbox create --image docker:ubuntu:22.04 --name nvbox --nvidia` — GPU passthrough
- [ ] `incusbox create --image docker:ubuntu:22.04 --name zfsbox --storage-dataset tank/incusbox` — ZFS dataset creation
- [ ] `incusbox create --image docker:ubuntu:22.04 --name btrfsbox --btrfs-compress zstd` — Btrfs subvolume
- [ ] `incusbox rm test --rm-home` — ZFS/Btrfs cleanup
- [ ] Rootless: `incus-user` daemon + `incusbox-rootless` profile applied
- [ ] Fix `raw.lxc` accumulation bug and re-test PID/IPC/net namespace sharing

---

## References

- [blincus](https://github.com/ublue-os/blincus) — Incus profile + cloud-init patterns
- [podclaw](https://github.com/mikestankavich/podclaw) — AppArmor/fuse-overlayfs/UID alignment patterns
- [jailmaker](https://github.com/Jip-Hop/jailmaker) — GPU passthrough + Docker nesting config
- [eliranwong/incus_container_gui_setup](https://github.com/eliranwong/incus_container_gui_setup) — GUI profile patterns
- [Incus OCI support](https://github.com/lxc/incus/blob/main/client/oci_images.go) — skopeo + umoci pipeline
