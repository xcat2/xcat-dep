# The payload is the upstream release, byte for byte: signed EFI files must not be stripped or
# otherwise touched by the build-root policy scripts.
%global debug_package %{nil}
%global __os_install_post %{nil}

Name:           ipxe-xcat
Version:        2.0.0
Release:        1
Summary:        iPXE network boot binaries from the upstream release
License:        GPL-2.0-only AND GPL-2.0-or-later AND BSD-2-Clause AND BSD-2-Clause-Patent AND BSD-3-Clause AND MIT AND OpenSSL
URL:            https://ipxe.org/
BuildArch:      noarch

Source0:        ipxeboot-%{version}.tar.gz
Source1:        ipxe-%{version}-source.tar.gz
Source2:        licenses/ipxe/COPYING
Source3:        licenses/ipxe/COPYING.GPLv2
Source4:        licenses/ipxe/COPYING.UBDL
Source5:        licenses/shim/COPYRIGHT
Source6:        licenses/shim/openssl/LICENSE
Source7:        licenses/shim/gnu-efi/README.efilib

%description
The ipxeboot.tar.gz tree of the iPXE %{version} release, installed unchanged
under /tftpboot/xcat/ipxe. It carries the signed Secure Boot builds and
their shim. The source archive of the release tag is installed with the
documentation.

%prep
%setup -q -c -T
install -D -m 0644 %{SOURCE2} licenses/ipxe/COPYING
install -D -m 0644 %{SOURCE3} licenses/ipxe/COPYING.GPLv2
install -D -m 0644 %{SOURCE4} licenses/ipxe/COPYING.UBDL
install -D -m 0644 %{SOURCE5} licenses/shim/COPYRIGHT
install -D -m 0644 %{SOURCE6} licenses/shim/openssl/LICENSE
install -D -m 0644 %{SOURCE7} licenses/shim/gnu-efi/README.efilib

%build

%install
mkdir -p %{buildroot}/tftpboot/xcat/ipxe
tar -xzf %{SOURCE0} --no-same-owner --strip-components=1 -C %{buildroot}/tftpboot/xcat/ipxe
install -D -m 0644 %{SOURCE1} %{buildroot}%{_pkgdocdir}/ipxe-%{version}-source.tar.gz

%files
/tftpboot/xcat/ipxe
%license licenses/ipxe licenses/shim
%dir %{_pkgdocdir}
%doc %{_pkgdocdir}/ipxe-%{version}-source.tar.gz

%changelog
* Fri Sep 25 2026 xCAT <xcat-user@lists.sourceforge.net> - 2.0.0-1
- Package the ipxeboot.tar.gz tree of the iPXE v2.0.0 release
