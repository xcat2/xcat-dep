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
- `--skip-genesis`
  - Skips the existing per-EL Genesis image build.
- `--genesis-release <PATH>`
  - Adds a verified OpenEmbedded Genesis RPM release alongside the existing
    per-EL Genesis packages.
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
- `--force-unlock`
  - Removes a stale lock after the previous publisher has been checked.

# Prerequisites

- Run as `root`.
- `mockbuild-all.pl` and package sources present under `<REPO_ROOT>`.
- xCAT sources present under `<XCAT_SOURCE>`.

Install baseline tooling — let the script do it, so the list cannot drift from what it loads:

```bash
./mockbuild-all.pl --install-deps        # as root, once per build host
```

It installs the toolchain and the Perl modules for this host's package manager (dnf on EL, zypper
on SUSE), then **loads** each module and fails if one is still missing. That last step is the point:
a missing module surfaces otherwise as a compile-time abort inside `XCAT::BuildUtils`, in the middle
of a CD run, which is how `perl-File-Slurper` and `perl-IPC-Cmd` each took a pipeline down. The
equivalent by hand:

```bash
dnf -y install perl perl-File-Slurper perl-IPC-Cmd \
  perl-Parallel-ForkManager mock createrepo tar rpm-build rpmdevtools \
  dnf-plugins-core wget git
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
  --publish --expect-arch "amd64 ppc64el riscv64" \
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
missing, and then builds the `[rocky-10-riscv64-xcat]` section of `packages-manifest.conf`
(as every target does -- a target with no section there is fatal):

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
  --skip-xcat --skip-genesis \
  --max-parallel 8
```

Outputs (as for every target): the build tree under `<OUTPUT>/mockbuild-all/` and the
deployable repo `<OUTPUT>/xcat-dep/rh10/riscv64/` (rpms, `repodata/`, `xcat-dep.repo` with
`baseurl=https://xcat.org/files/xcat/repos/yum/devel/xcat-dep/rh10/riscv64`,
`mklocalrepo.sh`, `buildinfo.txt`). Builder failures are tolerated and listed at the end.
The cross-built rpms are smoke-tested without installing them on the host: ipmitool-xcat,
conserver-xcat and the XS perl modules inside the emulated chroot, goconserver by running
its binaries through the binfmt handler. No build step installs an rpm on the build host
(see "Per-target package manifest").

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

# Repository verification gate (EL)

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
- **Build runs stage; publishing is a separate, locked, atomic step.** The arches build
  *concurrently* against the same `--apt-dir`, so an arch build run **never publishes**: it fills staging and stops. Publishing happens with **`--publish`** (implied by
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
  (detected via `control_binary_arch`), so ppc64el and riscv64 build only the genuinely
  arch-specific compiled deps (`ipmitool-xcat`, `conserver-xcat`, `goconserver`) yet still verify the
  boot components they need. The riscv64 sections require `grub2-xcat` only: the x86 loaders
  (`syslinux-xcat`, `elilo-xcat`, `xnba-undi`) are not part of a riscv64 repository.
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
  `amd64` and, through qemu-user, for `riscv64`; the ppc host for `ppc64el`).
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

## riscv64: cross-building on an amd64 host

There is no riscv64 Ubuntu build host in the xCAT build farm, so the riscv64 packages are
cross-built on the amd64 host. `sbuild-all.pl` bootstraps a riscv64 `schroot` with
`debootstrap --arch=riscv64`, and every command inside it -- debootstrap's second stage,
`apt-get`, `dpkg-buildpackage` -- runs through the `qemu-riscv64` binfmt handler, so each package
is compiled by the chroot's own riscv64 toolchain.

`--install-deps` installs `qemu-user-static` and `binfmt-support` with the rest of the toolchain.
Confirm the handler before the first riscv64 run:

```bash
cat /proc/sys/fs/binfmt_misc/qemu-riscv64        # enabled, flags: POF
```

The `F` flag is what makes the handler usable from a chroot: the kernel opens the interpreter when
the handler is registered, so the static QEMU binary does not have to exist under the chroot root.
Without a registered handler `sbuild-all.pl` refuses to create the chroot and names the handler and
the packages that provide it, instead of failing deep inside debootstrap.

`archive.ubuntu.com` carries amd64 and i386 only; every other architecture is on
`ports.ubuntu.com/ubuntu-ports`. The bootstrap mirror is defaulted from `--arch`, so a riscv64 run
needs no `--mirror`.

| what | how |
|---|---|
| ipmitool-xcat, conserver-xcat | `dpkg-buildpackage` in the emulated riscv64 chroot |
| goconserver | same chroot, compiled by the Go toolchain the chroot installs for riscv64 |
| grub2-xcat (`Architecture:all`) | built once on amd64 and assembled into the riscv64 index; listed in the riscv64 manifest sections as required-present, because a riscv64 management node needs it to netboot |
| syslinux-xcat, elilo-xcat, xnba-undi | not built and not required (x86 loaders) |
| xcat-genesis-base | not built: no riscv64 section names it, and the build skips the step when the manifest does not ask for it, so `--skip-genesis` is unnecessary here |

The riscv64 ipmitool-xcat deb is installed into the chroot that built it and
`/opt/xcat/bin/ipmitool-xcat -V` runs there before the run is called good. A cross-built binary
links against the target's loader and libraries, so the chroot is the only place it can run at all,
and without that check a deb whose binary never executes still builds green.

Emulated builds are slow. On an 8-core amd64 host, bootstrapping the noble riscv64 chroot took
about 4 minutes and ipmitool-xcat about 12, against seconds natively, so plan a riscv64 run of the
whole dependency set in hours rather than minutes. `--build-timeout` sets the per-package
wall-clock bound. A build that deadlocks under qemu-user is killed with a stall report rather than
hanging the pipeline, which is what goconserver did.

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

# riscv64 — cross-built on the amd64 host (there is no riscv64 build host); arch-specific deps
# only, and the genesis step is skipped by the manifest rather than by a flag:
./sbuild-all.pl --arch riscv64 --dists "focal jammy noble resolute"
```

These runs touch **only** `staging/<codename>/<arch>/`; the apt tree at `--apt-dir` is left alone, so
they can run at the same time. The build lock is per arch, so the amd64 and riscv64 runs can share
one host. `--dists` may be omitted entirely — with no
`--dists`/`--target`, **all supported codenames** are built (`focal jammy noble resolute`).

### Step 2 — publish once, after every arch has staged

```bash
./sbuild-all.pl --skip-build --skip-genesis \
  --publish --expect-arch "amd64 ppc64el riscv64" \
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

# Repository verification gate (Ubuntu)

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


# References

- [mock project repository](https://github.com/rpm-software-management/mock)
- [sbuild / schroot](https://wiki.debian.org/sbuild)
