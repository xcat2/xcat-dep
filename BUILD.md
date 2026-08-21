# Build Guide (xcat-dep)

This guide explains how to build, validate, and package the **xcat-dep** dependency packages
with `mockbuild-all.pl` — the RPM build orchestrator for EL targets, driven by `mock`.

The full xCAT **core** is NOT built here — it is built and published separately by the
xcat-core pipeline. `mockbuild-all.pl` builds only the dependency packages plus the
OS-dependent `xCAT-genesis-base` (pulled individually out of the xcat-core source tree).

# Purpose

`mockbuild-all.pl` is the top-level build orchestrator for the **xcat-dep** RPM repository.
It builds the dependency RPMs and the OS-dependent `xCAT-genesis-base`, then assembles:

- a binary RPM repo tree with repodata
- an SRPM repo tree with repodata
- one binary repo tarball and one SRPM repo tarball

# Historical Context

The deployment flow uses two separate repositories:

- `xcat-core` for xCAT packages (built by the xcat-core pipeline)
- `xcat-dep` for dependency packages (built here)

An earlier iteration of this script also built the full xCAT core into one unified tree
(via a `--skip-xcat` toggle). That is gone: the core is always built by the xcat-core
pipeline now, and `mockbuild-all.pl` builds only xcat-dep plus `xCAT-genesis-base`.

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
- `<REPO_ROOT>/conserver/mockbuild.pl`
- `<REPO_ROOT>/xnba/mockbuild.pl`
- `<REPO_ROOT>/mockbuild-perl-packages.pl`
- `<XCAT_SOURCE>/buildrpms.pl` — only to build the OS-dependent `xCAT-genesis-base` package (unless `--skip-genesis` is set); the full xCAT core is built separately by the xcat-core pipeline, not here.

Each build path uses `mock` for chroot isolation. Top-level steps are parallelized by `mockbuild-all.pl`, and perl dependency builds are also parallelized internally by `mockbuild-perl-packages.pl`.

## Per-target package manifest

`packages-manifest.conf` (repo root) declares, per target, exactly which packages are required —
one `[<target>]` section (matching `--target`, e.g. `[alma+epel-10-x86_64]`) of
`<package>=<version|*>` lines. For each target, `mockbuild-all.pl` builds **only** the packages
listed for it; a package absent from a target's section is not built for that target (the per-EL
perl set differs because the OS/EPEL already provides some modules). Note `conserver-xcat` is **not**
pulled in by `dnf install xCAT` (goconserver superseded it), yet it is listed in — and therefore
built for — every target, because some deployments still use it. The lists were derived empirically — on a clean MN of each
(EL, arch), `dnf install xCAT` from xcat.org latest, and the packages whose `from_repo=xcat-dep`
are exactly the required set. See the file header for details.

Build failures are **not tolerated**: any required (manifest) package that fails to build fails
the whole run.

`mockbuild-all.pl` does more than building RPMs. In a default run it performs these stages:

1. Optional chroot cleanup (`--scrub-all-chroots`)
2. Parallel build execution — only the target's manifest packages; any failure fails the run
3. Post-build chroot scrub — reclaims each build step's mock chroot (unless `--keep-buildroots`)
4. Binary RPM collection into `repo/<ARCH>/`
5. Source RPM collection into `repo-src/`
6. `createrepo --update` on both repo trees
7. Tarball creation for both repo trees
8. Summary generation (`summary.txt`)

The build process does **not** install any built RPM onto the build host. Installing an EL8/EL9
package on the (single, possibly EL10) build host corrupts the host RPM database; the real
install-and-run verification happens in the CI's separate Test phase (`cluster-test.pl` boots a
matching MN and installs xCAT + the freshly built xcat-dep there).

# Packages notes

- **`pyodbc`** is intentionally not built or listed in any target's manifest: modern EL provides
  `python3-pyodbc` from appstream/EPEL, so xcat-dep no longer ships its own. The legacy `pyodbc/`
  directory (an old `pyodbc-3.0.7` RPM spec) is kept for historical reference only.
