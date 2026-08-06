#!/usr/bin/env bash
#
# build-dep-debs.sh <PREFIX> "<DISTS>" [<GENESIS_BASE_RPM>] [<GENESIS_BASE_RPM_PPC>]
#
# Build every xcat-dep .deb for this host's arch (DEB_ARCH env, default from dpkg) and STAGE the
# resulting debs into <PREFIX>/repos/apt/<ubuntuXX.YY>/ for each requested codename so build-apt-repo.sh
# can assemble them. Run once per arch (amd64 on the x86 ubuntu host, ppc64el on the ppc ubuntu host).
#
# PER-CODENAME BUILDS (correctness): the compiled deps (ipmitool, syslinux, conserver, goconserver,
# grub2-xcat, elilo, xnba) are C/Go binaries that link against the target codename's libc/toolchain, so
# each is built INSIDE the matching sbuild chroot (`schroot -c <codename>-<arch>-sbuild`) -- NOT built
# once on the host and re-labeled into every codename dir (a noble/glibc-2.39 binary won't run on a
# focal/glibc-2.31 MN). Build-deps are installed in the session from each package's debian/control.
# The chroots must exist (create them with ci/mk-dep-chroots.sh); a missing chroot FAILS that codename
# LOUDLY (no silent re-label). The chroots need main + universe (quilt et al. live in universe).
#
# Cross-arch genesis (issue #7610): in 2.17 the apt repo shipped BOTH xcat-genesis-base-amd64 and
# xcat-genesis-base-ppc64el so an amd64 MN could netboot ppc nodes (and vice versa). Both are
# Architecture:all (codename-agnostic), so the amd64 host builds them ONCE and stages into every codename.
#
# Codename <-> version: focal=20.04 jammy=22.04 noble=24.04 resolute=26.04.
#
set -uo pipefail
PREFIX="${1:?PREFIX required}"; DISTS="${2:?DISTS required}"; GENESIS_RPM="${3:-}"
GENESIS_RPM_PPC="${4:-${GENESIS_BASE_RPM_PPC:-}}"
DEB_ARCH="${DEB_ARCH:-$(dpkg --print-architecture)}"
DEP="$PREFIX/source/xcat-dep"
APT="$PREFIX/repos/apt"
[ -d "$DEP" ] || { echo "FATAL: no xcat-dep checkout at $DEP" >&2; exit 1; }

declare -A C2V=( [focal]=ubuntu20.04 [jammy]=ubuntu22.04 [noble]=ubuntu24.04 [resolute]=ubuntu26.04 )
PKGS="ipmitool syslinux conserver goconserver grub2-xcat elilo xnba"

echo "[build-dep-debs] DEB_ARCH=$DEB_ARCH DISTS=$DISTS (per-codename chroot builds)"

