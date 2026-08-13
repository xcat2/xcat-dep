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

## Design

- **Fresh staging + promote-on-success.** Everything is built + validated into a per-run staging tree
  first; the published apt repo is (re)assembled from staging ONLY after the complete expected set
  validates — a partial/failed build never reaches the repo and stale debs never accumulate.
- **Per-arch package sets (`debs-manifest.conf`).** One `[<codename>-<arch>]` section per target. The
  noarch boot components (`syslinux-xcat`/`grub2-xcat`/`elilo-xcat`/`xnba-undi`, `Architecture:all`)
  are built ONCE on amd64 — single producer, their source is x86-only — and assembled into every
  arch's `Packages` index. They are listed for **ppc64el too, as required-present**, so the gate
  verifies the ppc repo actually carries them (a ppc MN needs them for netboot, matching the EL
  manifest). `build_one_codename` **skips** an `Architecture:all` package on any non-amd64 arch
  (detected via `control_binary_arch`), so ppc builds only the genuinely arch-specific compiled deps
  (`ipmitool-xcat`, `conserver-xcat`, `goconserver`) yet still verifies the boot components.
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

Run `sbuild-all.pl` on the build host for the arch you are building (amd64 on the x86 Ubuntu host,
ppc64el on the ppc Ubuntu host). The Ubuntu version(s) to build are selected with **`--dists`** (a
space/comma list of codenames) or, for exactly one, **`--target <codename>-<arch>`**. Version ↔
codename: `20.04`=`focal`, `22.04`=`jammy`, `24.04`=`noble`, `26.04`=`resolute`.

### Build ALL supported Ubuntu versions

```bash
# amd64 host — build focal+jammy+noble+resolute, sign, assemble the apt tree:
./sbuild-all.pl --arch amd64 --dists "focal jammy noble resolute" \
  --xcat-source ../xcat-core --genesis-rpm <xCAT-genesis-base-x86_64 rpm> \
  --genesis-rpm-ppc <xCAT-genesis-base-ppc64 rpm> \
  --gpg-sign --gpg-key-id xcat@example.com --gpg-home <gpg-home>
```

`--dists` may be omitted entirely — with no `--dists`/`--target`, **all supported codenames** are
built (the default is `focal jammy noble resolute`).

### Build ONE specific Ubuntu version

```bash
# just 24.04 (noble) on amd64 — two equivalent forms:
./sbuild-all.pl --arch amd64 --dists noble  --xcat-source ../xcat-core --genesis-rpm <rpm> --gpg-sign ...
./sbuild-all.pl --target noble-amd64        --xcat-source ../xcat-core --genesis-rpm <rpm> --gpg-sign ...

# just 20.04 (focal):
./sbuild-all.pl --arch amd64 --dists focal  ...
```

### ppc64el host

```bash
# arch-specific deps only (the Architecture:all boot components come from the amd64 build):
./sbuild-all.pl --arch ppc64el --dists "focal jammy noble resolute" \
  --xcat-source ../xcat-core --genesis-rpm <xCAT-genesis-base-ppc64 rpm> --gpg-sign ...
```

### Handy variants

```bash
./sbuild-all.pl --dry-run --arch amd64 --dists noble        # print the plan, do nothing
./sbuild-all.pl --skip-build --skip-genesis --gpg-sign ...  # assemble-only (re-index/re-sign staging)
```

`sbuild-all.pl --help` lists every option and `sbuild-all.pl --man` (or `perldoc sbuild-all.pl`)
prints the full manual; the shared flags (`--repo-root`, `--manifest`,
`--skip-build/-install/-genesis/-xcat-dep`, `--build-number`, `--gpg-sign`, `--dry-run`, …) match
`mockbuild-all.pl`.

# Repository verification gate

After the apt repo is assembled + signed, `sbuild-all.pl` runs a **manifest-driven gate** that fails
the build if the published repo is incomplete or mis-signed. It uses `debs-manifest.conf` as the
single source of truth and is layered so the decision logic is pure and unit-tested
(`BuildUtils::verify_repo_packages` / `verify_repo_signature`; `parse_packages_index` /
`resolve_present_names` for parsing/resolution), separate from the disk/gpg I/O.

- **Runs automatically** at the end of `assemble_apt`, **per codename × arch**. Suppress with
  `--no-verify-repo`; skipped under `--dry-run`. Verify an assembled tree out of band with
  `--verify-repo=<apt_dir>` (manifest/dists/key from `--manifest`/`--dists`/`--gpg-key-id`/`--gpg-home`).
- **Completeness:** for each cell, every package that codename×arch's manifest section requires (after
  `required_pkgs` skip-filtering) must appear in the published `binary-<arch>/Packages` with a version
  satisfying its pin. The arch-suffixed genesis (`xcat-genesis-base`) is resolved to **this cell's
  arch** (`xcat-genesis-base-<arch>`) — never a different arch, so a missing native genesis is caught.
- **Signature:** each `dists/<cn>/InRelease` (or detached `Release`+`Release.gpg`) must be a *good*
  signature whose **primary-key fingerprint equals the fingerprint of `--gpg-key-id`** — the repo was
  signed by exactly the CLI key. Expired/revoked keys and expired signatures are rejected; if the CLI
  key does not resolve to a fingerprint the gate fails (`SIGKEY`), never passes. A signature is only
  *required* when `--gpg-sign` was used (an intentionally-unsigned repo does not false-fail).

**Semantic idiosyncrasies (intentional, and mirrored in the EL `mockbuild-all.pl` gate):**

- **What "the repo" is:** the Ubuntu gate reads the **published `binary-<arch>/Packages` index** (what
  apt serves, per codename×arch); the EL gate reads the **binary rpm files** in the per-target dir.
  Both check the artifact that ships; they differ only in the Debian-vs-RHEL notion of "the repository".
- **Duplicate = hard error:** a package appearing in the index with **two distinct versions** (a stale
  `.deb` not cleaned from the pool) makes `parse_packages_index` **die loudly** rather than keep one —
  identical behaviour to the EL `rpm_version` gate.
- **Version pins** are the manifest's *upstream* version; the published Debian version's epoch/revision
  is stripped (`deb_upstream_version`) before the pin compare.

# Packages notes

- **`pyodbc`** is intentionally not built or listed: modern Ubuntu provides `python3-pyodbc` from apt
  (and EL from appstream/EPEL), so xcat-dep no longer ships its own. The legacy `pyodbc/` directory
  (an old `pyodbc-3.0.7` RPM spec, no `debian/`) is kept for historical reference only.
- **`conserver-xcat`** was replaced by `goconserver` but is provided for completeness and backward
  compatibility. Core packages depend on `goconserver`; to use conserver you must install
  `conserver-xcat` explicitly (it is **not** pulled in as a dependency), disable the `goconserver`
  service and enable the `conserver` service.

# References

- [mock project repository](https://github.com/rpm-software-management/mock)
- [sbuild / schroot](https://wiki.debian.org/sbuild)
