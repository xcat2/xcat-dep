# Build Guide (`mockbuild-all.pl`)

This guide explains how to use `mockbuild-all.pl` to build, validate, and package xCAT dependencies and optional xCAT packages into a unified EL10 repository layout.
It also documents the operational flags for controlling build, install-check, collection, and packaging behavior.

# Purpose

`mockbuild-all.pl` is the top-level build orchestrator for generating a **unified xCAT repository**.
It builds required dependency RPMs and, by default, xCAT RPMs, then assembles:

- a binary RPM repo tree with repodata
- an SRPM repo tree with repodata
- one binary repo tarball and one SRPM repo tarball

# Historical Context

Historically, the deployment flow used separate repositories:

- `xcat-core` for xCAT packages
- `xcat-dep` for dependency packages

The current flow produces a single **unified `xcat` repository** containing all required packages together.

# Placeholder Conventions

This guide uses the following placeholders consistently:

- `<REPO_ROOT>`: xcat-dep repository root (example: `/root/xcat-dep`)
- `<XCAT_SOURCE>`: xCAT source root (example: `<REPO_ROOT>/xcat-source-code`)
- `<ARCH>`: output of `uname -m` (for example: `x86_64`, `ppc64le`)
- `<OS_ID>`: `ID` field from `/etc/os-release` (for example: `rhel`, `rocky`)
- `<REL>`: integer major release from `VERSION_ID` in `/etc/os-release` (for example: `10`)
- `<TARGET>`: `<OS_ID>+epel-<REL>-<ARCH>`
- `<RUN_ID>`: build run identifier (auto-generated if omitted)

# Build Pipeline Overview

`mockbuild-all.pl` orchestrates these build components in parallel:

- `<REPO_ROOT>/elilo/mockbuild.pl`
- `<REPO_ROOT>/grub2-xcat/mockbuild.pl`
- `<REPO_ROOT>/ipmitool/mockbuild.pl`
- `<REPO_ROOT>/syslinux/mockbuild.pl`
- `<REPO_ROOT>/goconserver/mockbuild.pl`
- `<REPO_ROOT>/mockbuild-perl-packages.pl`
- `<XCAT_SOURCE>/buildrpms.pl` (unless `--skip-xcat` is set)

Each build path uses `mock` for chroot isolation. Top-level steps are parallelized by `mockbuild-all.pl`, and perl dependency builds are also parallelized internally by `mockbuild-perl-packages.pl`.

`mockbuild-all.pl` does more than building RPMs. In a default run it performs these stages:

1. Optional chroot cleanup (`--scrub-all-chroots`)
2. Parallel build execution
3. Optional install/smoke checks inside child builders (disabled with `--skip-install`)
4. Binary RPM collection into `repo/<ARCH>/`
5. Source RPM collection into `repo-src/`
6. `createrepo --update` on both repo trees
7. Tarball creation for both repo trees
8. Summary generation (`summary.txt`)

# Skip and Control Flags

Use these flags to skip specific operations:

- `--skip-install`
  - Skips install/smoke checks performed by child builder scripts after RPM build.
- `--skip-xcat`
  - Skips `<XCAT_SOURCE>/buildrpms.pl` (xCAT package build step).
- `--skip-xcat-dep`
  - Skips non-perl xcat-dep package builders (`elilo`, `grub2-xcat`, `ipmitool-xcat`, `syslinux-xcat`, `goconserver`).
- `--skip-perl`
  - Skips `<REPO_ROOT>/mockbuild-perl-packages.pl`.
- `--skip-build`
  - Skips all build steps; only runs collection/repo/tarball stages from existing artifact roots.
- `--skip-createrepo`
  - Skips `createrepo --update`.
- `--skip-tarball`
  - Skips tarball creation for both binary and SRPM repos.
- `--skip-genesis`
  - Skips the existing per-EL Genesis image build.
- `--genesis-release <PATH>`
  - Adds a verified OpenEmbedded Genesis RPM release alongside the existing
    per-EL Genesis packages.
- `--scrub-all-chroots`
  - Runs `mock -r <TARGET> --scrub=all` before build and collection.
