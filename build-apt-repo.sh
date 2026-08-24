#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ -z "${SOURCE_DATE_EPOCH:-}" ] && [ -f "$SCRIPT_DIR/Gitepoch" ]; then
    SOURCE_DATE_EPOCH=$(cat "$SCRIPT_DIR/Gitepoch")
    export SOURCE_DATE_EPOCH
fi

REPO_ROOT="$SCRIPT_DIR"
APT_DIR=""
GPG_KEY_ID="xcat@megware.com"
SKIP_SIGN=0
DRY_RUN=0
GENESIS_RELEASE=""
GENESIS_CHECKSUMS=""
GENESIS_VERIFIER=""
GENESIS_POOL_RELATIVE="pool/main/xcat-genesis-openembedded"
GENESIS_POOL=""
FORCE_UNLOCK=0
HELD_LOCK=""

cleanup() {
    if [[ -n "$GENESIS_CHECKSUMS" ]]; then
        rm -f -- "$GENESIS_CHECKSUMS"
    fi
    if [[ -n "$HELD_LOCK" ]]; then
        rm -f -- "$HELD_LOCK/owner"
        rmdir -- "$HELD_LOCK" 2>/dev/null || true
    fi
}
trap cleanup EXIT

declare -A CODENAME_MAP=(
    [ubuntu22.04]=jammy
    [ubuntu24.04]=noble
    [ubuntu26.04]=resolute
)
ARCHITECTURES=(amd64 ppc64el)

# Versions to build. Populated from positional DIST args; defaults to all of
# CODENAME_MAP when none are given. SUBSET=1 means the user requested a subset
# (so cleanup is scoped to the selected dists instead of wiping the whole repo).
SELECTED_VERS=()
SUBSET=0

usage() {
    cat <<'EOF'
Usage: build-apt-repo.sh [options] [DIST ...]

Generate APT repository metadata from pre-built .deb packages.

Arguments:
  DIST ...               One or more Ubuntu versions to build, e.g. ubuntu24.04.
                         Valid values: ubuntu22.04 ubuntu24.04 ubuntu26.04.
                         When omitted, all three are built (default behavior).
                         Building a subset only touches those dists; other
                         existing dists in the repo are left untouched.

Options:
  --repo-root PATH       xcat-dep repository root (default: script directory)
  --apt-dir PATH         APT output directory (default: <repo-root>/repos/apt)
  --gpg-key-id ID        GPG key ID for signing (default: xcat@megware.com)
  --skip-sign            Skip GPG signing (for testing)
  --genesis-release PATH Publish a verified OpenEmbedded Genesis DEB release for all suites
  --dry-run              Print planned actions without executing
  --force-unlock         Remove a stale <apt-dir>/.lock before acquiring it
  -h, --help             Show this help

Examples:
  build-apt-repo.sh                 # build all dists (default)
  build-apt-repo.sh ubuntu24.04     # build only noble
EOF
}

die() { echo "ERROR: $*" >&2; exit 1; }

step() { echo -e "\n== $* =="; }

run() {
    echo "+ $*"
    if [[ $DRY_RUN -eq 0 ]]; then
        "$@"
    fi
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --repo-root)   REPO_ROOT="$2"; shift 2 ;;
        --apt-dir)     APT_DIR="$2"; shift 2 ;;
        --gpg-key-id)  GPG_KEY_ID="$2"; shift 2 ;;
        --skip-sign)   SKIP_SIGN=1; shift ;;
        --genesis-release) GENESIS_RELEASE="$2"; shift 2 ;;
        --dry-run)     DRY_RUN=1; shift ;;
        --force-unlock) FORCE_UNLOCK=1; shift ;;
        -h|--help)     usage; exit 0 ;;
        -*)            die "Unknown option: $1" ;;
        *)             SELECTED_VERS+=("$1"); SUBSET=1; shift ;;
    esac
done

REPO_ROOT="$(cd "$REPO_ROOT" && pwd)"
APT_DIR="${APT_DIR:-$REPO_ROOT/repos/apt}"
GENESIS_POOL="$APT_DIR/$GENESIS_POOL_RELATIVE"

