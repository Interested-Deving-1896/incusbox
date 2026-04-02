#compdef incusbox
# zsh completion for incusbox
# Install to a directory in $fpath, e.g.:
#   mkdir -p ~/.local/share/zsh/completions
#   cp incusbox.zsh ~/.local/share/zsh/completions/_incusbox
#   echo 'fpath=(~/.local/share/zsh/completions $fpath)' >> ~/.zshrc
#   autoload -Uz compinit && compinit

_incusbox_containers() {
    local containers
    containers=( $(incus list --format csv 2>/dev/null \
        | awk -F',' '{print $1}' \
        | while read -r name; do
            manager="$(incus config get "${name}" user.manager 2>/dev/null || true)"
            [ "${manager}" = "incusbox" ] && printf '%s\n' "${name}"
        done) )
    printf '%s\n' "${containers[@]}"
}

_incusbox_images() {
    local images=(
        "docker\:ubuntu\:22.04:Ubuntu 22.04 LTS (Docker Hub)"
        "docker\:ubuntu\:24.04:Ubuntu 24.04 LTS (Docker Hub)"
        "docker\:fedora\:40:Fedora 40 (Docker Hub)"
        "docker\:archlinux:Arch Linux (Docker Hub)"
        "docker\:debian\:bookworm:Debian Bookworm (Docker Hub)"
        "docker\:alpine\:3.19:Alpine 3.19 (Docker Hub)"
        "ghcr\::GitHub Container Registry"
        "quay\::Quay.io"
        "images\:ubuntu/24.04:Ubuntu 24.04 (Incus images)"
        "images\:fedora/40:Fedora 40 (Incus images)"
        "images\:archlinux:Arch Linux (Incus images)"
        "images\:alpine/3.19:Alpine 3.19 (Incus images)"
        "images\:debian/bookworm:Debian Bookworm (Incus images)"
    )
    printf '%s\n' "${images[@]}"
}

_incusbox_storage_pools() {
    local pools
    pools=( $(incus storage list --format csv 2>/dev/null | awk -F',' '{print $1}') )
    printf '%s\n' "${pools[@]}"
}

