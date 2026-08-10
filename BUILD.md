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
- `--scrub-all-chroots`
  - Runs `mock -r <TARGET> --scrub=all` before build and collection.
- `--collect-dir <PATH>`
  - Adds extra artifact roots to the collection phase (repeatable).
- `--dry-run`
  - Prints planned actions without executing them.

# Prerequisites

- Run as `root`.
- `mockbuild-all.pl` and package sources present under `<REPO_ROOT>`.
- xCAT sources present under `<XCAT_SOURCE>`.

Install baseline tooling:

```bash
dnf -y install perl perl-Parallel-ForkManager mock createrepo tar rpm-build rpmdevtools dnf-plugins-core wget git
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

# Ubuntu / Debian dependency build (`sbuild-all.pl`)

The EL/SUSE path above uses `mockbuild-all.pl` (rpm + mock). The Ubuntu/Debian dependency packages
are built as **.deb** and assembled into a signed **apt** repository by **`sbuild-all.pl`** — the
apt/sbuild analogue of `mockbuild-all.pl`. It shares the same CLI vocabulary (`BuildUtils.pm`'s
`standard_options`) and the same manifest-driven, zero-tolerance, fail-hard design, and it **absorbs**
the three former shell scripts (`mk-dep-chroots.sh`, `build-dep-debs.sh`, `build-apt-repo.sh`) into one
Perl entrypoint. The testable helpers live in `BuildUtils.pm` and are exercised by `t/sbuild-all.t`.

The compiled deps are built **per codename inside the matching `sbuild` chroot** so each binary links
against that release's libc/toolchain (a noble/glibc-2.39 binary won't run on focal/glibc-2.31). The
build never mutates the checkout: each package tree is copied out-of-tree and stamped from
`SOURCE_DATE_EPOCH` (reproducible), and the maintained `debian/` packaging is reused verbatim.

Codename ↔ version (the single supported set — `BuildUtils` is the source of truth):
`focal`=20.04, `jammy`=22.04, `noble`=24.04, `resolute`=26.04.

## Design (how the review's correctness concerns are met)

- **Fresh staging + promote-on-success.** Everything is built + validated into a per-run staging tree
  first; the published apt repo is (re)assembled from staging ONLY after the complete expected set
  validates — a partial/failed build never reaches the repo and stale debs never accumulate.
- **Per-arch package sets (`debs-manifest.conf`).** One `[<codename>-<arch>]` section per target. The
  x86 boot components (`syslinux`/`elilo`/`xnba`, `Architecture:all`) are built ONCE on amd64
  (single producer) and assembled into every arch's `Packages` index; ppc64el builds only the
  genuinely arch-specific compiled deps (`ipmitool-xcat`, `conserver-xcat`, `goconserver`).
- **Fail-hard.** Any required chroot / package / artifact failure, or any version-pin mismatch, fails
  the whole run non-zero.
- **Genesis keeps its maintained packaging.** A native `xcat-genesis-base` deb is INGESTED as-is when
  provided (`--genesis-deb`); a converted rpm keeps the maintained control (Depends/Breaks/Replaces)
  and maintainer scripts from `xcat-core/xCAT-genesis-builder/debian/`. Cross-arch ppc64el genesis on
  the amd64 host (issue #7610) is `--require-ppc-genesis`-gated.
- **First-run chroots.** `sbuild-all.pl` auto-initializes any missing `<codename>-<arch>-sbuild` chroot
  (main + universe so `quilt` et al. resolve; fast mirror; shared-tree bind-mount) — no separate step.

## Files

- **`sbuild-all.pl`** — the orchestrator (run as **root** on the Ubuntu build host: the amd64 host for
  `amd64`, the ppc host for `ppc64el`).
- **`BuildUtils.pm`** — shared, unit-tested helpers + the canonical CLI spec (mirrors `MockBuildUtils.pm`).
- **`<dep>/sbuild.pl`** ×7 — per-package builders (mirror `<dep>/mockbuild.pl`); each drives its
  maintained `debian/` in the chroot and collects the `.deb`(s). Invoked by `sbuild-all.pl`.
- **`debs-manifest.conf`** — per `[<codename>-<arch>]` required set + version pins.
- **`t/sbuild-all.t`** — fixture tests (`prove t/sbuild-all.t`).

## Usage (per arch, as root on the matching build host)

```bash
# amd64 host — build all four codenames, sign, assemble the apt tree:
./sbuild-all.pl --arch amd64 --dists "focal jammy noble resolute" \
  --xcat-source ../xcat-core --genesis-rpm <xCAT-genesis-base rpm> \
  --genesis-rpm-ppc <ppc64 xCAT-genesis-base rpm> \
  --gpg-sign --gpg-key-id xcat@megware.com --gpg-home <gpg-home>

# ppc64el host — arch-specific deps only (the arch:all boot components come from amd64):
./sbuild-all.pl --arch ppc64el --dists "focal jammy noble resolute" \
  --xcat-source ../xcat-core --genesis-rpm <ppc64 xCAT-genesis-base rpm> --gpg-sign ...

# a single target / a dry run:
./sbuild-all.pl --target noble-amd64 ...
./sbuild-all.pl --dry-run --skip-build --skip-genesis ...
```

`sbuild-all.pl --help` lists every option; the shared flags (`--repo-root`, `--manifest`,
`--skip-build/-install/-genesis/-xcat-dep`, `--build-number`, `--gpg-sign`, `--dry-run`, …) match
`mockbuild-all.pl`.

# References

- [mock project repository](https://github.com/rpm-software-management/mock)
- [sbuild / schroot](https://wiki.debian.org/sbuild)
