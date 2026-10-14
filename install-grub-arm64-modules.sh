#!/bin/bash
# Install the arm64-efi GRUB modules, so a host grub-mkimage can build the AArch64
# network loader of grub2-xcat.spec. Ubuntu ships them only in grub-efi-arm64-bin,
# which is Architecture: arm64 and does not install on an amd64 host. The deb is read
# through apt's signed metadata, unpacked in a temporary directory, and only the
# module files are copied out.
#
# grub-mkimage embeds kernel.img and resolves moddep.lst from the module directory,
# so the modules must come from the GRUB version of the host tool.

usage() {
    cat <<'EOF'
Usage: install-grub-arm64-modules.sh [-d DESTDIR] [-s SUITE] [-m MIRROR]

  -d DESTDIR   where the modules go (default /usr/lib/grub/arm64-efi)
  -s SUITE     suite to read (default: VERSION_CODENAME of /etc/os-release)
  -m MIRROR    apt mirror (default https://ports.ubuntu.com/ubuntu-ports)

apt verifies the suite InRelease signature with the host keyring, and the deb hash
against that signed index. The deb is unpacked under ${TMPDIR:-/tmp} and removed on
exit. Nothing else from it is installed.
EOF
}

PACKAGE=grub-efi-arm64-bin
MODULE_PATH=usr/lib/grub/arm64-efi
MIRROR_DEFAULT=https://ports.ubuntu.com/ubuntu-ports

# Prints the GRUB upstream version of the host image builder, e.g. 2.12.
# EL names the tool grub2-mkimage and Debian names it grub-mkimage.
host_grub_version() {
    local tool out
    for tool in grub2-mkimage grub-mkimage; do
        command -v "$tool" >/dev/null 2>&1 || continue
        out=$("$tool" --version 2>/dev/null) || continue
        # "grub-mkimage (GRUB) 2.12-1ubuntu7.3"
        out=${out##* }
        echo "${out%%-*}"
        return 0
    done
    echo "no grub2-mkimage and no grub-mkimage on PATH" >&2
    return 1
}

# The upstream version of a deb version: no epoch, no distribution revision.
upstream_version() {
    local v=${1#*:}
    echo "${v%%-*}"
}

# apt-get against a private state tree, so the host dpkg architecture and the host
# sources stay as they are. An unsigned or stale index fails here.
apt_get() {
    local root=$1
    shift
    apt-get \
        -o Dir::State="$root/state" \
        -o Dir::State::status="$root/status" \
        -o Dir::Cache="$root/cache" \
        -o Dir::Etc::SourceList="$root/sources.list" \
        -o Dir::Etc::SourceParts="$root/none" \
        -o Dir::Etc::Preferences="$root/none/preferences" \
        -o Dir::Etc::PreferencesParts="$root/none" \
        -o APT::Architecture=arm64 \
        -o APT::Architectures=arm64 \
        -o APT::Sandbox::User=root \
        -o Acquire::AllowInsecureRepositories=false \
        -o APT::Get::AllowUnauthenticated=false \
        "$@"
}

main() {
    local dest=/usr/lib/grub/arm64-efi suite='' mirror=$MIRROR_DEFAULT opt
    OPTIND=1
    while getopts 'd:s:m:h' opt; do
        case $opt in
            d) dest=$OPTARG ;;
            s) suite=$OPTARG ;;
            m) mirror=$OPTARG ;;
            h) usage; return 0 ;;
            *) usage >&2; return 2 ;;
        esac
    done
    shift $((OPTIND - 1))
    if (( $# != 0 )); then
        usage >&2
        return 2
    fi
    if [[ -z $suite ]]; then
        suite=$(. /etc/os-release 2>/dev/null && echo "$VERSION_CODENAME")
    fi
    if [[ -z $suite ]]; then
        echo "no suite: /etc/os-release names no VERSION_CODENAME, give -s" >&2
        return 2
    fi

    local want
    want=$(host_grub_version) || return 1

    local root
    root=$(mktemp -d "${TMPDIR:-/tmp}/grub-arm64.XXXXXX") || return 1
    # shellcheck disable=SC2064
    trap "rm -rf '$root'" EXIT
    mkdir -p "$root/state/lists/partial" "$root/cache/archives/partial" "$root/none" "$root/deb" || return 1
    : > "$root/status"
    printf 'deb [arch=arm64] %s %s main\n' "$mirror" "$suite" > "$root/sources.list" || return 1

    if ! apt_get "$root" update; then
        echo "FAIL: apt-get update of $mirror $suite failed" >&2
        return 1
    fi
    if ! (cd "$root/deb" && apt_get "$root" download "$PACKAGE"); then
        echo "FAIL: apt-get download $PACKAGE from $suite failed" >&2
        return 1
    fi

    local deb
    deb=$(find "$root/deb" -maxdepth 1 -name "${PACKAGE}_*_arm64.deb" | sort | head -1)
    if [[ -z $deb ]]; then
        echo "FAIL: apt downloaded no $PACKAGE deb" >&2
        return 1
    fi

    local got
    got=$(dpkg-deb -f "$deb" Version) || return 1
    got=$(upstream_version "$got")
    if [[ $got != "$want" ]]; then
        echo "FAIL: $PACKAGE is GRUB $got and the host image builder is GRUB $want" >&2
        return 1
    fi

    dpkg-deb -x "$deb" "$root/x" || return 1
    if [[ ! -d $root/x/$MODULE_PATH ]]; then
        echo "FAIL: $PACKAGE carries no $MODULE_PATH" >&2
        return 1
    fi

    # The modules, moddep.lst and kernel.img, and none of the documentation or the
    # prebuilt images under monolithic/ that the deb also carries.
    install -d "$dest" || return 1
    find "$root/x/$MODULE_PATH" -maxdepth 1 -type f -exec install -m 0644 -t "$dest" {} + || return 1

    local count
    count=$(find "$dest" -maxdepth 1 -name '*.mod' | wc -l)
    if (( count == 0 )) || [[ ! -f $dest/kernel.img || ! -f $dest/moddep.lst ]]; then
        echo "FAIL: $dest has no modules, no kernel.img or no moddep.lst" >&2
        return 1
    fi
    echo "PASS: $count arm64-efi modules of GRUB $got in $dest, from ${deb##*/}"
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
    main "$@"
fi
