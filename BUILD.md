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

The APT side takes the same option, on the run that **publishes**:

```bash
./sbuild-all.pl --skip-build --skip-genesis \
  --publish --expect-arch "amd64 ppc64el" \
  --genesis-release /path/to/xcat-genesis-release \
  --gpg-sign --gpg-key-id <id> --gpg-home <gpg-home>
```

The debs are published **once**, under `pool/main/xcat-genesis-openembedded`, and
every suite's `Packages` index points at that one copy — they are
`Architecture: all` and identical for every codename. Because every suite indexes
it, a release must be published for all of them: a run whose `--dists` omits a
suite is refused rather than leaving that suite indexing retired files. Each
package is copied and re-checked against the release checksums while the publish
lock is held, so what is indexed and signed is what was verified, and anything
staged under the OpenEmbedded Genesis package name is dropped: the release is the
only source of those packages. `sbuild-all.pl` loads the release reader only when
the option is used, so an apt build without it does not need `perl-File-Slurper`
on the build host.

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
- **Build runs stage; publishing is a separate, locked, atomic step.** The two arches build
  *concurrently* on their two hosts against the same `--apt-dir`, so an arch build run **never
  publishes**: it fills staging and stops. Publishing happens with **`--publish`** (implied by
  `--skip-build`, i.e. the finalization run). That step takes **one global publish lock** — not the
  per-arch build lock — assembles the whole tree into a **side directory**, runs the repo gate against
  *that* tree, and only then swaps it onto `--apt-dir` with a single `rename(2)`. Readers therefore
  see either the previous complete repo or the new complete repo, never a half-wiped `pool/` or an
  index that disagrees with its `Release`; a failed gate leaves the published tree untouched.
  Codenames outside `--dists` survive the swap. `--skip-createrepo` forces "do not publish".
- **Clean, disposable build environment per package.** Every package builds in its own `schroot`
  session, and the chroot must hand out a **throwaway** session (`union-type=overlay`, or a
  snapshot/tarball chroot). `sbuild-all.pl` repairs a chroot that lacks one and hard-fails if it still
  is not disposable. That is what makes the fail-hard dependency handling mean something: inside the
  session `apt-get update`, the common build tooling and the package's `Build-Depends` (resolved with
  `mk-build-deps`, so version constraints, `a | b` alternatives and arch qualifiers are honoured) are
  all **fatal** on failure — and since nothing survives the session, a package whose `debian/control`
  forgets a `Build-Depends` cannot build green on a sibling package's leftovers.
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
- **`t/sbuild-all.t`** — unit tests for the pure helpers (`prove t/`).
- **`t/verify-repo.t`** — end-to-end tests of the repo gate against fixture apt trees (missing
  secondary arch, arch:all-only index, unsigned repo, missing manifest section).

## Prerequisites (once per build host, as root)

```bash
./sbuild-all.pl --install-deps
```

Installs the sbuild/schroot toolchain and the Perl modules the script loads, then **loads** each one
and fails if any is still missing. That last step is the point: a missing module surfaces otherwise
as a compile-time abort inside `XCAT::BuildUtils`, mid-run — which is how `File::Slurper` being
absent on `xcat-master-ub` took a CD run down. `IPC::Cmd` is deliberately not in the package list:
it is core on Debian/Ubuntu, no such package exists, and naming one fails the whole install; the
probe is what asserts it is usable.

The per-codename sbuild chroots are separate host state — see `ci/mk-dep-chroots.sh`.

## Usage (per arch, as root on the matching build host)

Run `sbuild-all.pl` on the build host for the arch you are building (amd64 on the x86 Ubuntu host,
ppc64el on the ppc Ubuntu host). The Ubuntu version(s) to build are selected with **`--dists`** (a
space/comma list of codenames) or, for exactly one, **`--target <codename>-<arch>`**. Version ↔
codename: `20.04`=`focal`, `22.04`=`jammy`, `24.04`=`noble`, `26.04`=`resolute`.

The full flow is **two steps**: each arch builds into staging on its own host, then **one**
finalization step publishes the assembled repo atomically.

