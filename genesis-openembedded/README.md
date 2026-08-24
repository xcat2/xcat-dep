# OpenEmbedded Genesis packages

xCAT builds the Genesis image in `xcat-core`. This directory turns those build
outputs into packages and feeds them into the xcat-dep repositories.

Run the release builder on a host that can build the OpenEmbedded layer. The
xcat-core checkout must be clean. `--xcat-ref` checks that the checkout points
to the intended commit; it does not change the checkout for you.

The packaging scripts use `File::Slurper` and `IPC::Cmd`. Install
`libfile-slurper-perl` on Ubuntu. On EL, install `perl-File-Slurper` and
`perl-IPC-Cmd` from EPEL and AppStream.

```bash
./genesis-openembedded/build \
  --xcat-source /path/to/xcat-core \
  --xcat-ref <tag-or-commit> \
  --all \
  --work-dir /path/to/oe-work \
  --output-dir /path/to/xcat-genesis-release
```

The default format is `all`, which produces RPM, SRPM, and DEB packages. Use
`--format rpm` or `--format deb` when only one package family is needed. The
supported image architectures are `x86`, `x86_64`, `ppc64`, `ppc64le`,
`armv7hf`, `aarch64`, and `riscv64`.

Use `--architecture` for development builds. Repository publication requires a
complete release built with `--all`.

Each package installs one exact-architecture export under
`/opt/xcat/share/xcat/netboot/genesis-openembedded/<architecture>/`. The package
and install namespaces are separate from the old Genesis packages, so both
generations can be published and installed without replacing one another. The
packages are `noarch` or `all` because they are installed on the management
node, not run on the target node.

`--work-dir` keeps the OpenEmbedded downloads and build state between release
builds. Without it, the builder uses a temporary directory and removes it when
the command finishes.

The release directory contains:

- `rpm/`, `srpm/`, and `deb/` package directories
- `release.manifest`, including the xcat-core commit
- `SHA256SUMS`

Validate the directory before publishing it:

```bash
./genesis-openembedded/verify-release --complete /path/to/xcat-genesis-release
```

The checksum file detects incomplete or changed output. It does not authenticate
the release, so only accept a directory produced by a trusted build host.

`verify-release` also checks the identity of each package, including a fixed
build host and a build time taken from the source epoch. Those are reproduced
by rpm 4.14.3, 4.16.1.3, 4.19.1.1 and 6.0.2, so an EL8 or later builder -- and
a current Fedora one -- produces a release the verifier accepts.

Pass that same directory to the repository builders:

```bash
perl ./mockbuild-all.pl \
  --genesis-release /path/to/xcat-genesis-release \
  [other build options]

./build-apt-repo.sh \
  --genesis-release /path/to/xcat-genesis-release \
  [DIST ...]
```

The RPM builder keeps its old per-EL Genesis build and adds the new packages.
The APT builder does the same for each selected suite. Both consumers require
all seven architectures and verify package identities and checksums before
collecting packages. Every management-node repository receives every target
image so it can provision nodes of another architecture.

Without `--genesis-release`, both builders keep their existing behavior. The
new packages do not provide, replace, or obsolete the old package names. A
separate xcat-core change will select the OpenEmbedded package and install
namespace after the repositories carry it. Generated images and packages
belong in release storage, not in Git.

Run the package tests on a Linux builder with RPM, DEB, and repository tools:

```bash
prove t/build_utils.t
prove -It/lib t/genesis_openembedded_release.t
sudo -E prove -It/lib t/genesis_openembedded_consumer.t
```