- **`conserver-xcat`** was replaced by `goconserver` but is provided for completeness and backward
  compatibility. Core packages depend on `goconserver`; to use conserver you must install
  `conserver-xcat` explicitly (it is **not** pulled in as a dependency), disable the `goconserver`
  service and enable the `conserver` service.

# Skip and Control Flags

Use these flags to skip specific operations:

- `--skip-genesis`
  - Skips the `xCAT-genesis-base` build (`<XCAT_SOURCE>/buildrpms.pl --package xCAT-genesis-base`).
- `--skip-xcat-dep`
  - Skips non-perl xcat-dep package builders (`elilo`, `grub2-xcat`, `ipmitool-xcat`, `syslinux-xcat`, `goconserver`, `conserver-xcat`, `xnba-undi`).
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
- `--keep-buildroots`
  - Keeps each build step's mock chroot after the build instead of scrubbing it. By default,
    after the parallel build phase every step's buildroot (dep packages, the per-package perl
    chroots, and `xCAT-genesis-base`) is reclaimed with
    `mock -r <CHROOT> --uniqueext <EXT> --scrub=chroot --scrub=bootstrap` — a lock-safe scrub (a
    chroot still held by a concurrent build is refused and skipped). Both the build chroot and its
    per-uniqueext bootstrap chroot are removed (each build step gets its own bootstrap, so both
    must go); the shared root cache under `/var/cache/mock` is kept so rebuilds stay fast. This
    stops `/var/lib/mock` from growing unbounded across runs. Pass `--keep-buildroots` to preserve
    a buildroot for debugging a failed build.
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

If you will build the `xCAT-genesis-base` package (that is, you will **not** use `--skip-genesis`), install xCAT build dependencies:

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

By default (no `--target`), `mockbuild-all.pl` builds all three EL releases for the host
arch: `rh8`, `rh9`, and `rh10`. Pass `--target <TARGET>` to build a single target instead; it
takes **one** value and is not repeatable — run the script once per target to build several, or
omit it to build all three.

# Build the Dependency Repository

`mockbuild-all.pl` builds the xcat-dep packages (dep packages, perl packages, and the
OS-dependent `xCAT-genesis-base`). The full xCAT core is **not** built here — it is built and
published separately by the xcat-core pipeline.

```bash
cd /root/xcat-dep
perl ./mockbuild-all.pl \
  --repo-root /root/xcat-dep \
  --xcat-source /root/xcat-dep/xcat-source-code \
  --scrub-all-chroots
```

Notes:

- The build never installs a built RPM onto the build host (see above); install-and-run
  verification is the CI Test phase's job.
- Add `--skip-genesis` to skip the `xCAT-genesis-base` build (the only step that invokes
  `<XCAT_SOURCE>/buildrpms.pl`).
- `<RUN_ID>` is optional; when omitted it is timestamp-based.

# Common Build Modes

xcat-dep repo:

```bash
cd <REPO_ROOT>
perl ./mockbuild-all.pl \
  --repo-root <REPO_ROOT> \
  --xcat-source <XCAT_SOURCE> \
  --scrub-all-chroots
```

Dependency repo without the `xCAT-genesis-base` build:

```bash
cd <REPO_ROOT>
perl ./mockbuild-all.pl \
  --repo-root <REPO_ROOT> \
  --xcat-source <XCAT_SOURCE> \
  --scrub-all-chroots \
  --skip-genesis
```

Collection-only pass from existing build artifacts:

```bash
cd <REPO_ROOT>
perl ./mockbuild-all.pl \
  --repo-root <REPO_ROOT> \
  --xcat-source <XCAT_SOURCE> \
  --skip-build
```

# Cross-arch genesis-base (`--finalize-xcat-dep`)