### Step 1 — build each arch into staging (no publishing)

```bash
# amd64 host — build focal+jammy+noble+resolute into staging:
./sbuild-all.pl --arch amd64 --dists "focal jammy noble resolute" \
  --xcat-source ../xcat-core --genesis-rpm <xCAT-genesis-base-x86_64 rpm> \
  --genesis-rpm-ppc <xCAT-genesis-base-ppc64 rpm>

# ppc64el host — arch-specific deps only (the Architecture:all boot components and both genesis
# debs come from the amd64 build):
./sbuild-all.pl --arch ppc64el --dists "focal jammy noble resolute" --skip-genesis
```

These runs touch **only** `staging/<codename>/<arch>/`; the apt tree at `--apt-dir` is left alone, so
the two hosts can run at the same time. `--dists` may be omitted entirely — with no
`--dists`/`--target`, **all supported codenames** are built (`focal jammy noble resolute`).

### Step 2 — publish once, after every arch has staged

```bash
./sbuild-all.pl --skip-build --skip-genesis \
  --publish --expect-arch "amd64 ppc64el" \
  --gpg-sign --gpg-key-id xcat@example.com --gpg-home <gpg-home>
```

This takes the global publish lock, assembles + signs both arches' staging into a side tree, gates it,
and swaps it onto `--apt-dir` atomically. `--expect-arch` states which architectures the published
repo must serve — omit it and the staged arch set is used instead. (`--publish` is implied here
because the run builds nothing; state it explicitly if you want to build **and** publish in one go.)

### Build ONE specific Ubuntu version

```bash
# just 24.04 (noble) on amd64 — two equivalent forms:
./sbuild-all.pl --arch amd64 --dists noble  --xcat-source ../xcat-core --genesis-rpm <rpm>
./sbuild-all.pl --target noble-amd64        --xcat-source ../xcat-core --genesis-rpm <rpm>

# just 20.04 (focal):
./sbuild-all.pl --arch amd64 --dists focal  ...
```

### Handy variants

```bash
./sbuild-all.pl --dry-run --arch amd64 --dists noble               # print the plan, do nothing
./sbuild-all.pl --skip-build --skip-genesis --gpg-sign ...         # publish-only (re-index/re-sign staging)
./sbuild-all.pl --skip-build --skip-genesis --publish \
  --genesis-release <release-dir> ...                              # publish an OpenEmbedded Genesis release too
# single host: build AND publish in one go
./sbuild-all.pl --arch amd64 --dists noble --genesis-rpm <rpm> \
  --publish --expect-arch amd64 --gpg-sign --gpg-key-id <id> --gpg-home <dir>
```

`sbuild-all.pl --help` lists every option and `sbuild-all.pl --man` (or `perldoc sbuild-all.pl`)
prints the full manual; the shared flags (`--repo-root`, `--manifest`,
`--skip-build/-install/-genesis/-xcat-dep`, `--build-number`, `--gpg-sign`, `--dry-run`, …) match
`mockbuild-all.pl`.

# Repository verification gate

Before an assembled repo is published, `sbuild-all.pl` runs a **manifest-driven gate** that fails the
build if the repo is incomplete, serves the wrong architectures, or is mis-signed. It uses
`debs-manifest.conf` as the single source of truth and is layered so the decision logic is pure and
unit-tested (`BuildUtils::verify_repo_arches` / `verify_repo_packages` / `verify_repo_signature`;
`parse_packages_index` / `parse_release_architectures` / `resolve_present_names` for
parsing/resolution), separate from the disk/gpg I/O.

- **Runs automatically** inside `--publish`, against the **side tree, before the swap**, per codename ×
  expected arch — so a repo that fails the gate is never published. Suppress with `--no-verify-repo`;
  skipped under `--dry-run`. Verify an already-published tree out of band with
  `--verify-repo=<apt_dir>` (manifest/dists/arches/key from
  `--manifest`/`--dists`/`--expect-arch`/`--gpg-key-id`/`--gpg-home`).
