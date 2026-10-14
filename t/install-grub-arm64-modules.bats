#!/usr/bin/env bats
# Unit tests for install-grub-arm64-modules.sh. apt-get, dpkg-deb and the grub
# image builder are shell functions here, so no archive is read and the modules
# land only under BATS_TEST_TMPDIR.

setup() {
    source "$BATS_TEST_DIRNAME/../install-grub-arm64-modules.sh"
    export TMPDIR=$BATS_TEST_TMPDIR
    CALLS=$BATS_TEST_TMPDIR/calls
    DEST=$BATS_TEST_TMPDIR/dest
    DEB_VERSION=2.12-1ubuntu7
    TOOL_VERSION=2.12-1ubuntu7.3
    DEB_HAS_MODULES=1
}

# Both names, because the loop takes whichever the host has and a developer host
# may carry the real EL one.
grub2-mkimage() {
    echo "grub2-mkimage (GRUB) $TOOL_VERSION"
}

grub-mkimage() {
    echo "grub-mkimage (GRUB) $TOOL_VERSION"
}

apt-get() {
    echo "apt-get $*" >>"$CALLS"
    local list
    list=$(printf '%s\n' "$@" | sed -nE 's/^Dir::Etc::SourceList=//p')
    [ -z "$list" ] || cp "$list" "$BATS_TEST_TMPDIR/sources.list.seen"
    case " $* " in
        *" download "*)
            # apt-get download writes the deb into the working directory.
            : >"grub-efi-arm64-bin_${DEB_VERSION}_arm64.deb"
            ;;
    esac
}

# A deb tree with the module directory, the documentation and the prebuilt images
# the real grub-efi-arm64-bin carries.
dpkg-deb() {
    echo "dpkg-deb $*" >>"$CALLS"
    case $1 in
        -f) echo "$DEB_VERSION" ;;
        -x)
            local out=$3 mod=$3/usr/lib/grub/arm64-efi
            if [[ $out != "$BATS_TEST_TMPDIR"/* ]]; then
                echo "dpkg-deb -x outside the temporary tree: $out" >&2
                return 1
            fi
            mkdir -p "$out/usr/share/doc/grub-efi-arm64-bin"
            : >"$out/usr/share/doc/grub-efi-arm64-bin/copyright"
            (( DEB_HAS_MODULES )) || return 0
            mkdir -p "$mod/monolithic"
            local m
            for m in normal linux tftp efinet; do : >"$mod/$m.mod"; done
            : >"$mod/kernel.img"
            : >"$mod/moddep.lst"
            : >"$mod/monolithic/grubnetaa64.efi"
            ;;
    esac
}

leftover_dirs() {
    find "$BATS_TEST_TMPDIR" -maxdepth 1 -name 'grub-arm64.*' | wc -l
}

@test "an operand is a usage error" {
    run main noble
    [ "$status" -eq 2 ]
    [[ $output == Usage:* ]]
}

@test "an unknown option is a usage error" {
    run main -z
    [ "$status" -eq 2 ]
    [[ $output == *Usage:* ]]
}

@test "the upstream version of a deb version drops the epoch and the revision" {
    [ "$(upstream_version 1:2.12-1ubuntu7.3)" = 2.12 ]
    [ "$(upstream_version 2.06-104)" = 2.06 ]
}

@test "the host GRUB version comes from the image builder on PATH" {
    [ "$(host_grub_version)" = 2.12 ]
}

@test "no image builder on PATH stops the run before any download" {
    host_grub_version() { echo "no grub2-mkimage and no grub-mkimage on PATH" >&2; return 1; }
    run main -d "$DEST" -s noble
    [ "$status" -eq 1 ]
    [ ! -e "$CALLS" ]
}

@test "apt reads the given suite and mirror, with authentication left on" {
    run main -d "$DEST" -s jammy -m https://mirror.example/ubuntu-ports
    [ "$status" -eq 0 ]
    grep -q -- '-o APT::Get::AllowUnauthenticated=false' "$CALLS"
    grep -q -- '-o Acquire::AllowInsecureRepositories=false' "$CALLS"
    grep -q -- '-o APT::Architectures=arm64' "$CALLS"
    grep -q 'apt-get .* update' "$CALLS"
    grep -q 'download grub-efi-arm64-bin' "$CALLS"
    # The suite and the mirror reach apt through its own sources.list, and the host
    # sources and dpkg architectures are never read or changed.
    local list
    list=$(sed -nE 's/.*-o Dir::Etc::SourceList=([^ ]+).*/\1/p' "$CALLS" | head -1)
    [ "$(cat "$BATS_TEST_TMPDIR/sources.list.seen")" = "deb [arch=arm64] https://mirror.example/ubuntu-ports jammy main" ]
    [[ $list == "$BATS_TEST_TMPDIR"/grub-arm64.*/sources.list ]]
}

@test "only the module files are installed, and the temporary tree is removed" {
    run main -d "$DEST" -s noble
    [ "$status" -eq 0 ]
    [[ $output == "PASS: 4 arm64-efi modules of GRUB 2.12 in $DEST, from grub-efi-arm64-bin_2.12-1ubuntu7_arm64.deb" ]]
    [ -f "$DEST/normal.mod" ]
    [ -f "$DEST/kernel.img" ]
    [ -f "$DEST/moddep.lst" ]
    # Not the documentation, and not the prebuilt images of monolithic/.
    [ ! -e "$DEST/usr" ]
    [ ! -e "$DEST/monolithic" ]
    [ ! -e "$DEST/copyright" ]
    [ "$(find "$DEST" -mindepth 1 | wc -l)" -eq 6 ]
    [ "$(leftover_dirs)" -eq 0 ]
}

@test "a deb of another GRUB version than the host tool installs nothing" {
    DEB_VERSION=2.06-1ubuntu1
    run main -d "$DEST" -s noble
    [ "$status" -eq 1 ]
    [[ $output == *"grub-efi-arm64-bin is GRUB 2.06 and the host image builder is GRUB 2.12"* ]]
    [ ! -e "$DEST" ]
    [ "$(leftover_dirs)" -eq 0 ]
}

@test "a deb without the module directory installs nothing" {
    DEB_HAS_MODULES=0
    run main -d "$DEST" -s noble
    [ "$status" -eq 1 ]
    [[ $output == *"carries no usr/lib/grub/arm64-efi"* ]]
    [ ! -e "$DEST" ]
}

@test "a failed apt-get update stops the run before the download" {
    apt-get() {
        echo "apt-get $*" >>"$CALLS"
        case " $* " in *" update "*) return 100 ;; esac
    }
    run main -d "$DEST" -s noble
    [ "$status" -eq 1 ]
    [[ $output == *"apt-get update of https://ports.ubuntu.com/ubuntu-ports noble failed"* ]]
    ! grep -q 'download' "$CALLS"
    [ ! -e "$DEST" ]
}

@test "a download that yields no deb is not reported as a success" {
    apt-get() { echo "apt-get $*" >>"$CALLS"; }
    run main -d "$DEST" -s noble
    [ "$status" -eq 1 ]
    [[ $output == *"apt downloaded no grub-efi-arm64-bin deb"* ]]
    [ ! -e "$DEST" ]
}