- `--collect-dir <PATH>`
  - Adds extra artifact roots to the collection phase (repeatable).
- `--dry-run`
  - Prints planned actions without executing them.
- `--force-unlock`
  - Removes a stale lock after the previous publisher has been checked.

# Prerequisites

- Run as `root`.
- `mockbuild-all.pl` and package sources present under `<REPO_ROOT>`.
- xCAT sources present under `<XCAT_SOURCE>`.

Install baseline tooling:

```bash
dnf -y install perl perl-File-Slurper perl-IPC-Cmd \
  perl-Parallel-ForkManager mock createrepo tar rpm-build rpmdevtools \
  dnf-plugins-core wget git
```

If you will build xCAT packages (that is, you will **not** use `--skip-xcat`), install xCAT build dependencies:

```bash
cd <XCAT_SOURCE>
perl buildrpms.pl --install_deps
```

Validate mock config availability:

```bash
mock -r <TARGET> --print-root-path
```

# Target Resolution

`--target` is optional.

If `--target` is omitted, `mockbuild-all.pl` derives `<TARGET>` from:

- `/etc/os-release` (`ID`, `VERSION_ID`)
- `uname -m`

Equivalent derivation:

```text
<TARGET> = <OS_ID>+epel-<REL>-<ARCH>
```

`<TARGET>` is also passed to `mock` as the chroot/config identifier:

```text
mock -r <TARGET> ...
```

# Build Full Unified Repository (xCAT + Dependencies)

Use this mode to build dependency packages and xCAT packages together.

```bash
cd /root/xcat-dep
perl ./mockbuild-all.pl \
  --repo-root /root/xcat-dep \
  --xcat-source /root/xcat-dep/xcat-source-code \
  --scrub-all-chroots
```

Notes:

- Install/smoke checks run by default inside child builders.
- Add `--skip-install` to skip those checks.
- `<RUN_ID>` is optional; when omitted it is timestamp-based.

# Add an OpenEmbedded Genesis Release

Build the Genesis package release first, following
[`genesis-openembedded/README.md`](genesis-openembedded/README.md). Then pass the
result to the regular repository build:

```bash
cd <REPO_ROOT>
perl ./mockbuild-all.pl \
  --repo-root <REPO_ROOT> \
  --xcat-source <XCAT_SOURCE> \
  --genesis-release /path/to/xcat-genesis-release
```

The release is checked before any package is collected. Its binary RPMs are
published once under `xcat-dep/common`. Source RPMs stay in the verified
release directory. Existing per-EL repositories keep the old Genesis packages
and contain no OpenEmbedded copies.

The build holds separate locks for its work area and the published repository.
It prepares the complete common repository in a temporary directory, then
replaces the previous repository only after package verification, metadata
generation, and signing have succeeded. If a stopped publisher leaves staging
or backup directories behind, rerun it with ``--force-unlock`` to recover the
previous repository before starting a new publication.

Repository publication requires a release containing every supported Genesis
architecture. The packages are `noarch`, and the common repository contains
the full set of target images.

The release checksums cover the unsigned input packages. If repository signing
is enabled, `rpmsign` changes the deployed RPM bytes after collection.

The OpenEmbedded packages use their own names and install under
`/opt/xcat/share/xcat/netboot/genesis-openembedded/`. Publishing them does not
replace the Genesis packages used by current xcat-core releases. Activation is
a separate xcat-core change.

Omit `--genesis-release` to keep using the existing Genesis builder.

The per-target repository tarballs do not contain `xcat-dep/common`. For an
offline installation, mirror the common repository with its metadata before
disconnecting the installation network.

# Build Unified Repository Without xCAT (`--skip-xcat`)

Use this mode to build dependency packages only and skip invoking `/root/xcat-dep/xcat-source-code/buildrpms.pl`.

```bash
cd /root/xcat-dep
perl ./mockbuild-all.pl \
  --repo-root /root/xcat-dep \
  --xcat-source /root/xcat-dep/xcat-source-code \
  --scrub-all-chroots \
  --skip-xcat \
  --skip-install
```