- **Architectures:** the expected set is always a **claim**, never an inference from what happens to
  be present — `--expect-arch` if given, else the staged arch set when publishing, else each
  codename's own `Release` `Architectures:` line when verifying standalone. An expected arch with no
  *native* package is `MISSING-ARCH`; natives for an arch outside the expected set are
  `UNEXPECTED-ARCH` (a stale architecture). This is what makes an **entirely missing secondary
  architecture** a failure instead of reading as "this run did not build it". Note that a non-empty
  `binary-<arch>/Packages` is *not* evidence the arch was built: the `Architecture:all` packages
  (`grub2-xcat`, the genesis debs) ride into every arch's index, so `index_has_native_arch` is what
  counts.
- **Completeness:** for each cell, every package that codename×arch's manifest section requires (after
  `required_pkgs` skip-filtering) must appear in the published `binary-<arch>/Packages` with a version
  satisfying its pin. The arch-suffixed genesis (`xcat-genesis-base`) is resolved to **this cell's
  arch** (`xcat-genesis-base-<arch>`) — never a different arch, so a missing native genesis is caught.
  An expected cell with **no manifest section** is a hard error (`NO-MANIFEST`), not a free pass.
- **Signature:** each `dists/<cn>/InRelease` (or detached `Release`+`Release.gpg`) must be a *good*
  signature whose **primary-key fingerprint equals the fingerprint of `--gpg-key-id`** — the repo was
  signed by exactly the CLI key. Expired/revoked keys and expired signatures are rejected; if the CLI
  key does not resolve to a fingerprint the gate fails (`SIGKEY`), never passes. In the automatic
  pre-swap run a signature is required iff `--gpg-sign` was used (an intentionally-unsigned repo does
  not false-fail); in the **standalone `--verify-repo` mode signatures are checked by default**, and
  `--no-verify-signature` is the explicit opt-out.

**Semantic idiosyncrasies (intentional, and mirrored in the EL `mockbuild-all.pl` gate):**

- **What "the repo" is:** the Ubuntu gate reads the **published `binary-<arch>/Packages` index** (what
  apt serves, per codename×arch); the EL gate reads the **binary rpm files** in the per-target dir.
  Both check the artifact that ships; they differ only in the Debian-vs-RHEL notion of "the repository".
- **Duplicate = hard error:** a package appearing in the index with **two distinct versions** (a stale
  `.deb` not cleaned from the pool) makes `parse_packages_index` **die loudly** rather than keep one —
  identical behaviour to the EL `rpm_version` gate.
- **Version pins** match the **full** Debian version — `[epoch:]upstream[-revision]` — exactly as it
  appears in the built `.deb` and in the published index. The revision is the *packaging* revision
  (`elilo-xcat` 3.14-5 and 3.14-6 are different builds of the same upstream 3.14) and the epoch
  overrides version comparison outright, so an upstream-only pin would accept a deb that the gate
  calls good and `apt install xCAT` then refuses — xCAT's own `debian/control` declares versioned
  dependencies (`goconserver (>= 0.3.3-snap…)`, `ipmitool-xcat (>= 1.8.17-1)`, `grub2-xcat (>= 2.02-…)`).
  Two pins stay globbed on purpose: `goconserver=0.3.3-snap*` (upstream exact; the revision is the CD
  stamp, which changes every run — the glob still *requires* a snap stamp) and `xcat-genesis-base=2.*`
  (its version is not owned by xcat-dep, and each arch is converted from its own genesis rpm).
- **Only build output is collected.** Some package directories carry prebuilt `.deb` files in the
  checkout — `elilo/` ships `elilo-xcat_3.14-5_all.deb` and `gnu-efi_3.0v-5_amd64.deb`. Those arrive
  with the copied source tree and are **not** output of the build, so the collector snapshots the
  `.deb`s present before the build and subtracts them afterwards (a file the build overwrites changes
  size/mtime and still counts). Without this, a stale checked-in artifact is republished under the
  current run's name — and with full-version pins it also collides with the freshly built one.

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
