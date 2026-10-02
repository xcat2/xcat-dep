#!/usr/bin/env bats
# Unit tests for verify-xcatsn-install.sh. dnf and rpm are shell functions
# here, so no repository is read and nothing is installed.

setup() {
    source "$BATS_TEST_DIRNAME/../verify-xcatsn-install.sh"
    export TMPDIR=$BATS_TEST_TMPDIR
    CALLS=$BATS_TEST_TMPDIR/calls
    for r in baseos appstream core dep; do
        mkdir -p "$BATS_TEST_TMPDIR/$r/repodata"
    done
    REPOS=("$BATS_TEST_TMPDIR/baseos" "$BATS_TEST_TMPDIR/appstream"
        "$BATS_TEST_TMPDIR/core" "$BATS_TEST_TMPDIR/dep")
    REPOLIST=$(local_repolist)
    INSTALL_RC=0
}

local_repolist() {
    local id
    for id in baseos appstream xcat-core xcat-dep; do
        printf 'Repo-id            : %s\nRepo-baseurl       : file:///repos/%s\n\n' "$id" "$id"
    done
}

dnf() {
    echo "dnf $*" >>"$CALLS"
    case " $* " in
        *" repolist -v "*) echo "$REPOLIST" ;;
        *" install xCATsn "*) return "$INSTALL_RC" ;;
    esac
}

rpm() {
    echo "rpm $*" >>"$CALLS"
    case " $* " in
        *" -qa "*) printf 'bash-5\nxCATsn-2\ngpg-pubkey-1\n' ;;
    esac
}

leftover_dirs() {
    find "$BATS_TEST_TMPDIR" -maxdepth 1 -name 'xcatsn-*' | wc -l
}

@test "a missing release is a usage error" {
    run main -n "${REPOS[@]}"
    [ "$status" -eq 2 ]
    [[ $output == Usage:* ]]
}

@test "three repositories are a usage error" {
    run main -r 10 -n "${REPOS[@]:0:3}"
    [ "$status" -eq 2 ]
    [[ $output == Usage:* ]]
}

@test "no key and no -n is refused" {
    run main -r 10 "${REPOS[@]}"
    [ "$status" -eq 2 ]
    [[ $output == *"give -k KEYFILE"* ]]
}

@test "a URL is not accepted as a repository" {
    run main -r 10 -n "${REPOS[@]:0:3}" https://example.com/xcat-dep
    [ "$status" -eq 2 ]
    [[ $output == *"not a local directory: https://example.com/xcat-dep"* ]]
}

@test "a directory without repodata is not accepted" {
    run main -r 10 -n "${REPOS[@]:0:3}" "$BATS_TEST_TMPDIR"
    [ "$status" -eq 2 ]
    [[ $output == *"no repodata/ in"* ]]
}

@test "four file:// repositories pass the guard" {
    run only_local_repos <<<"$(local_repolist)"
    [ "$status" -eq 0 ]
}

@test "the guard reads the dnf5 field names" {
    run only_local_repos <<<"$(local_repolist | sed 's/^Repo-id  /Repo ID  /; s/^Repo-baseurl/Base URL    /')"
    [ "$status" -eq 0 ]
}

@test "an extra repository fails the guard" {
    run only_local_repos <<<"$(local_repolist; printf 'Repo-id : epel\nRepo-baseurl : file:///epel\n')"
    [ "$status" -eq 1 ]
    [[ $output == *"repositories other than"*"epel"* ]]
}

@test "a remote base URL fails the guard" {
    run only_local_repos <<<"$(local_repolist | sed 's|file:///repos/xcat-dep|https://xcat.org/xcat-dep|')"
    [ "$status" -eq 1 ]
    [[ $output == *"not file://: https://xcat.org/xcat-dep"* ]]
}

@test "a repository without a base URL fails the guard" {
    run only_local_repos <<<"$(local_repolist | grep -v 'file:///repos/appstream')"
    [ "$status" -eq 1 ]
    [[ $output == *"without one base URL"* ]]
}

@test "a metalink fails the guard" {
    run only_local_repos <<<"$(local_repolist; echo 'Repo-metalink : https://mirrors.example/metalink')"
    [ "$status" -eq 1 ]
    [[ $output == *"metalink or mirror list"* ]]
}

@test "dnf sees only the four repositories and no host reposdir" {
    run main -r 9 -k /keys/a -k /keys/b "${REPOS[@]}"
    [ "$status" -eq 0 ]
    grep -q -- "--disablerepo=\* --setopt=reposdir=$BATS_TEST_TMPDIR/xcatsn-repos" "$CALLS"
    grep -q -- "--repofrompath=xcat-dep,file://$BATS_TEST_TMPDIR/dep " "$CALLS"
    grep -q -- "--enablerepo=baseos,appstream,xcat-core,xcat-dep " "$CALLS"
    grep -q -- "--import /keys/a /keys/b" "$CALLS"
    grep -q -- "--setopt=gpgcheck=1" "$CALLS"
    [[ $output == *"PASS: xCATsn installed on EL9"*", 2 packages"* ]]
}

@test "a remote repository stops the run before the install" {
    REPOLIST=$(local_repolist | sed 's|file:///repos/baseos|http://mirror/baseos|')
    run main -r 10 -n "${REPOS[@]}"
    [ "$status" -eq 1 ]
    ! grep -q "install xCATsn" "$CALLS"
}

@test "a failed install fails the check and removes the installroot" {
    INSTALL_RC=1
    run main -r 10 -n "${REPOS[@]}"
    [ "$status" -eq 1 ]
    [[ $output == *"FAIL: dnf install xCATsn returned 1"* ]]
    grep -q "install xCATsn" "$CALLS"
    [ "$(leftover_dirs)" -eq 0 ]
}