# build one codename's compiled deps inside its sbuild chroot; stage into repos/apt/<ver>/.
# The whole per-codename build runs in ONE schroot session (ephemeral overlay); the produced debs are
# copied OUT to $out on the shared tree (bind-mounted rw into the chroot). Returns non-zero if any
# package failed to build for this codename.
build_codename() {
  local cn="$1" ver="${C2V[$1]:-}" chroot="${1}-${DEB_ARCH}-sbuild"
  [ -n "$ver" ] || { echo "FATAL: unknown codename '$cn'" >&2; return 1; }
  if ! schroot -l 2>/dev/null | grep -qx "chroot:${chroot}"; then
    echo "FATAL: sbuild chroot '$chroot' missing for codename '$cn' -- create it with ci/mk-dep-chroots.sh (build-once-per-codename requires it; refusing to re-label a host build)" >&2
    return 1
  fi
  local out="$PREFIX/debs-$cn-$DEB_ARCH"; rm -rf "$out"; mkdir -p "$out"
  echo "== [$cn] building [$PKGS] in chroot $chroot -> $out =="
  # schroot SANITIZES the environment, so pass DEP/OUT/PKGS as POSITIONAL ARGS to the inner bash
  # (env vars would arrive empty inside the chroot). `-s <args>` => args become $1/$2/$3 for the
  # stdin (heredoc) script; the 'INNER' heredoc is quoted so inner $pkg/$W do not expand out here.
  schroot -c "$chroot" -u root -d / -- bash -uo pipefail -s "$DEP" "$out" "$PKGS" <<'INNER'
    DEP="$1"; OUT="$2"; PKGS="$3"
    export DEBIAN_FRONTEND=noninteractive DEB_BUILD_OPTIONS=nocheck
    for t in 1 2 3; do apt-get update -q && break; sleep 5; done
    # common tools the make_deb.sh scripts use beyond debian/control Build-Depends (e.g. goconserver's
    # make_deb.sh git-clones + go-builds; others wget/curl their upstream tarball).
    apt-get install -y --no-install-recommends git wget curl ca-certificates golang-go devscripts >/dev/null 2>&1 || true
    fail=""
    for pkg in $PKGS; do
      [ -f "$DEP/$pkg/make_deb.sh" ] || { echo "  skip $pkg (no make_deb.sh)"; continue; }
      W=$(mktemp -d); cp -a "$DEP/$pkg" "$W/$pkg"; cd "$W/$pkg"
      if [ -f debian/control ]; then
        # install Build-Depends parsed from debian/control (strip version/arch qualifiers)
        BD=$(sed -n '/^Build-Depends:/,/^\S/p' debian/control | tr ',' '\n' \
             | sed -E 's/^Build-Depends://; s/\(.*\)//; s/\[.*\]//; s/[[:space:]]//g' \
             | grep -E '^[a-z0-9]' | grep -v '^debhelper-compat' | sort -u | tr '\n' ' ')
        [ -n "$BD" ] && { apt-get install -y $BD >/dev/null 2>&1 || echo "  [warn] $pkg: some build-deps failed to install"; }
      fi
      chmod +x make_deb.sh
      if ./make_deb.sh > "$OUT/$pkg.buildlog" 2>&1; then
        # make_deb.sh drops the .deb(s) beside the package dir (the build tree is removed by it)
        found=$(find "$W" -maxdepth 2 -name '*.deb' ! -name '*-dbgsym_*' -print)
        if [ -n "$found" ]; then echo "$found" | while read -r d; do cp -v "$d" "$OUT/"; done; echo "  OK $pkg"
        else echo "  FAIL $pkg (built but produced no .deb)"; fail="$fail $pkg"; fi
      else
        echo "  FAIL $pkg (build error -- see $pkg.buildlog)"; fail="$fail $pkg"
      fi
      cd /; rm -rf "$W"
    done
    [ -z "$fail" ] || { echo "FAILED_PACKAGES:$fail"; exit 1; }
INNER
  local rc=$?
  mkdir -p "$APT/$ver"
  cp -v "$out"/*.deb "$APT/$ver/" 2>/dev/null || true
  return $rc
}

overall=0
for cn in $DISTS; do
  mkdir -p "$APT/${C2V[$cn]:?unknown codename $cn}"
  build_codename "$cn" || overall=1
done

# Convert a noarch xCAT-genesis-base rpm (path or URL) into an Architecture:all deb.
#   convert_genesis_rpm_to_deb <rpm> <deb-package-name> <out-dir>
convert_genesis_rpm_to_deb() {
  local rpm="$1" pkgname="$2" outdir="$3" work ver pkgd
  work="$(mktemp -d)"
  ( cd "$work" && (rpm2cpio "$rpm" 2>/dev/null || curl -fsSL "$rpm" | rpm2cpio) | cpio -idm --quiet )
  ver="$(rpm -qp --qf '%{VERSION}-%{RELEASE}' "$rpm" 2>/dev/null || echo 2.18.0-snap)"
  pkgd="$work/pkg/$pkgname"; mkdir -p "$pkgd/DEBIAN" "$pkgd/opt/xcat"
  cp -a "$work"/opt/xcat/* "$pkgd/opt/xcat/" 2>/dev/null || cp -a "$work"/* "$pkgd/opt/xcat/" 2>/dev/null || true
  cat > "$pkgd/DEBIAN/control" <<CTRL
Package: $pkgname
Version: $ver
Architecture: all
Maintainer: xCAT <xcat@xcat.org>
Description: xCAT genesis base (diskless boot image), converted from the rpm
CTRL
  dpkg-deb --build "$pkgd" "$outdir/${pkgname}_${ver}_all.deb"
  rm -rf "$work"
}

# xCAT-genesis-base debs: Architecture:all, codename-agnostic -> built ONCE (amd64 host) into a genesis
# staging dir, then staged into EVERY requested codename dir. Produces BOTH the amd64 genesis (native)
# AND, for cross-arch (#7610), the ppc64el genesis from the ppc64 rpm -- so the amd64 apt repo can
# netboot ppc nodes. If no rpm given, reuse an already-staged/known deb.
if [ "$DEB_ARCH" = amd64 ]; then
  GEN="$PREFIX/genesis-debs"; rm -rf "$GEN"; mkdir -p "$GEN"
  # --- amd64 genesis (native) ---
  gdeb="$(ls "$APT"/*/xcat-genesis-base-amd64_*_all.deb 2>/dev/null | head -1 || true)"
  if [ -n "$GENESIS_RPM" ]; then
    echo "== converting amd64 genesis-base rpm -> deb: $GENESIS_RPM =="
    convert_genesis_rpm_to_deb "$GENESIS_RPM" xcat-genesis-base-amd64 "$GEN"
  elif [ -n "$gdeb" ]; then
    echo "== reusing already-staged amd64 genesis-base deb: $gdeb =="; cp "$gdeb" "$GEN/"
  else
    reuse="$(ls /opt/xcat-ci-shared/builds/*/debs/xcat-genesis-base-amd64_2.18*_all.deb 2>/dev/null | tail -1 || true)"
    [ -n "$reuse" ] || { echo "FATAL: no GENESIS_BASE_RPM given and no genesis-base deb to reuse" >&2; exit 1; }
    echo "== reusing amd64 genesis-base deb: $reuse =="; cp "$reuse" "$GEN/"
  fi
  # --- ppc64el genesis (cross-arch, issue #7610) ---
  gdeb_ppc="$(ls "$APT"/*/xcat-genesis-base-ppc64el_*_all.deb 2>/dev/null | head -1 || true)"
  if [ -n "$GENESIS_RPM_PPC" ]; then
    echo "== converting ppc64el genesis-base rpm -> deb: $GENESIS_RPM_PPC =="
    convert_genesis_rpm_to_deb "$GENESIS_RPM_PPC" xcat-genesis-base-ppc64el "$GEN"
  elif [ -n "$gdeb_ppc" ]; then
    echo "== reusing already-staged ppc64el genesis-base deb: $gdeb_ppc =="; cp "$gdeb_ppc" "$GEN/"
  else
    echo "WARN: no ppc64 genesis rpm (arg 4 / GENESIS_BASE_RPM_PPC) and none staged --" >&2
    echo "      apt repo will NOT ship xcat-genesis-base-ppc64el; an amd64 MN cannot netboot" >&2
    echo "      ppc nodes (issue #7610). Pass the ppc64 xCAT-genesis-base rpm to fix." >&2
  fi
  # stage the arch:all genesis debs into every requested codename
  for cn in $DISTS; do cp -v "$GEN"/*.deb "$APT/${C2V[$cn]}/" 2>/dev/null || true; done
fi

if [ "$overall" -ne 0 ]; then
  echo "[build-dep-debs] FATAL: one or more codenames had package build failures (see repos/apt/<ver>/*.buildlog)" >&2
else
  echo "[build-dep-debs] staged $DEB_ARCH debs into repos/apt/{$(echo $DISTS | tr ' ' ',')}"
fi
exit $overall
