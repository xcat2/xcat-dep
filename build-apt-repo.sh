#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ -z "${SOURCE_DATE_EPOCH:-}" ] && [ -f "$SCRIPT_DIR/Gitepoch" ]; then
    export SOURCE_DATE_EPOCH=$(cat "$SCRIPT_DIR/Gitepoch")
fi

REPO_ROOT="$SCRIPT_DIR"
APT_DIR=""
GPG_KEY_ID="xcat@megware.com"
SKIP_SIGN=0
DRY_RUN=0

declare -A CODENAME_MAP=(
    [ubuntu22.04]=jammy
    [ubuntu24.04]=noble
    [ubuntu26.04]=resolute
)
ARCHITECTURES=(amd64 ppc64el)

usage() {
    cat <<'EOF'
Usage: build-apt-repo.sh [options]

Generate APT repository metadata from pre-built .deb packages.

Options:
  --repo-root PATH       xcat-dep repository root (default: script directory)
  --apt-dir PATH         APT output directory (default: <repo-root>/repos/apt)
  --gpg-key-id ID        GPG key ID for signing (default: xcat@megware.com)
  --skip-sign            Skip GPG signing (for testing)
  --dry-run              Print planned actions without executing
  -h, --help             Show this help
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
        --dry-run)     DRY_RUN=1; shift ;;
        -h|--help)     usage; exit 0 ;;
        *)             die "Unknown option: $1" ;;
    esac
done

REPO_ROOT="$(cd "$REPO_ROOT" && pwd)"
APT_DIR="${APT_DIR:-$REPO_ROOT/repos/apt}"

step "Validating prerequisites"

command -v apt-ftparchive >/dev/null 2>&1 \
    || die "apt-ftparchive not found. Install: sudo apt-get install apt-utils"
command -v gpg >/dev/null 2>&1 \
    || die "gpg not found. Install: sudo apt-get install gnupg"

if [[ $SKIP_SIGN -eq 0 ]]; then
    if ! gpg --list-secret-keys "$GPG_KEY_ID" >/dev/null 2>&1; then
        die "Secret key '$GPG_KEY_ID' not in GPG keyring. Import it or use --skip-sign."
    fi
    echo "GPG signing key: $GPG_KEY_ID"
else
    echo "GPG signing: skipped"
fi

for ver in "${!CODENAME_MAP[@]}"; do
    src="$APT_DIR/$ver"
    [[ -d "$src" ]] || die "Source directory missing: $src"
    count=$(find "$src" -maxdepth 1 -name '*.deb' | wc -l)
    [[ $count -gt 0 ]] || die "No .deb files in $src"
    echo "Found $count debs in $src"
done

step "Cleaning previous repo metadata"

if [[ $DRY_RUN -eq 0 ]]; then
    rm -rf "$APT_DIR/dists" "$APT_DIR/pool"
fi
echo "Removed dists/ and pool/"

step "Creating directory structure"

for ver in "${!CODENAME_MAP[@]}"; do
    codename="${CODENAME_MAP[$ver]}"
    run mkdir -p "$APT_DIR/pool/main/$codename"
    for arch in "${ARCHITECTURES[@]}"; do
        run mkdir -p "$APT_DIR/dists/$codename/main/binary-$arch"
    done
done

step "Populating pool"

for ver in "${!CODENAME_MAP[@]}"; do
    codename="${CODENAME_MAP[$ver]}"
    src="$APT_DIR/$ver"
    dst="$APT_DIR/pool/main/$codename"
    echo "$ver -> pool/main/$codename/"
    if [[ $DRY_RUN -eq 0 ]]; then
        for deb in "$src"/*.deb; do
            ln "$deb" "$dst/" 2>/dev/null || cp "$deb" "$dst/"
        done
    fi
done

step "Generating Packages indexes"

for ver in "${!CODENAME_MAP[@]}"; do
    codename="${CODENAME_MAP[$ver]}"
    echo "Indexing $codename..."

    if [[ $DRY_RUN -eq 1 ]]; then
        echo "(dry-run: would generate Packages for $codename)"
        continue
    fi

    all_packages=$(cd "$APT_DIR" && apt-ftparchive packages "pool/main/$codename/")

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

for ver in "${!CODENAME_MAP[@]}"; do
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

    for ver in "${!CODENAME_MAP[@]}"; do
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
    echo "Public key -> xcat-dep.asc"
else
    echo "WARNING: $key_src not found, skipping key export"
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
