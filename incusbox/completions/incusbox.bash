# bash completion for incusbox
# Source this file or install to /etc/bash_completion.d/incusbox
# or ~/.local/share/bash-completion/completions/incusbox

_incusbox_containers() {
    incus list --format csv 2>/dev/null \
        | awk -F',' '{print $1}' \
        | while read -r name; do
            manager="$(incus config get "${name}" user.manager 2>/dev/null || true)"
            [ "${manager}" = "incusbox" ] && printf '%s\n' "${name}"
        done
}

_incusbox_images() {
    # Offer common OCI shorthand + Incus image server prefixes
    printf '%s\n' \
        "docker:ubuntu:22.04" "docker:ubuntu:24.04" \
        "docker:fedora:40"    "docker:archlinux" \
        "docker:debian:bookworm" "docker:alpine:3.19" \
        "docker:opensuse/leap:15.5" \
        "ghcr:" "quay:" \
        "images:ubuntu/24.04" "images:fedora/40" \
        "images:archlinux"    "images:alpine/3.19" \
        "images:debian/bookworm"
}

_incusbox_storage_pools() {
    incus storage list --format csv 2>/dev/null | awk -F',' '{print $1}'
}

_incusbox() {
    local cur prev words cword
    _init_completion || return

    local commands="create enter list ls rm remove stop upgrade assemble export host-exec setup-rootless version help"

    # Top-level command completion
    if [ "${cword}" -eq 1 ]; then
        # shellcheck disable=SC2207
        COMPREPLY=( $(compgen -W "${commands}" -- "${cur}") )
        return
    fi

    local cmd="${words[1]}"

    case "${cmd}" in
        create)
            local opts="--image --name --hostname --home --home-prefix --volume
                        --additional-flags --additional-packages --init-hooks
                        --pre-init-hooks --init --nvidia --storage-pool
                        --storage-dataset --btrfs-compress --root
                        --unshare-netns --unshare-ipc --unshare-process
                        --unshare-devsys --unshare-groups --unshare-all
                        --pull --yes --dry-run --verbose --version --help"
            case "${prev}" in
                --image|-i)
                    # shellcheck disable=SC2207
                    COMPREPLY=( $(compgen -W "$(_incusbox_images)" -- "${cur}") )
                    return ;;
                --storage-pool)
                    # shellcheck disable=SC2207
                    COMPREPLY=( $(compgen -W "$(_incusbox_storage_pools)" -- "${cur}") )
                    return ;;
                --btrfs-compress)
                    # shellcheck disable=SC2207
                    COMPREPLY=( $(compgen -W "zstd lzo zlib" -- "${cur}") )
                    return ;;
                --home|--home-prefix|--storage-dataset)
                    _filedir -d
                    return ;;
            esac
            # shellcheck disable=SC2207
            COMPREPLY=( $(compgen -W "${opts}" -- "${cur}") )
            ;;

        enter)
            local opts="--user --headless --root --yes --dry-run --verbose --version --help"
            case "${prev}" in
                enter|--user|-u)
                    if [ "${prev}" = "enter" ] || [ "${prev}" = "${cmd}" ]; then
                        # shellcheck disable=SC2207
                        COMPREPLY=( $(compgen -W "$(_incusbox_containers)" -- "${cur}") )
                    fi
                    return ;;
            esac
            # shellcheck disable=SC2207
            COMPREPLY=( $(compgen -W "${opts}" -- "${cur}") )
            ;;

        list|ls)
            # shellcheck disable=SC2207
            COMPREPLY=( $(compgen -W "--root --verbose --version --help" -- "${cur}") )
            ;;

        rm|remove)
            local opts="--force --rm-home --root --yes --verbose --version --help"
            if [[ "${cur}" != -* ]]; then
                # shellcheck disable=SC2207
                COMPREPLY=( $(compgen -W "$(_incusbox_containers)" -- "${cur}") )
                return
            fi
            # shellcheck disable=SC2207
            COMPREPLY=( $(compgen -W "${opts}" -- "${cur}") )
            ;;

        stop)
            local opts="--all --root --verbose --version --help"
            if [[ "${cur}" != -* ]]; then
                # shellcheck disable=SC2207
                COMPREPLY=( $(compgen -W "$(_incusbox_containers)" -- "${cur}") )
                return
            fi
            # shellcheck disable=SC2207
            COMPREPLY=( $(compgen -W "${opts}" -- "${cur}") )
            ;;

        upgrade)
            local opts="--all --root --verbose --version --help"
            if [[ "${cur}" != -* ]]; then
                # shellcheck disable=SC2207
                COMPREPLY=( $(compgen -W "$(_incusbox_containers)" -- "${cur}") )
                return
            fi
            # shellcheck disable=SC2207
            COMPREPLY=( $(compgen -W "${opts}" -- "${cur}") )
            ;;

        assemble)
            local opts="--file --replace --yes --dry-run --verbose --version --help"
            case "${prev}" in
                --file|-f)
                    _filedir yaml
                    return ;;
            esac
            # shellcheck disable=SC2207
            COMPREPLY=( $(compgen -W "${opts}" -- "${cur}") )
            ;;

        export)
            local opts="--app --bin --service --delete --label --extra-flags --sudo --verbose --version --help"
            case "${prev}" in
                --bin|-b)
                    _filedir
                    return ;;
            esac
            # shellcheck disable=SC2207
            COMPREPLY=( $(compgen -W "${opts}" -- "${cur}") )
            ;;

        setup-rootless)
            # shellcheck disable=SC2207
            COMPREPLY=( $(compgen -W "--fix --yes --verbose --version --help" -- "${cur}") )
            ;;

        *)
            # shellcheck disable=SC2207
            COMPREPLY=( $(compgen -W "${commands}" -- "${cur}") )
            ;;
    esac
}

complete -F _incusbox incusbox