`xCAT-genesis-base` is a noarch package whose *name* carries the target arch
(`xCAT-genesis-base-x86_64`, `xCAT-genesis-base-ppc64` — xCAT collapses `ppc64le` to `ppc64`
via `tarch`; there is no big-endian code in it). A management node must be able to netboot
nodes of the *other* arch, so — as in 2.17 — the `x86_64` dep repo must also ship the
`ppc64` genesis and the `ppc64le` dep repo must ship the `x86_64` genesis.

Each arch is built on its own build host, so once both per-arch repos exist, run a final,
build-free pass that cross-copies the noarch genesis between them and re-indexes + re-signs
the affected repos:

```bash
perl ./mockbuild-all.pl --finalize-xcat-dep \
  --x86_64-repo  <x86_64 repo root holding <os>/x86_64> \
  --ppc64le-repo <ppc64le repo root holding <os>/ppc64le> \
  --gpg-sign --gpg-key-name "xCAT Signing Key" --gpg-home <GNUPGHOME>
```

- If both arches were built into one shared tree, pass the same path to both options.
- Idempotent: a repo pair already carrying the fresh foreign-arch genesis is left untouched;
  any stale foreign-arch genesis is dropped before the fresh one is copied in.
- It builds nothing and holds no output lock — use it alone.

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

# Tests

The reusable, side-effect-free helpers live in `MockBuildUtils.pm` (package selection under the
`--skip-*` flags, version-pin matching incl. globs, RPM-identity comparison, and the cross-arch
genesis `finalize` logic). Focused fixture tests cover them:

```bash
prove t/            # or: perl t/mockbuild-all.t
```

The RPM-identity / `cross_copy_genesis` cases build tiny fixture rpms and are skipped
automatically if `rpmbuild` is unavailable.

# Repository verification gate

After each per-target repo is built + signed, `mockbuild-all.pl` runs a **manifest-driven gate** that
fails the build if the published repo is incomplete or mis-signed. It uses `packages-manifest.conf` as
the single source of truth and is layered so the decision logic is pure and unit-tested
(`MockBuildUtils::verify_repo_packages` / `verify_repo_signature`), separate from the disk/gpg I/O.

- **Runs automatically** at the end of `deploy_target` (per `rh<N>/<arch>` cell). Suppress with
  `--no-verify-repo`. Verify an already-built repo out of band with `--verify-repo=<repo>`
  (target derived from the `rh<N>/<arch>` path, or pass `--target`; manifest from `<repo-root>/
  packages-manifest.conf`; key/home from `--gpg-key-name`/`--gpg-home`).
- **Completeness:** every package the target's manifest section requires (after `required_pkgs`
  skip-filtering) must be present with a version satisfying its pin.
- **Signature:** the repo's `repodata/repomd.xml.asc` must be a *good* signature whose **primary-key
  fingerprint equals the fingerprint of `--gpg-key-name`** — i.e. the repo was signed by exactly the
  CLI key. Expired/revoked keys and expired signatures are rejected (not just `VALIDSIG`). If the CLI
  key cannot be resolved to a fingerprint (not in the keyring) the gate fails (`SIGKEY`), never passes.

**Semantic idiosyncrasies (intentional, and mirrored in the Ubuntu `sbuild-all.pl` gate):**

- **What "the repo" is:** the EL gate reads the **binary rpm files** in the per-target dir (via
  `rpm_version`); the Ubuntu gate reads the **published `binary-<arch>/Packages` index**. Both check
  the artifact that ships; they differ only in the RHEL-vs-Debian notion of "the repository".
- **Duplicate = hard error:** if a required package appears with **two distinct versions** (a stale
  artifact not cleaned before the build), the gate **dies loudly** rather than silently picking one —
  identical on both EL (`rpm_version`) and Ubuntu (`parse_packages_index`).
- **Version pins** are the manifest's *upstream* version; the Debian gate strips the epoch/revision
  (`deb_upstream_version`) before comparing, the EL gate compares `%{version}` directly.

# References

- [mock project repository](https://github.com/rpm-software-management/mock)
