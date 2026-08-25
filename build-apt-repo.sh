#!/bin/bash
set -euo pipefail
shopt -s nullglob

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
GENESIS_STAGE_RELATIVE=""
GENESIS_STAGE=""
PACKAGE_TEMPORARY=""
KEY_TEMPORARY=""
TRANSACTION_ROOT=""
METADATA_ROOT=""
FORCE_UNLOCK=0
HELD_LOCK=""
PUBLICATION_COMMITTED=0
declare -A GENESIS_EXPECTED=()
declare -A SUITE_EXPECTED=()
declare -A SUITE_STAGE=()
declare -a PUBLISHED_DESTINATIONS=()
declare -a PUBLISHED_BACKUPS=()

cleanup() {
    if [[ $PUBLICATION_COMMITTED -eq 0 ]]; then
        local index destination backup
        for ((index=${#PUBLISHED_DESTINATIONS[@]} - 1; index >= 0; index--)); do
            destination="${PUBLISHED_DESTINATIONS[$index]}"
            backup="${PUBLISHED_BACKUPS[$index]}"
            rm -rf -- "$destination"
            if [[ -n "$backup" && -d "$backup" ]]; then
                mv -- "$backup" "$destination"
            fi
        done
    fi
    if [[ -n "$GENESIS_CHECKSUMS" ]]; then
        rm -f -- "$GENESIS_CHECKSUMS"
    fi
    if [[ -n "$TRANSACTION_ROOT" && -d "$TRANSACTION_ROOT" ]]; then
        rm -rf -- "$TRANSACTION_ROOT"
    fi
    if [[ -n "$PACKAGE_TEMPORARY" ]]; then
        rm -f -- "$PACKAGE_TEMPORARY"
    fi
    if [[ -n "$KEY_TEMPORARY" ]]; then
        rm -f -- "$KEY_TEMPORARY"
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

# Versions to build. Positional DIST arguments select a subset. With no DIST
# argument, metadata is rebuilt for every known suite.
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

# Publication is one transaction over a shared tree. The lock also covers verification, so a
# second writer cannot replace a package between verification and metadata generation. mkdir
# is used because it remains reliable when the repository is stored on NFS.
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

step "Preparing repository transaction"

for ver in "${SELECTED_VERS[@]}"; do
    codename="${CODENAME_MAP[$ver]}"
    echo "$ver -> pool/main/$codename/"
done

if [[ $DRY_RUN -eq 0 ]]; then
    mkdir -p "$APT_DIR"
    TRANSACTION_ROOT=$(mktemp -d "$APT_DIR/.xcat-apt.XXXXXX")
    METADATA_ROOT="$TRANSACTION_ROOT/dists"
    for ver in "${SELECTED_VERS[@]}"; do
        codename="${CODENAME_MAP[$ver]}"
        SUITE_STAGE["$codename"]="$TRANSACTION_ROOT/pool/main/$codename"
        mkdir -p "${SUITE_STAGE[$codename]}"
        for arch in "${ARCHITECTURES[@]}"; do
            mkdir -p "$METADATA_ROOT/$codename/main/binary-$arch"
        done
    done
fi
if [[ -n "$GENESIS_RELEASE" && $DRY_RUN -eq 0 ]]; then
    GENESIS_STAGE="$TRANSACTION_ROOT/pool/main/xcat-genesis-openembedded"
    mkdir -p "$GENESIS_STAGE"
    GENESIS_STAGE_RELATIVE=${GENESIS_STAGE#"$APT_DIR/"}
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
    cp --reflink=auto -- "$source" "$destination" 2>/dev/null \
        || cp -- "$source" "$destination"
}

copy_genesis_deb() {
    local source="$1"
    local directory="$2"
    local name destination relative
    name=$(basename "$source")
    destination="$directory/$name"
    relative="deb/$name"
    if [[ -e "$destination" ]]; then
        cmp -s "$source" "$destination" \
            || die "Package collision with different content: $destination"
        return
    fi
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
    dst="${SUITE_STAGE[$codename]:-}"
    if [[ $DRY_RUN -eq 0 ]]; then
        for deb in "$src"/*.deb; do
            if [[ ${deb##*/} == xcat-genesis-openembedded-*.deb ]]; then
                continue
            fi
            SUITE_EXPECTED["$codename/${deb##*/}"]=1
            copy_deb "$deb" "$dst"
        done
    fi
done

if [[ -n "$GENESIS_RELEASE" && $DRY_RUN -eq 0 ]]; then
    echo "Genesis release -> staged shared pool"
    for deb in "$GENESIS_RELEASE"/deb/*.deb; do
        copy_genesis_deb "$deb" "$GENESIS_STAGE"
    done
fi

# The pool is indexed and the metadata is signed from what is on disk now, not from what
# was copied earlier, so check the packages again here: anything that changed between the
# copy and this point would otherwise be published and signed as verified.
if [[ -n "$GENESIS_RELEASE" && $DRY_RUN -eq 0 ]]; then
    step "Re-verifying pooled Genesis packages"
    for deb in "$GENESIS_RELEASE"/deb/*.deb; do
        name=$(basename "$deb")
        GENESIS_EXPECTED["$name"]=1
        pooled="$GENESIS_STAGE/$name"
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
        suite_stage_relative=${SUITE_STAGE[$codename]#"$APT_DIR/"}
        apt-ftparchive packages "$suite_stage_relative/" \
            | sed "s|^Filename: $suite_stage_relative/|Filename: pool/main/$codename/|"
        if [[ -n "$GENESIS_STAGE_RELATIVE" ]]; then
            apt-ftparchive packages "$GENESIS_STAGE_RELATIVE/" \
                | sed "s|^Filename: $GENESIS_STAGE_RELATIVE/|Filename: $GENESIS_POOL_RELATIVE/|"
        elif [[ -d "$GENESIS_POOL" ]]; then
            apt-ftparchive packages "$GENESIS_POOL_RELATIVE/"
        fi
    )

    for arch in "${ARCHITECTURES[@]}"; do
        pkg_file="$METADATA_ROOT/$codename/main/binary-$arch/Packages"

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
        release "$METADATA_ROOT/$codename/" \
        > "$METADATA_ROOT/$codename/Release"

    if [ -n "${SOURCE_DATE_EPOCH:-}" ]; then
        deterministic_date=$(date -R -d "@$SOURCE_DATE_EPOCH" --utc)
        sed -i "s/^Date: .*/Date: $deterministic_date/" "$METADATA_ROOT/$codename/Release"
    fi
done

if [[ $SKIP_SIGN -eq 0 ]]; then
    step "Signing Release files"

    for ver in "${SELECTED_VERS[@]}"; do
        codename="${CODENAME_MAP[$ver]}"
        release="$METADATA_ROOT/$codename/Release"

        echo "Signing $codename..."
        if [[ $DRY_RUN -eq 0 ]]; then
            gpg --default-key "$GPG_KEY_ID" \
                --batch --yes --armor \
                --detach-sign \
                -o "$release.gpg" "$release"

            gpg --default-key "$GPG_KEY_ID" \
                --batch --yes --armor \
                --clearsign \
                -o "$METADATA_ROOT/$codename/InRelease" "$release"
        fi
    done
fi

step "Exporting public key"

key_src="$REPO_ROOT/repomd.xml.key"
key_dst="$APT_DIR/xcat-dep.asc"
if [[ -f "$key_src" ]]; then
    if [[ $DRY_RUN -eq 1 ]]; then
        echo "+ cp $key_src $key_dst"
    else
        KEY_TEMPORARY=$(mktemp "$APT_DIR/.xcat-key.XXXXXX")
        cp -- "$key_src" "$KEY_TEMPORARY"
        mv -- "$KEY_TEMPORARY" "$key_dst"
        KEY_TEMPORARY=""
    fi
    echo "Public key -> xcat-dep.asc (from $key_src)"
elif [[ $DRY_RUN -eq 1 ]]; then
    echo "(dry-run: would export $GPG_KEY_ID public key to xcat-dep.asc)"
else
    # No pre-exported key file: export the signing public key straight from the
    # keyring (honors GNUPGHOME), so clients get the matching pubkey.
    KEY_TEMPORARY=$(mktemp "$APT_DIR/.xcat-key.XXXXXX")
    if gpg --armor --export "$GPG_KEY_ID" > "$KEY_TEMPORARY" 2>/dev/null \
        && [[ -s "$KEY_TEMPORARY" ]]; then
        mv -- "$KEY_TEMPORARY" "$key_dst"
        KEY_TEMPORARY=""
        echo "Public key -> xcat-dep.asc (exported $GPG_KEY_ID from keyring)"
    else
        rm -f "$KEY_TEMPORARY"
        KEY_TEMPORARY=""
        echo "WARNING: could not export '$GPG_KEY_ID' and $key_src not found; no xcat-dep.asc written"
    fi
fi

publish_package() {
    local source="$1"
    local destination
    local genesis_relative="${3:-}"
    destination="$2/$(basename "$source")"
    mkdir -p -- "$2"
    if [[ -e "$destination" ]]; then
        cmp -s "$source" "$destination" \
            || die "Package collision with different content: $destination"
        return
    fi
    PACKAGE_TEMPORARY=$(mktemp "$2/.xcat-deploy.XXXXXX")
    cp --reflink=auto -- "$source" "$PACKAGE_TEMPORARY" 2>/dev/null \
        || cp -- "$source" "$PACKAGE_TEMPORARY"
    if [[ -n "$genesis_relative" ]]; then
        "$GENESIS_VERIFIER" \
            --checksum-file "$GENESIS_CHECKSUMS" \
            --relative-file "$genesis_relative" \
            --copied-file "$PACKAGE_TEMPORARY"
    fi
    mv -- "$PACKAGE_TEMPORARY" "$destination"
    PACKAGE_TEMPORARY=""
}

publish_metadata() {
    local source="$1"
    local destination="$2"
    local backup=""
    mkdir -p -- "$(dirname "$destination")"
    if [[ -e "$destination" ]]; then
        backup="$(dirname "$destination")/.${destination##*/}.previous.$$"
        rm -rf -- "$backup"
        mv -- "$destination" "$backup"
    fi
    PUBLISHED_DESTINATIONS+=("$destination")
    PUBLISHED_BACKUPS+=("$backup")
    mv -- "$source" "$destination"
}

if [[ $DRY_RUN -eq 0 ]]; then
    step "Publishing packages"
    for ver in "${SELECTED_VERS[@]}"; do
        codename="${CODENAME_MAP[$ver]}"
        for deb in "${SUITE_STAGE[$codename]}"/*.deb; do
            publish_package "$deb" "$APT_DIR/pool/main/$codename"
        done
    done
    if [[ -n "$GENESIS_RELEASE" ]]; then
        for deb in "$GENESIS_STAGE"/*.deb; do
            publish_package "$deb" "$GENESIS_POOL" "deb/${deb##*/}"
        done
    fi

    step "Publishing repository metadata"
    for ver in "${SELECTED_VERS[@]}"; do
        codename="${CODENAME_MAP[$ver]}"
        publish_metadata "$METADATA_ROOT/$codename" "$APT_DIR/dists/$codename"
    done
    PUBLICATION_COMMITTED=1
    for backup in "${PUBLISHED_BACKUPS[@]}"; do
        [[ -z "$backup" ]] || rm -rf -- "$backup"
    done

    step "Retiring previous packages"
    for ver in "${SELECTED_VERS[@]}"; do
        codename="${CODENAME_MAP[$ver]}"
        for deb in "$APT_DIR/pool/main/$codename"/*.deb; do
            [[ -e "$deb" ]] || continue
            name=$(basename "$deb")
            [[ -n "${SUITE_EXPECTED[$codename/$name]:-}" ]] || rm -f -- "$deb"
        done
    done
fi

if [[ -n "$GENESIS_RELEASE" && $DRY_RUN -eq 0 ]]; then
    for deb in "$GENESIS_POOL"/*.deb; do
        [[ -e "$deb" ]] || continue
        name=$(basename "$deb")
        [[ -n "${GENESIS_EXPECTED[$name]:-}" ]] || rm -f -- "$deb"
    done
fi

if [[ $DRY_RUN -eq 0 ]]; then
    rm -rf -- "$TRANSACTION_ROOT"
    TRANSACTION_ROOT=""
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
