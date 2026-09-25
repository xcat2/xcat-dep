`python-scp-0.14.5-1.oe2403.src.rpm` is the unchanged openEuler 24.03 LTS
source package, rebuilt for openEuler 20.03 LTS SP4, whose native repositories
do not provide `python3-scp`.

- Source: https://repo.openeuler.org/openEuler-24.03-LTS/source/Packages/python-scp-0.14.5-1.oe2403.src.rpm
- SHA256: `3461d2a3fe0122cac2893d8465ad1271ae21e5570a31d4402e3f887ef545a0e8`
- Upstream signing key: `8AA16BF9F2CA5244010DCA963B477C60B675600B`
- License: LGPL-2.1-or-later

The upstream spec disables its SSH-dependent `%check`. Native validation must
include authenticated SCP uploads and downloads, recursive paths, mode and time
preservation, and rejection of incorrect client and server keys. The build uses
the target's native Python and Paramiko packages.
