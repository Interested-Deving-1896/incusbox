# AGENTS.md — incusbox

Architecture decisions, conventions, and patterns for this project.
Read this before making changes.

---

## Repository layout

```
incusbox/
  incusbox              Top-level dispatcher (routes to incusbox-* scripts)
  incusbox-create       Create a container
  incusbox-enter        Enter a running container
  incusbox-list         List containers
  incusbox-rm           Remove a container
  incusbox-stop         Stop a container
  incusbox-upgrade      Upgrade packages inside a container
  incusbox-snapshot     Create, list, restore, delete snapshots
  incusbox-console      Attach to a container console
  incusbox-backup       Export a container to a portable archive
  incusbox-restore      Import a container from a backup archive
  incusbox-export       Export an app/binary/service from inside a container
  incusbox-host-exec    Run a host command from inside a container
  incusbox-assemble     Create/update containers from a declarative YAML file
  incusbox-setup-rootless  Guided setup for rootless incusbox via incus-user
  incusbox-init         Cloud-init-style init script run inside the container
  lib.sh                Shared library sourced by all scripts
  install               Installer script
  profiles/             Incus profile YAML files
  completions/          Shell completions (bash, zsh)
  man/                  Man pages
  docs/                 Documentation and example files
```

---

## Shared library (lib.sh)

Every `incusbox-*` script sources `lib.sh` at startup. It provides:

- **Environment normalisation** — `USER`, `HOME`, `SHELL` set from `id`/`getent` if missing
- **Config loading** — sources config files in order (system → user); uses
  `if [ -e ]; then . file; fi` (never `[ -e ] && . file` which exits under `set -e`)
- **Logging** — `log`, `die`, `warn`, `info` (info only when `verbose=1`)
- **Incus resolution** — `resolve_incus` sets `INCUS` and `INCUS_SOCKET`
- **Dependency checks** — `require_incus`, `require_cmd`
- **Container metadata** — `container_config NAME KEY`, `container_status NAME`
- **Doctor** — `incusbox_doctor` runs prerequisite checks

**Config file load order** (later files override earlier):
1. `/usr/share/incusbox/incusbox.conf`
2. `/usr/local/share/incusbox/incusbox.conf`
3. `/etc/incusbox/incusbox.conf`
4. `$XDG_CONFIG_HOME/incusbox/incusbox.conf`
5. `~/.incusboxrc`

Set `INCUSBOX_SKIP_CONFIG=1` to suppress config loading (useful in tests).

---

## Incus binary resolution

`resolve_incus` in `lib.sh` sets `INCUS` (the command to invoke):

1. `rootful=1` and non-root → `sudo incus`, clear `INCUS_SOCKET`
2. Non-root + user socket exists → `incus`, export `INCUS_SOCKET`
3. Otherwise → `incus`, clear `INCUS_SOCKET`

Scripts that need rootful access set `rootful=1` before calling `resolve_incus`.

---

## Snapshot, console, backup, restore

These commands delegate directly to Incus:

| Command | Incus call |
|---|---|
| `incusbox snapshot create NAME [SNAP]` | `incus snapshot create` |
| `incusbox snapshot list NAME` | `incus info` (parses Snapshots section) |
| `incusbox snapshot restore NAME SNAP` | `incus snapshot restore` |
| `incusbox snapshot delete NAME SNAP` | `incus snapshot delete` |
| `incusbox console NAME` | `incus console` |
| `incusbox backup NAME [--output PATH]` | `incus export` |
| `incusbox restore NAME --from PATH` | `incus import` |

---

## Declarative assembly (incusbox-assemble)

`incusbox assemble --file FILE` reads a YAML file and creates/updates containers.

- Uses a minimal line-by-line YAML parser (no external deps)
- `--dry-run` prints commands without executing
- `--replace` removes and recreates existing containers
- See `docs/example-assemble.yaml` for the full schema

---

## CI (.github/workflows/ci.yaml)

- **syntax** — `bash -n` on all scripts
- **shellcheck** — `shellcheck --severity=warning` on all scripts
  - SC1090, SC1091, SC2154, SC3043 globally excluded (expected patterns)
  - SC2034 is NOT globally excluded — use per-file `# shellcheck disable=SC2034`
- **install-dry-run** — runs `./install --user` and verifies all files land correctly
- **profile-yaml** — validates all profile YAML files with `yq`
- **assemble-parse** — tests the YAML parser against `docs/example-assemble.yaml`
- **integration** — live Incus daemon; exercises create → enter → list → rm

---

## Intentional divergence from other Incus projects

The following features exist in other projects in this suite but are
**intentionally absent** from incusbox because they are container-specific
or Linux-distro-specific concepts with no meaningful VM equivalent:

| Feature | Reason absent |
|---|---|
| `upgrade` (package manager) | Distro-specific; `apt`/`dnf`/`pacman` differ per image |
| `export` (app/binary to host) | Linux namespace sharing — not applicable to VMs |
| `setup-rootless` | `incus-user` daemon — container-specific concept |
| GPU passthrough via VFIO | VM-specific (VFIO/SR-IOV); containers use device passthrough differently |
| macOS/Windows image pipeline | Guest-OS-specific; incusbox targets Linux containers only |
| Android extensions (GApps, Magisk) | Android-specific; incusbox targets Linux containers |

These are not gaps — they are correct omissions for a Linux container manager.

---

## Adding a new subcommand

1. Create `incusbox/incusbox-<name>` (executable, `#!/bin/bash`, sources `lib.sh`)
2. Add it to the `executables` list in `incusbox/install`
3. Add the command to `show_help()` and the `case` dispatch in `incusbox/incusbox`
4. Add syntax + shellcheck coverage (automatic via glob in CI)
5. If it introduces new optional deps, add them to `incusbox_doctor` in `lib.sh`