Important behavior:

- `--skip-xcat` skips the xCAT build step, but collection still scans:
  - `<XCAT_SOURCE>/dist/<TARGET>/rpms`
- If that path already has xCAT RPMs, they are included in the resulting unified repo.

# Common Build Modes

Full unified repo (xCAT + dependencies, with install/smoke checks):

```bash
cd <REPO_ROOT>
perl ./mockbuild-all.pl \
  --repo-root <REPO_ROOT> \
  --xcat-source <XCAT_SOURCE> \
  --scrub-all-chroots
```

Full unified repo (xCAT + dependencies, skip install/smoke checks):

```bash
cd <REPO_ROOT>
perl ./mockbuild-all.pl \
  --repo-root <REPO_ROOT> \
  --xcat-source <XCAT_SOURCE> \
  --scrub-all-chroots \
  --skip-install
```

Dependency-only repo (skip xCAT package build):

```bash
cd <REPO_ROOT>
perl ./mockbuild-all.pl \
  --repo-root <REPO_ROOT> \
  --xcat-source <XCAT_SOURCE> \
  --scrub-all-chroots \
  --skip-xcat \
  --skip-install
```

Collection-only pass from existing build artifacts:

```bash
cd <REPO_ROOT>
perl ./mockbuild-all.pl \
  --repo-root <REPO_ROOT> \
  --xcat-source <XCAT_SOURCE> \
  --skip-build
```

# Output Artifacts and Paths

For each run:

- Binary repo path:
  - `<REPO_ROOT>/build-output/mockbuild-all/<RUN_ID>/repo/<ARCH>/`
- SRPM repo path:
  - `<REPO_ROOT>/build-output/mockbuild-all/<RUN_ID>/repo-src/`
- Run summary:
  - `<REPO_ROOT>/build-output/mockbuild-all/<RUN_ID>/summary.txt`
- Binary repo tarball:
  - `<REPO_ROOT>/build-output/mockbuild-all/mockbuild-all-<TARGET>-<RUN_ID>.tar.gz`
- SRPM repo tarball:
  - `<REPO_ROOT>/build-output/mockbuild-all/mockbuild-all-<TARGET>-<RUN_ID>-srpm.tar.gz`

# Architecture Requirements

`mockbuild-all.pl` derives architecture from the build host:

- `<ARCH> = $(uname -m)`

Because of this, to build `ppc64le` artifacts you must run `mockbuild-all.pl` on a Power host where:

- `uname -m` returns `ppc64le`
- a matching mock config exists for `<TARGET>` (for example `rocky+epel-10-ppc64le`)

In short: build `ppc64le` packages on a Power machine.

# riscv64 (EL10): cross-building on an x86_64 host

There is no riscv64 build host in the xCAT build farm and no EPEL for riscv64, so the
EL10 riscv64 dependency repository (`rh10/riscv64`) is cross-built on an x86_64 host:
mock runs a Rocky Linux 10 riscv64 chroot through user-mode QEMU (`forcearch`), so the
packages are compiled by the riscv64 toolchain of the chroot itself. The mock
configuration for that chroot is shipped in this repository:

- `mock-configs/rocky-10-riscv64-xcat.cfg`

It includes the stock `templates/rocky-10.tpl` from mock-core-configs (Rocky 10 BaseOS,
AppStream, CRB and extras for `$basearch` = riscv64) and sets
`root = 'rocky-10-riscv64-xcat'`, `target_arch = 'riscv64'`,
`legal_host_arches = ('x86_64', 'riscv64')` and `forcearch = 'riscv64'`. The stock
`rocky-10-riscv64.cfg` cannot be used from an x86_64 host (it only admits a riscv64 host
and names its chroot `rocky-10-x86_64`).

## Host prerequisites

On an x86_64 EL10 host with the baseline tooling from "Prerequisites":

- `mock` (>= 5) and `mock-core-configs` providing `templates/rocky-10.tpl` and
  `rocky-10-x86_64.cfg` (the native, EPEL-free Rocky 10 chroot used for the noarch
  packages of the riscv64 build), `podman` (mock pulls the Rocky 10 bootstrap image),
  `golang` (goconserver is cross-compiled on the host with `GOARCH=riscv64`).