# Everything from the pool wipe to the signature is one transaction over a shared tree, and
# the packages are verified inside it: a second writer between the verification and
# apt-ftparchive would be indexed and signed unchecked. Hold the tree for the whole run, with
# an atomic mkdir (reliable over NFS, unlike flock) like mockbuild-all.pl does for its output.
acquire_apt_lock() {
    local lock="$APT_DIR/.lock"
    [[ $DRY_RUN -eq 0 ]] || return 0
    mkdir -p -- "$APT_DIR"
    if [[ $FORCE_UNLOCK -eq 1 && -d "$lock" ]]; then
        echo "force-unlock: removing stale lock $lock"
        rm -f -- "$lock/owner"
        rmdir -- "$lock" 2>/dev/null || true
    fi
    if mkdir -- "$lock" 2>/dev/null; then
        HELD_LOCK="$lock"
        printf 'host=%s\npid=%s\nepoch=%s\n' "$(uname -n)" "$$" "$(date +%s)" > "$lock/owner"
        return 0
    fi
    [[ -d "$lock" ]] || die "Cannot create lock $lock"
    die "APT directory $APT_DIR is locked ($lock): $(tr '\n' ' ' < "$lock/owner" 2>/dev/null)
another build-apt-repo.sh run owns it; use a different --apt-dir or --force-unlock if stale."
}
acquire_apt_lock

if [[ -n "$GENESIS_RELEASE" ]]; then
    [[ -d "$GENESIS_RELEASE" ]] || die "Genesis release directory not found: $GENESIS_RELEASE"
    GENESIS_RELEASE="$(cd "$GENESIS_RELEASE" && pwd)"
    GENESIS_VERIFIER="$SCRIPT_DIR/genesis-openembedded/verify-release"
    [[ -x "$GENESIS_VERIFIER" ]] || die "Genesis release verifier not found: $GENESIS_VERIFIER"
fi

# Default to all known versions when no DIST arg was given; otherwise validate
# each requested version against CODENAME_MAP.
if [[ ${#SELECTED_VERS[@]} -eq 0 ]]; then
    SELECTED_VERS=("${!CODENAME_MAP[@]}")
else
    for ver in "${SELECTED_VERS[@]}"; do
        [[ -n "${CODENAME_MAP[$ver]:-}" ]] \
            || die "Unknown DIST '$ver'. Valid: ${!CODENAME_MAP[*]}"
    done
fi
echo "Building dists: ${SELECTED_VERS[*]}"

step "Validating prerequisites"

command -v apt-ftparchive >/dev/null 2>&1 \
    || die "apt-ftparchive not found. Install: sudo apt-get install apt-utils"
command -v gpg >/dev/null 2>&1 \
    || die "gpg not found. Install: sudo apt-get install gnupg"
if [[ -n "$GENESIS_RELEASE" ]]; then
    command -v dpkg-deb >/dev/null 2>&1 \
        || die "dpkg-deb not found. Install: sudo apt-get install dpkg"
    command -v cmp >/dev/null 2>&1 \
        || die "cmp not found. Install: sudo apt-get install diffutils"
    GENESIS_CHECKSUMS=$(mktemp "${TMPDIR:-/tmp}/xcat-genesis-checksums.XXXXXX")
    cp -- "$GENESIS_RELEASE/SHA256SUMS" "$GENESIS_CHECKSUMS"
    "$GENESIS_VERIFIER" --complete --format deb "$GENESIS_RELEASE"
    cmp -s "$GENESIS_CHECKSUMS" "$GENESIS_RELEASE/SHA256SUMS" \
        || die "Genesis release changed during verification"
    [[ $SUBSET -eq 0 ]] \
        || die "--genesis-release updates all suites; omit DIST arguments"
    echo "Genesis release: $GENESIS_RELEASE"
fi

if [[ $SKIP_SIGN -eq 0 ]]; then
    if ! gpg --list-secret-keys "$GPG_KEY_ID" >/dev/null 2>&1; then
        die "Secret key '$GPG_KEY_ID' not in GPG keyring. Import it or use --skip-sign."
    fi
    echo "GPG signing key: $GPG_KEY_ID"
else
    echo "GPG signing: skipped"
fi

for ver in "${SELECTED_VERS[@]}"; do
    src="$APT_DIR/$ver"
    [[ -d "$src" ]] || die "Source directory missing: $src"
    count=$(find "$src" -maxdepth 1 -name '*.deb' | wc -l)
    [[ $count -gt 0 ]] || die "No .deb files in $src"
    echo "Found $count debs in $src"
done

step "Cleaning previous repo metadata"

if [[ $DRY_RUN -eq 0 ]]; then
    if [[ $SUBSET -eq 1 ]]; then
        # Subset build: only remove the selected dists, leave others intact.
        for ver in "${SELECTED_VERS[@]}"; do
            codename="${CODENAME_MAP[$ver]}"
            rm -rf "$APT_DIR/dists/$codename" "$APT_DIR/pool/main/$codename"
        done
        echo "Removed dists/ and pool/ for: ${SELECTED_VERS[*]}"
    else
        rm -rf "$APT_DIR/dists"
        for ver in "${!CODENAME_MAP[@]}"; do
            rm -rf "$APT_DIR/pool/main/${CODENAME_MAP[$ver]}"
        done
        echo "Removed dists/ and suite pools"
    fi
    if [[ -n "$GENESIS_RELEASE" ]]; then
        rm -rf "$GENESIS_POOL"
        echo "Removed the previous shared Genesis pool"
    fi
fi

step "Creating directory structure"

for ver in "${SELECTED_VERS[@]}"; do
    codename="${CODENAME_MAP[$ver]}"
    run mkdir -p "$APT_DIR/pool/main/$codename"
    for arch in "${ARCHITECTURES[@]}"; do
        run mkdir -p "$APT_DIR/dists/$codename/main/binary-$arch"
    done
done
if [[ -n "$GENESIS_RELEASE" ]]; then
    run mkdir -p "$GENESIS_POOL"
fi

step "Populating pool"

copy_deb() {
    local source="$1"
    local destination
    destination="$2/$(basename "$source")"
    if [[ -e "$destination" ]]; then
        cmp -s "$source" "$destination" \
            || die "Package collision with different content: $destination"
        return
    fi
    ln "$source" "$destination" 2>/dev/null || cp "$source" "$destination"
}

copy_genesis_deb() {
    local source="$1"
    local directory="$2"
    local name destination relative
    name=$(basename "$source")
    destination="$directory/$name"
    relative="deb/$name"
    # The pool needs a file of its own. A hard link would let a later write through either
    # path change both the verified release and the published package.
    cp --reflink=auto -- "$source" "$destination" 2>/dev/null \
        || cp -- "$source" "$destination"
    "$GENESIS_VERIFIER" \
        --checksum-file "$GENESIS_CHECKSUMS" \
        --relative-file "$relative" \
        --copied-file "$destination"
}

for ver in "${SELECTED_VERS[@]}"; do
    codename="${CODENAME_MAP[$ver]}"
    src="$APT_DIR/$ver"
    dst="$APT_DIR/pool/main/$codename"
    echo "$ver -> pool/main/$codename/"
    if [[ $DRY_RUN -eq 0 ]]; then
        for deb in "$src"/*.deb; do
            if [[ ${deb##*/} == xcat-genesis-openembedded-*.deb ]]; then
                continue
            fi
            copy_deb "$deb" "$dst"
        done
    fi
