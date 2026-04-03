#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
# incusbox shared library.
# Source this file; do not execute directly.
#
# Every incusbox-* script sources this file to get:
#   - USER/HOME/SHELL normalisation
#   - Config file loading
#   - Logging helpers (log, die, info, warn)
#   - Incus binary resolution (INCUS + INCUS_SOCKET)
#   - require_incus / require_cmd
#   - incusbox_doctor

# ── environment normalisation ─────────────────────────────────────────────────
[ -z "${USER}"  ] && USER="$(id -run)"
[ -z "${HOME}"  ] && HOME="$(getent passwd "${USER}" | cut -d: -f6)"
[ -z "${SHELL}" ] && SHELL="$(getent passwd "${USER}" | cut -d: -f7)"
export USER HOME SHELL

# ── config loading ────────────────────────────────────────────────────────────
# Config files are sourced in order; later files override earlier ones.
# Scripts may set INCUSBOX_SKIP_CONFIG=1 to suppress loading (tests).
_incusbox_load_config() {
    [ "${INCUSBOX_SKIP_CONFIG:-0}" = "1" ] && return 0
    local _cf
    for _cf in \
        /usr/share/incusbox/incusbox.conf \
        /usr/local/share/incusbox/incusbox.conf \
        /etc/incusbox/incusbox.conf \
        "${XDG_CONFIG_HOME:-${HOME}/.config}/incusbox/incusbox.conf" \
        "${HOME}/.incusboxrc"
    do
        # shellcheck disable=SC1090
        if [ -e "${_cf}" ]; then . "$(realpath "${_cf}")"; fi
    done
}
_incusbox_load_config

# ── logging ───────────────────────────────────────────────────────────────────
log()  { printf >&2 '%s\n' "$*"; }
die()  { printf >&2 'Error: %s\n' "$*"; exit 1; }
warn() { printf >&2 'Warning: %s\n' "$*"; }
info() { if [ "${verbose:-0}" -eq 1 ]; then printf >&2 '+ %s\n' "$*"; fi; }

# ── Incus binary resolution ───────────────────────────────────────────────────
# Sets INCUS (the command to invoke) and INCUS_SOCKET (exported when using the
# rootless incus-user socket).
#
# Resolution order:
#   1. rootful=1 and non-root  → "sudo incus", clear INCUS_SOCKET
#   2. non-root + user socket  → "incus", export INCUS_SOCKET to user socket
#   3. otherwise               → "incus", clear INCUS_SOCKET
#
# Callers set rootful=0/1 before sourcing or before calling resolve_incus.
resolve_incus() {
    local _socket="${XDG_RUNTIME_DIR:-/run/user/$(id -ru)}/incus/incus.socket"
    if [ "${rootful:-0}" -eq 1 ] && [ "$(id -ru)" -ne 0 ]; then
        INCUS="sudo incus"
        unset INCUS_SOCKET
    elif [ "$(id -ru)" -ne 0 ] && [ -S "${_socket}" ]; then
        INCUS="incus"
        export INCUS_SOCKET="${_socket}"
    else
        INCUS="incus"
        unset INCUS_SOCKET
    fi
    export INCUS
}

# ── dependency checks ─────────────────────────────────────────────────────────
require_incus() {
    command -v incus >/dev/null 2>&1 \
        || die "'incus' not found in PATH. See https://linuxcontainers.org/incus/docs/main/installing/"
}

require_cmd() {
    local _cmd _missing=""
    for _cmd in "$@"; do
        command -v "${_cmd}" >/dev/null 2>&1 || _missing="${_missing} ${_cmd}"
    done
    if [ -n "${_missing}" ]; then
        die "Missing required commands:${_missing}"
    fi
}

# ── container metadata helpers ────────────────────────────────────────────────
# Read a user.incusbox.* config key from a named container.
# Usage: container_config NAME KEY
container_config() {
    ${INCUS} config get "$1" "user.incusbox.$2" 2>/dev/null || true
}

# Return the lowercase status of a container ("running", "stopped", …)
container_status() {
    ${INCUS} info "$1" 2>/dev/null | awk '/^Status:/ {print tolower($2)}'
}

# ── doctor ────────────────────────────────────────────────────────────────────
incusbox_doctor() {
    local _ok=0 _fail=0

    _chk_cmd() {
        if command -v "$1" >/dev/null 2>&1; then
            printf '  \033[32m✓\033[0m %s\n' "$1"
            _ok=$((_ok + 1))
        else
            printf '  \033[31m✗\033[0m %s — not found\n' "$1"
            _fail=$((_fail + 1))
        fi
    }

    _chk_opt() {
        if command -v "$1" >/dev/null 2>&1; then
            printf '  \033[32m✓\033[0m %s\n' "$1"
        else
            printf '  \033[33m!\033[0m %s — optional, not found\n' "$1"
        fi
    }

    printf 'incusbox doctor\n\n'
    printf 'Required:\n'
    _chk_cmd incus

    printf '\nOptional:\n'
    _chk_opt skopeo
    _chk_opt zfs
    _chk_opt btrfs
    _chk_opt nvidia-smi
    _chk_opt python3
    _chk_opt yq

    printf '\nOptional commands:\n'
    _chk_opt tar
    _chk_opt gzip

    printf '\nIncus socket:\n'
    local _sock="${XDG_RUNTIME_DIR:-/run/user/$(id -ru)}/incus/incus.socket"
    if [ -S "${_sock}" ]; then
        printf '  \033[32m✓\033[0m rootless socket: %s\n' "${_sock}"
    elif [ -S /var/lib/incus/unix.socket ]; then
        printf '  \033[32m✓\033[0m rootful socket: /var/lib/incus/unix.socket\n'
    else
        printf '  \033[31m✗\033[0m no Incus socket found — is incus running?\n'
        _fail=$((_fail + 1))
    fi

    printf '\n'
    if [ "${_fail}" -eq 0 ]; then
        printf '\033[32mAll checks passed (%d ok).\033[0m\n' "${_ok}"
    else
        printf '\033[33m%d check(s) failed, %d passed.\033[0m\n' "${_fail}" "${_ok}"
        return 1
    fi
}
