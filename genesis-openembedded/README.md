# OpenEmbedded Genesis packages

xCAT builds the Genesis image in `xcat-core`. This directory turns those build
outputs into packages and feeds them into the xcat-dep repositories.

Run the release builder on a host that can build the OpenEmbedded layer. The
xcat-core checkout must be clean. `--xcat-ref` checks that the checkout points
to the intended commit; it does not change the checkout for you.

```bash
./genesis-openembedded/build \
  --xcat-source /path/to/xcat-core \
  --xcat-ref <tag-or-commit> \
  --all \
  --output-dir /path/to/xcat-genesis-release
```

The default format is `all`, which produces RPM, SRPM, and DEB packages. Use
`--format rpm` or `--format deb` when only one package family is needed. The
supported image architectures are `x86`, `x86_64`, `ppc64`, `ppc64le`,
`armv7hf`, `aarch64`, and `riscv64`.

Use `--architecture` for development builds. Repository publication requires a
complete release built with `--all`.

Each package installs one exact-architecture export under
`/opt/xcat/share/xcat/netboot/genesis/<architecture>/`. This includes the kernel,
initramfs, manifests, checksums, and license evidence. The packages are `noarch`
or `all` because they are installed on the management node, not run on the
target node.

The release directory contains:

- `rpm/`, `srpm/`, and `deb/` package directories
- `release.manifest`, including the xcat-core commit
- `SHA256SUMS`

Validate the directory before publishing it:

```bash
./genesis-openembedded/verify-release /path/to/xcat-genesis-release
```

Pass that same directory to the repository builders:

```bash
perl ./mockbuild-all.pl \
  --genesis-release /path/to/xcat-genesis-release \
  [other build options]

./build-apt-repo.sh \
  --genesis-release /path/to/xcat-genesis-release \
  [DIST ...]
```

The RPM builder skips its old per-EL Genesis build when a release is supplied.
The APT builder adds the DEB packages to every selected suite. Both consumers
require all seven architectures and verify package identities and checksums
before collecting packages. Every management-node repository receives every
target image so it can provision nodes of another architecture.

Without `--genesis-release`, both builders keep their existing behavior. The
option remains opt-in until xcat-core uses the exact package names on every
platform. The current RPM naming already matches `x86_64`, but older mappings
still use `ppc64` for `ppc64le`, and the DEB packages use `amd64`. Those mappings
belong in a separate xcat-core change. Generated images and packages belong in
release storage, not in Git.

The DEB packages replace the old `amd64` and `ppc64el` package spellings during
an upgrade. They do not provide aliases for those names. This keeps the old
workflow unchanged until the xcat-core package dependencies move to the exact
architecture names.

Run the package tests on a Linux builder with RPM, DEB, and repository tools:

```bash
sudo prove -It/lib t
```