done

if [[ -n "$GENESIS_RELEASE" && $DRY_RUN -eq 0 ]]; then
    echo "Genesis release -> $GENESIS_POOL_RELATIVE/"
    for deb in "$GENESIS_RELEASE"/deb/*.deb; do
        copy_genesis_deb "$deb" "$GENESIS_POOL"
    done
fi

# The pool is indexed and the metadata is signed from what is on disk now, not from what
# was copied earlier, so check the packages again here: anything that changed between the
# copy and this point would otherwise be published and signed as verified.
if [[ -n "$GENESIS_RELEASE" && $DRY_RUN -eq 0 ]]; then
    step "Re-verifying pooled Genesis packages"
    for deb in "$GENESIS_RELEASE"/deb/*.deb; do
        name=$(basename "$deb")
        pooled="$GENESIS_POOL/$name"
        "$GENESIS_VERIFIER" \
            --checksum-file "$GENESIS_CHECKSUMS" \
            --relative-file "deb/$name" \
            --copied-file "$pooled"
        echo "Re-verified pooled Genesis package: $pooled"
    done
fi

step "Generating Packages indexes"

for ver in "${SELECTED_VERS[@]}"; do
    codename="${CODENAME_MAP[$ver]}"
    echo "Indexing $codename..."

    if [[ $DRY_RUN -eq 1 ]]; then
        echo "(dry-run: would generate Packages for $codename)"
        continue
    fi

    all_packages=$(
        cd "$APT_DIR"
        apt-ftparchive packages "pool/main/$codename/"
        if [[ -d "$GENESIS_POOL" ]]; then
            apt-ftparchive packages "$GENESIS_POOL_RELATIVE/"
        fi
    )

    for arch in "${ARCHITECTURES[@]}"; do
        pkg_file="$APT_DIR/dists/$codename/main/binary-$arch/Packages"

        echo -n "" > "$pkg_file"

        echo "$all_packages" | awk -v arch="$arch" '
            BEGIN { RS=""; FS="\n"; OFS="\n"; ORS="\n\n" }
            {
                pkg_arch = ""
                for (i = 1; i <= NF; i++) {
                    if ($i ~ /^Architecture:/) {
                        split($i, a, ": ")
                        pkg_arch = a[2]
                    }
                }
                if (pkg_arch == arch || pkg_arch == "all") {
                    print
                }
            }
        ' >> "$pkg_file"

        gzip -9 -k -f -n "$pkg_file"

        pkg_count=$(grep -c '^Package:' "$pkg_file" 2>/dev/null || echo 0)
        echo "  binary-$arch: $pkg_count packages"
    done
done

step "Generating Release files"

for ver in "${SELECTED_VERS[@]}"; do
    codename="${CODENAME_MAP[$ver]}"
    echo "Release for $codename..."

    if [[ $DRY_RUN -eq 1 ]]; then
        echo "(dry-run: would generate Release for $codename)"
        continue
    fi

    apt-ftparchive \
        -o "APT::FTPArchive::Release::Origin=xCAT" \
        -o "APT::FTPArchive::Release::Label=xcat-dep" \
        -o "APT::FTPArchive::Release::Suite=$codename" \
        -o "APT::FTPArchive::Release::Codename=$codename" \
        -o "APT::FTPArchive::Release::Architectures=amd64 ppc64el" \
        -o "APT::FTPArchive::Release::Components=main" \
        -o "APT::FTPArchive::Release::Description=xCAT dependency packages for $ver" \
        release "$APT_DIR/dists/$codename/" \
        > "$APT_DIR/dists/$codename/Release"

    if [ -n "${SOURCE_DATE_EPOCH:-}" ]; then
        deterministic_date=$(date -R -d "@$SOURCE_DATE_EPOCH" --utc)
        sed -i "s/^Date: .*/Date: $deterministic_date/" "$APT_DIR/dists/$codename/Release"
    fi
