#!/bin/bash
#
# mk-dep-chroots.sh -- create the per-codename sbuild chroots the xcat-dep per-codename deb build
# (build-dep-debs.sh) needs. Run as ROOT on the ubuntu build host (xcat-master-ub for amd64; the ppc
# ubuntu host for ppc64el). Idempotent: recreates each chroot from scratch.
#
# Why not just build on the host: the compiled deps link against the target codename's libc/toolchain,
# so a focal deb MUST be built in a focal chroot (a noble/glibc-2.39 binary won't run on focal). This
# creates one chroot per codename that build-dep-debs.sh drives via `schroot -c <codename>-<arch>-sbuild`.
#
# GOTCHAS baked in here (learned the hard way):
#   * archive.ubuntu.com TIMES OUT from the build host -> use a fast BR mirror (override with MIRROR=).
#   * build-deps like `quilt` live in UNIVERSE -> the chroot sources.list must carry main + universe
#     (sbuild-createchroot's default is main only, which makes every build fail on `quilt`).
#   * debootstrap may lack a script for a codename -> symlink it to the generic `gutsy` script.
#   * build-dep-debs.sh reads the source + writes debs under /opt/xcat-ci-shared -> bind-mount it in.
#
# Env: MIRROR (default BR archive), DEB_ARCH (default amd64), CODENAMES (default all four).
set -u
MIRROR="${MIRROR:-http://br.archive.ubuntu.com/ubuntu}"
ARCH="${DEB_ARCH:-amd64}"
CODENAMES="${CODENAMES:-focal jammy noble resolute}"

command -v sbuild-createchroot >/dev/null 2>&1 \
  || { echo "installing schroot/sbuild/debootstrap"; DEBIAN_FRONTEND=noninteractive apt-get install -y -q schroot sbuild debootstrap; }
for cn in $CODENAMES; do
  [ -e "/usr/share/debootstrap/scripts/$cn" ] || ln -sf gutsy "/usr/share/debootstrap/scripts/$cn"
done

for cn in $CODENAMES; do
  echo "=== creating ${cn}-${ARCH} $(date +%H:%M:%S) via ${MIRROR} ==="
  rm -rf "/srv/chroot/${cn}-${ARCH}"; rm -f /etc/schroot/chroot.d/${cn}-${ARCH}* 2>/dev/null
  if sbuild-createchroot --arch="$ARCH" "$cn" "/srv/chroot/${cn}-${ARCH}" "$MIRROR"; then
    # enable main + universe (+ updates/security) so build-deps in universe (quilt, ...) resolve
    cat > "/srv/chroot/${cn}-${ARCH}/etc/apt/sources.list" <<EOF
deb ${MIRROR} ${cn} main universe
deb ${MIRROR} ${cn}-updates main universe
deb ${MIRROR} ${cn}-security main universe
EOF
    mkdir -p "/srv/chroot/${cn}-${ARCH}/opt/xcat-ci-shared"   # bind-mount target for the shared tree
    echo "OK ${cn}"
  else
    echo "FAIL ${cn}"
  fi
done

# ensure the sbuild profile bind-mounts the shared tree into every session
grep -q '/opt/xcat-ci-shared' /etc/schroot/sbuild/fstab 2>/dev/null \
  || echo '/opt/xcat-ci-shared  /opt/xcat-ci-shared  none  rw,bind  0  0' >> /etc/schroot/sbuild/fstab

echo "ALL_CHROOTS_DONE (registered: $(schroot -l 2>/dev/null | grep -c '^chroot:'))"