- A static user-mode QEMU for riscv64 registered in `binfmt_misc` with the `F` (fix
  binary) flag. On Fedora this is the `qemu-user-static-riscv` package. EL10 has no such
  package: copy `/usr/bin/qemu-riscv64-static` out of a Fedora container (for example
  `registry.fedoraproject.org/fedora:44` with `dnf install qemu-user-static-riscv`) to
  `/usr/local/bin/qemu-riscv64-static` on the host, then register it:

  ```text
  # /etc/binfmt.d/qemu-riscv64-static.conf
  :qemu-riscv64:M::\x7fELF\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\xf3\x00:\xff\xff\xff\xff\xff\xff\xff\x00\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff\xff:/usr/local/bin/qemu-riscv64-static:FP
  ```

  ```bash
  systemctl restart systemd-binfmt
  cat /proc/sys/fs/binfmt_misc/qemu-riscv64        # enabled, flags: PF
  ```

- mock refuses `forcearch` unless `/usr/bin/qemu-riscv64-static` exists (it only checks
  for the file; the kernel runs the interpreter registered above). When the binary lives
  in `/usr/local/bin`, a symlink is enough:

  ```bash
  ln -s /usr/local/bin/qemu-riscv64-static /usr/bin/qemu-riscv64-static
  ```

Validate the host before building (all as root; mock also accepts members of the `mock`
group):

```bash
podman run --rm --arch riscv64 quay.io/rockylinux/rockylinux:10 uname -m   # riscv64
install -m 644 mock-configs/rocky-10-riscv64-xcat.cfg /etc/mock/
mock -r rocky-10-riscv64-xcat --init                                       # ~3-4 min
mock -r rocky-10-riscv64-xcat --chroot -- uname -m                         # riscv64
```

The per-package `mockbuild.pl` scripts reference the target by name only
(`include('/etc/mock/<target>.cfg')` in their deterministic overlay), so the config must
live in `/etc/mock/` for a build.

Emulated builds are slow: a chroot init takes 3-4 minutes and a C or XS build 5-30
minutes instead of seconds, so the riscv64 build of the dependency set takes on the order
of an hour on a large host. Chroots and caches live under `/var/lib/mock` and
`/var/cache/mock` as for any other mock target (about 1 GB per per-package chroot).

## Building and deploying `rh10/riscv64`

`mockbuild-all.pl` knows `rocky-10-riscv64-xcat` as a *forcearch target* (see
`%forcearch_targets` in the script): it is selected with `--target` only (the default
rh8/rh9/rh10 run stays the host arch), installs the shipped config into `/etc/mock/` if
missing, and then builds:

| what | how |
|---|---|
| ipmitool-xcat, conserver-xcat | `mock --rebuild` in the riscv64 chroot (emulated), `--target-arch riscv64` |
| goconserver | cross-compiled on the host (`GOARCH=riscv64`), packaged with `rpmbuild --target riscv64` |
| grub2-xcat (noarch) | built in the native, EPEL-free `rocky-10-x86_64` chroot |
| perl list6 + EPEL gap (`--epel-gap`) | `mockbuild-perl-packages.pl --target-arch riscv64 --noarch-mock-cfg rocky-10-x86_64 --epel-gap`: XS modules in the riscv64 chroot, noarch modules in the native chroot |
| elilo-xcat, syslinux-xcat, xnba-undi | not built (x86 bootloaders) |

There is no EPEL for riscv64, so the perl deps of xCAT that EL10 otherwise takes from EPEL
are built here as well (`--epel-gap` in `mockbuild-perl-packages.pl`: perl-Crypt-Blowfish,
perl-Crypt-CBC, perl-Crypt-Rijndael, perl-Digest-SHA1, perl-Expect, perl-Mail-Sender,
perl-Net-DNS, perl-Net-IP and the build-only perl-Path-Class), and the noarch deps are
built once, natively, rather than imported from another repo. The required set asserted
after the build is ipmitool-xcat, grub2-xcat, perl-IO-Stty, perl-HTTP-Async and
perl-Net-HTTPS-NB (plus xCAT-genesis-base unless `--skip-genesis`).

