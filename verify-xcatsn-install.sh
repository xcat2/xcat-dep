#!/bin/bash
# Install xCATsn into an empty installroot from four local repositories only:
# BaseOS, AppStream, xcat-core and xcat-dep. This is the repository set of an
# air-gapped EL service node. Nothing is installed on the host.

usage() {
    cat <<'EOF'
Usage: verify-xcatsn-install.sh -r RELEASE [-k KEYFILE]... [-n] BASEOS APPSTREAM XCAT_CORE XCAT_DEP

  -r RELEASE   EL major release of the repositories (8, 9, 10)
  -k KEYFILE   GPG public key to trust; repeat for each key
  -n           do not check package signatures
  BASEOS ...   local repository directories, each with a repodata/ subdirectory

Give at least one -k, or -n. The installroot is made under ${TMPDIR:-/var/tmp}
and removed on exit. The rpm of an EL10 host rejects the AlmaLinux 8 key, which
has SHA-1 bindings. For EL8, point RPM_SEQUOIA_CRYPTO_POLICY at a policy that
sets sha1.second_preimage_resistance = "always".
EOF
}

REPO_IDS=(baseos appstream xcat-core xcat-dep)

# Prints the file:// URL of a local repository directory.
repo_url() {
    local dir=$1
    if [[ $dir == *://* ]]; then
        echo "not a local directory: $dir" >&2
        return 1
    fi
    if [[ ! -d $dir/repodata ]]; then
        echo "no repodata/ in $dir" >&2
        return 1
    fi
    echo "file://$(cd "$dir" && pwd -P)"
}

# Reads 'dnf repolist -v' output. Fails unless the enabled repositories are
# exactly REPO_IDS and every one of them has a file:// base URL only.
only_local_repos() {
    local out ids urls bad
    out=$(cat)
    ids=$(sed -nE 's/^(Repo-id|Repo ID) *: *([^ ]+).*/\2/p' <<<"$out" | sort | tr '\n' ' ')
    if [[ $ids != "$(printf '%s\n' "${REPO_IDS[@]}" | sort | tr '\n' ' ')" ]]; then
        echo "dnf loaded repositories other than ${REPO_IDS[*]}: $ids" >&2
        return 1
    fi
    if grep -qE '^(Repo-metalink|Repo-mirrors|Metalink|Mirrors) *:' <<<"$out"; then
        echo "dnf loaded a metalink or mirror list" >&2
        return 1
    fi
    urls=$(sed -nE 's/^(Repo-baseurl|Base URL) *: *//p' <<<"$out")
    if [[ $(grep -c . <<<"$urls") -ne ${#REPO_IDS[@]} ]]; then
        echo "dnf reported a repository without one base URL" >&2
        return 1
    fi
    bad=$(grep -vE '^file://[^ ,]+$' <<<"$urls")
    if [[ -n $bad ]]; then
        echo "dnf loaded a repository that is not file://: $bad" >&2
        return 1
    fi
    echo "repositories:" $urls
}

main() {
    local release='' nogpg=0 keys=() opt
    OPTIND=1
    while getopts 'r:k:nh' opt; do
        case $opt in
            r) release=$OPTARG ;;
            k) keys+=("$OPTARG") ;;
            n) nogpg=1 ;;
            h) usage; return 0 ;;
            *) usage >&2; return 2 ;;
        esac
    done
    shift $((OPTIND - 1))
    if [[ ! $release =~ ^[0-9]+$ || $# -ne 4 ]]; then
        usage >&2
        return 2
    fi
    if (( nogpg == 0 && ${#keys[@]} == 0 )); then
        echo "give -k KEYFILE for each repository key, or -n" >&2
        return 2
    fi

    local i url args=()
    for i in 0 1 2 3; do
        url=$(repo_url "${@:i+1:1}") || return 2
        args+=("--repofrompath=${REPO_IDS[i]},$url")
    done

    local root empty
    root=$(mktemp -d "${TMPDIR:-/var/tmp}/xcatsn-root.XXXXXX") || return 1
    empty=$(mktemp -d "${TMPDIR:-/var/tmp}/xcatsn-repos.XXXXXX") || { rm -rf "$root"; return 1; }
    # shellcheck disable=SC2064
    trap "rm -rf '$root' '$empty'" EXIT

    args=(--installroot="$root" --releasever="$release" -y
        --disablerepo='*' --setopt=reposdir="$empty"
        --setopt=module_platform_id="platform:el$release"
        --setopt=install_weak_deps=False
        # EL8 packages carry file dependencies outside primary.xml. dnf 4.19 and later skip filelists.
        --setopt=optional_metadata_types=filelists
        "${args[@]}" --enablerepo="$(IFS=,; echo "${REPO_IDS[*]}")")
    if (( nogpg )); then
        args+=(--nogpgcheck)
    else
        # dnf checks package signatures against the keys in the installroot rpmdb.
        rpm --root "$root" --initdb || return 1
        rpm --root "$root" --import "${keys[@]}" || return 1
        args+=(--setopt=gpgcheck=1)
    fi

    local repolist rc count
    repolist=$(dnf "${args[@]}" repolist -v) || { echo "FAIL: dnf repolist failed" >&2; return 1; }
    only_local_repos <<<"$repolist" || return 1

    dnf "${args[@]}" install xCATsn
    rc=$?
    if (( rc != 0 )); then
        echo "FAIL: dnf install xCATsn returned $rc" >&2
        return 1
    fi
    count=$(rpm --root "$root" -qa | grep -cv '^gpg-pubkey-')
    echo "PASS: xCATsn installed on EL$release from ${REPO_IDS[*]} only, $count packages"
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
    main "$@"
fi