done

if [[ $SKIP_SIGN -eq 0 ]]; then
    step "Signing Release files"

    for ver in "${SELECTED_VERS[@]}"; do
        codename="${CODENAME_MAP[$ver]}"
        release="$APT_DIR/dists/$codename/Release"

        echo "Signing $codename..."
        if [[ $DRY_RUN -eq 0 ]]; then
            gpg --default-key "$GPG_KEY_ID" \
                --batch --yes --armor \
                --detach-sign \
                -o "$release.gpg" "$release"

            gpg --default-key "$GPG_KEY_ID" \
                --batch --yes --armor \
                --clearsign \
                -o "$APT_DIR/dists/$codename/InRelease" "$release"
        fi
    done
fi

step "Exporting public key"

key_src="$REPO_ROOT/repomd.xml.key"
key_dst="$APT_DIR/xcat-dep.asc"
if [[ -f "$key_src" ]]; then
    run cp "$key_src" "$key_dst"
    echo "Public key -> xcat-dep.asc (from $key_src)"
elif [[ $DRY_RUN -eq 1 ]]; then
    echo "(dry-run: would export $GPG_KEY_ID public key to xcat-dep.asc)"
else
    # No pre-exported key file: export the signing public key straight from the
    # keyring (honors GNUPGHOME), so clients get the matching pubkey.
    if gpg --armor --export "$GPG_KEY_ID" > "$key_dst" 2>/dev/null && [[ -s "$key_dst" ]]; then
        echo "Public key -> xcat-dep.asc (exported $GPG_KEY_ID from keyring)"
    else
        rm -f "$key_dst"
        echo "WARNING: could not export '$GPG_KEY_ID' and $key_src not found; no xcat-dep.asc written"
    fi
fi

step "Summary"

echo ""
echo "APT repository generated at: $APT_DIR"
echo ""
echo "Structure:"
if [[ $DRY_RUN -eq 0 ]]; then
    find "$APT_DIR/dists" -type f | sort | sed "s|$APT_DIR/||"
    echo ""
    pool_count=$(find "$APT_DIR/pool" -name '*.deb' | wc -l)
    echo "Pool: $pool_count .deb files"
fi
echo ""
echo "Example sources.list entries:"
echo "  deb [arch=amd64 signed-by=/etc/apt/keyrings/xcat-dep.asc] http://SERVER/xcat/repos/apt jammy main"
echo "  deb [arch=amd64 signed-by=/etc/apt/keyrings/xcat-dep.asc] http://SERVER/xcat/repos/apt noble main"
echo "  deb [arch=amd64 signed-by=/etc/apt/keyrings/xcat-dep.asc] http://SERVER/xcat/repos/apt resolute main"
echo ""
echo "Client setup:"
echo "  curl -fsSL http://SERVER/xcat/repos/apt/xcat-dep.asc | sudo tee /etc/apt/keyrings/xcat-dep.asc >/dev/null"
echo "  echo 'deb [arch=amd64 signed-by=/etc/apt/keyrings/xcat-dep.asc] http://SERVER/xcat/repos/apt <codename> main' \\"
echo "    | sudo tee /etc/apt/sources.list.d/xcat-dep.list"
echo "  sudo apt-get update"