_incusbox() {
    local state line
    typeset -A opt_args

    _arguments -C \
        '1: :->command' \
        '*:: :->args' \
        && return 0

    case "${state}" in
        command)
            local commands=(
                'create:Create a new incusbox container'
                'enter:Enter an existing incusbox container'
                'list:List incusbox containers'
                'ls:List incusbox containers (alias)'
                'rm:Remove an incusbox container'
                'remove:Remove an incusbox container (alias)'
                'stop:Stop one or more incusbox containers'
                'upgrade:Upgrade packages inside a container'
                'assemble:Create containers from a declarative YAML file'
                'export:Export an app/binary/service from inside a container'
                'host-exec:Run a host command from inside a container'
                'setup-rootless:Configure rootless incusbox via incus-user'
                'version:Show version'
                'help:Show help'
            )
            _describe 'incusbox commands' commands
            ;;

        args)
            case "${line[1]}" in
                create)
                    _arguments \
                        {-i,--image}'[Image to use]:image:->images' \
                        {-n,--name}'[Container name]:name' \
                        '--hostname[Hostname inside container]:hostname' \
                        {-H,--home}'[Custom home directory]:directory:_files -/' \
                        '--home-prefix[Prefix for per-container homes]:directory:_files -/' \
                        '--volume[Additional bind mount (SRC\:DST[\:ro])]:volume' \
                        {-a,--additional-flags}'[Extra flags for incus launch]:flags' \
                        '--additional-packages[Packages to install at init]:packages' \
                        '--init-hooks[Commands run after container init]:command' \
                        '--pre-init-hooks[Commands run before container init]:command' \
                        {-I,--init}'[Use init system (systemd) inside container]' \
                        '--nvidia[Enable NVIDIA GPU passthrough]' \
                        '--storage-pool[Incus storage pool]:pool:->pools' \
                        '--storage-dataset[ZFS dataset prefix]:dataset:_files -/' \
                        '--btrfs-compress[Btrfs compression algorithm]:algo:(zstd lzo zlib)' \
                        {-r,--root}'[Run as root (rootful container)]' \
                        '--unshare-netns[Do not share host network namespace]' \
                        '--unshare-ipc[Do not share host IPC namespace]' \
                        '--unshare-process[Do not share host PID namespace]' \
                        '--unshare-devsys[Do not share /dev and /sys]' \
                        '--unshare-groups[Do not forward supplementary groups]' \
                        '--unshare-all[Enable all unshare flags]' \
                        {-p,--pull}'[Always pull image even if cached]' \
                        {-Y,--yes}'[Non-interactive]' \
                        {-d,--dry-run}'[Print commands without executing]' \
                        {-v,--verbose}'[Show verbose output]' \
                        {-V,--version}'[Show version]' \
                        {-h,--help}'[Show help]'
                    case "${state}" in
                        images) _describe 'images' "$(_incusbox_images)" ;;
                        pools)  _values 'pools' $(_incusbox_storage_pools) ;;
                    esac
                    ;;

                enter)
                    _arguments \
                        '1:container:->containers' \
                        {-u,--user}'[Run as USER inside container]:user:_users' \
                        {-H,--headless}'[Do not allocate a TTY]' \
                        {-r,--root}'[Use rootful incus]' \
                        {-Y,--yes}'[Non-interactive]' \
                        {-d,--dry-run}'[Print commands without executing]' \
                        {-v,--verbose}'[Show verbose output]' \
                        {-V,--version}'[Show version]' \
                        {-h,--help}'[Show help]' \
                        '--:command to run inside container:_command_names'
                    case "${state}" in
                        containers) _values 'containers' $(_incusbox_containers) ;;
                    esac
                    ;;

                list|ls)
                    _arguments \
                        {-r,--root}'[List rootful containers]' \
                        {-v,--verbose}'[Show verbose output]' \
                        {-V,--version}'[Show version]' \
                        {-h,--help}'[Show help]'
                    ;;

                rm|remove)
                    _arguments \
                        '*:container:->containers' \
                        {-f,--force}'[Force removal even if running]' \
                        '--rm-home[Also remove the container home directory]' \
                        {-r,--root}'[Use rootful incus]' \
                        {-Y,--yes}'[Non-interactive]' \
                        {-v,--verbose}'[Show verbose output]' \
                        {-V,--version}'[Show version]' \
                        {-h,--help}'[Show help]'
                    case "${state}" in
                        containers) _values 'containers' $(_incusbox_containers) ;;
                    esac
                    ;;

                stop)
                    _arguments \
                        '*:container:->containers' \
                        {-a,--all}'[Stop all running incusbox containers]' \
                        {-r,--root}'[Use rootful incus]' \
                        {-v,--verbose}'[Show verbose output]' \
                        {-V,--version}'[Show version]' \
                        {-h,--help}'[Show help]'
                    case "${state}" in
                        containers) _values 'containers' $(_incusbox_containers) ;;
                    esac
                    ;;

                upgrade)
                    _arguments \
                        '*:container:->containers' \
                        {-a,--all}'[Upgrade all incusbox containers]' \
                        {-r,--root}'[Use rootful incus]' \
                        {-v,--verbose}'[Show verbose output]' \
                        {-V,--version}'[Show version]' \
                        {-h,--help}'[Show help]'
                    case "${state}" in
                        containers) _values 'containers' $(_incusbox_containers) ;;
                    esac
                    ;;

                assemble)
                    _arguments \
                        {-f,--file}'[YAML file describing containers]:file:_files -g "*.yaml *.yml"' \
                        '--replace[Remove and recreate existing containers]' \
                        {-Y,--yes}'[Non-interactive]' \
                        {-d,--dry-run}'[Print commands without executing]' \
                        {-v,--verbose}'[Show verbose output]' \
                        {-V,--version}'[Show version]' \
                        {-h,--help}'[Show help]'
                    ;;

                export)
                    _arguments \
                        {-a,--app}'[Export a .desktop application]:app' \
                        {-b,--bin}'[Export a binary]:binary:_files' \
                        {-s,--service}'[Export a systemd user service]:service' \
                        {-d,--delete}'[Remove a previously exported entry]' \
                        '--label[Custom label suffix]:label' \
                        '--extra-flags[Extra flags for the wrapper command]:flags' \
                        '--sudo[Prefix wrapper command with sudo]' \
                        {-v,--verbose}'[Show verbose output]' \
                        {-V,--version}'[Show version]' \
                        {-h,--help}'[Show help]'
                    ;;

                setup-rootless)
                    _arguments \
                        '--fix[Attempt to automatically fix detected issues]' \
                        {-Y,--yes}'[Non-interactive (implies --fix)]' \
                        {-v,--verbose}'[Show verbose output]' \
                        {-V,--version}'[Show version]' \
                        {-h,--help}'[Show help]'
                    ;;
            esac
            ;;
    esac
}

_incusbox "$@"
