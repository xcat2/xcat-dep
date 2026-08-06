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

# Ubuntu / Debian dependency build (apt, sbuild)

The EL/SUSE path above uses `mockbuild-all.pl` (rpm). The Ubuntu/Debian dependency packages are
built as **.deb** and assembled into a signed **apt** repository, with the compiled deps built
**per codename inside matching `sbuild` chroots** so each binary links against that release's
libc/toolchain (a noble/glibc-2.39 binary won't run on focal/glibc-2.31).

Codename ↔ version: `focal`=20.04, `jammy`=22.04, `noble`=24.04, `resolute`=26.04.

## Scripts

- **`mk-dep-chroots.sh`** — create the per-codename `sbuild` chroots the deb build needs. Run as
  **root** on the Ubuntu build host (the amd64 host for `amd64`, the ppc host for `ppc64el`); one
  chroot per codename (`<codename>-<arch>-sbuild`). Idempotent. Gotchas baked in: `archive.ubuntu.com`
  times out from some hosts (use a fast mirror, override with `MIRROR=`); the chroot `sources.list`
  must carry **main + universe** (build-deps like `quilt` live in universe); a missing debootstrap
  script is symlinked to the generic one. Env: `MIRROR`, `DEB_ARCH` (default `amd64`), `CODENAMES`
  (default `focal jammy noble resolute`).

- **`build-dep-debs.sh <PREFIX> "<DISTS>" [<GENESIS_BASE_RPM>] [<GENESIS_BASE_RPM_PPC>]`** — build
  every xcat-dep `.deb` for this host's arch and stage them under `<PREFIX>/repos/apt/<ubuntuXX.YY>/`
  for each requested codename. Run once per arch (amd64 on the x86 host, ppc64el on the ppc host).
  The compiled deps (ipmitool, syslinux, conserver, goconserver, grub2-xcat, elilo, xnba) are built
  **inside** the matching `schroot -c <codename>-<arch>-sbuild` — never built once and re-labeled.
  `xCAT-genesis-base-{amd64,ppc64el}` are `Architecture:all`, so the amd64 host builds them once and
  stages them into every codename (cross-arch netboot, issue #7610). A missing chroot fails that
  codename loudly (no silent re-label).

- **`build-apt-repo.sh`** (already in this repo) — assemble the staged per-codename debs into ONE apt
  tree signed with the xCAT key (the same key as xcat-core apt).

## Flow (per arch)

```
mk-dep-chroots.sh                                       # once, as root: create the sbuild chroots
build-dep-debs.sh <PREFIX> "focal jammy noble resolute" # build + stage the .debs per codename
build-apt-repo.sh ...                                   # assemble + sign the apt tree
```

> NOTE: `mk-dep-chroots.sh` / `build-dep-debs.sh` originated in the xCAT CI (xcat-core-ci-cd) and
> still carry CI-specific path assumptions (e.g. a bind-mount of the shared build tree in
> `mk-dep-chroots.sh`); genericizing them for standalone use is tracked in the xCAT CI issue queue.

# References

- [mock project repository](https://github.com/rpm-software-management/mock)