Deliberately not built for riscv64:

- perl-DB_File: needs libdb, which EL10 dropped (EPEL 10 re-adds it for its own
  architectures only, and Rocky Linux 10 riscv64 has no libdb at all). Only the Confluent
  client of xCAT-server uses DB_File and xCAT-server only recommends perl-DB_File, so a
  riscv64 management node installs without it.
- perl-SOAP-Lite: its Fedora BuildRequires (IO::SessionData, MIME::Lite, XML::Parser::Lite,
  Test::XML) are EPEL-only as well, so it can neither be built nor installed without EPEL;
  xCAT uses it for HP blade and VirtualBox support only.

Known differences from the EPEL-fed x86_64 repo: perl-Net-DNS is the 0.80 release of
`perl-Net-DNS/Net-DNS.spec`, built pure-perl (`--noxs`) as noarch, where EPEL 10 ships
1.47 -- its spec BuildRequires perl(Net::LibIDN2), which is EPEL-only too. A newer,
XS-free perl-Net-DNS without that BuildRequires is a follow-up. The riscv64 goconserver
binaries are stripped by the Go linker (`-ldflags "-s -w"`, cross build only) because the
host's brp-strip cannot strip a riscv64 ELF.

On a host where `/` is small, note that every per-package mock chroot (riscv64 and the
native noarch one) and its bootstrap chroot live under `/var/lib/mock` while it builds
(about 0.5-1 GB each; the bootstrap dirs stay behind after a successful build until
scrubbed), so `--max-parallel` bounds the peak disk usage as well as the CPU load.

```bash
cd <REPO_ROOT>
perl ./mockbuild-all.pl \
  --target rocky-10-riscv64-xcat \
  --output <OUTPUT> \
  --skip-xcat --skip-genesis --skip-install \
  --max-parallel 8
```

Outputs (as for every target): the build tree under `<OUTPUT>/mockbuild-all/` and the
deployable repo `<OUTPUT>/xcat-dep/rh10/riscv64/` (rpms, `repodata/`, `xcat-dep.repo` with
`baseurl=https://xcat.org/files/xcat/repos/yum/devel/xcat-dep/rh10/riscv64`,
`mklocalrepo.sh`, `buildinfo.txt`). Builder failures are tolerated and listed at the end.
The cross-built rpms are smoke-tested without installing them on the host: ipmitool-xcat,
conserver-xcat and the XS perl modules inside the emulated chroot, goconserver by running
its binaries through the binfmt handler. `--skip-install` only skips those checks and the
host installation of the noarch perl rpms (built in the native chroot); pass it when the
build host must stay untouched.

# Validation Commands

```bash
cat <REPO_ROOT>/build-output/mockbuild-all/<RUN_ID>/summary.txt
ls -1 <REPO_ROOT>/build-output/mockbuild-all/<RUN_ID>/repo/<ARCH>/
ls -1 <REPO_ROOT>/build-output/mockbuild-all/<RUN_ID>/repo-src/
ls -1 <REPO_ROOT>/build-output/mockbuild-all/mockbuild-all-<TARGET>-<RUN_ID>.tar.gz
ls -1 <REPO_ROOT>/build-output/mockbuild-all/mockbuild-all-<TARGET>-<RUN_ID>-srpm.tar.gz
find <REPO_ROOT>/build-output/mockbuild-all/<RUN_ID>/build-logs -type f | sort
```

# Common Issues

- `Missing xCAT build script: .../buildrpms.pl`
  - Ensure `<XCAT_SOURCE>` points to a valid xCAT source tree.
- `WARN: missing dep builder script, skipping: ...`
  - Sync the repository; one or more package build scripts are missing.
- `mock target not found`
  - Validate with `mock -r <TARGET> --print-root-path` and install the required mock config packages.

# References

- [mock project repository](https://github.com/rpm-software-management/mock)
