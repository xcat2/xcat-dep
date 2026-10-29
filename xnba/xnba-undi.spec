Name:           xnba-undi
Version:        1.21.1 
Release:        1
Summary:        xCAT Network Boot Agent for x86 PXE hosts

Group:          System Environment/Kernel
License:        GPL
URL:            https://ipxe.org/ipxe.git
BuildRoot:      %{_tmppath}/%{name}-%{version}-%{release}
BuildArch:	noarch

%define Distribution %(rpm -q -qf /etc/redhat-release --qf '%%{name}' | cut -d"-"  -f 1)
%define os_version %(rpm -q --qf '%%{version}' %{Distribution}-release)
%define os_release %(rpm -q --qf '%%{release}' %{Distribution}-release | cut -d"." -f 1)


Source:  xnba-1.21.1.tar.bz2 
Patch1:  ipxe-branding.patch
Patch2:  ipxe-machyp.patch
Patch3:  ipxe-xnbaclass.patch
Patch4:  ipxe-dhcp.patch
Patch5:  ipxe-verbump.patch
Patch6:  ipxe-binutils-2.41-compat.patch

BuildRequires: make
BuildRequires: gcc
BuildRequires: binutils
BuildRequires: perl
BuildRequires: xz-devel

%description
The xCAT Network Boot Agent is a slightly modified version of iPXE.  It provides enhanced boot features for any UNDI compliant x86 host.  This includes iSCSI, http/ftp downloads, and iPXE script based booting.

%prep

%setup  -n xnba-1.21.1 
%patch1 -p1
%patch2 -p1
%patch3 -p1
%patch4 -p1
%patch5 -p1
%patch6 -p1

# iPXE builds with NET_PROTO_IPV6 off: src/config/general.h comments the define out. The
# loader then has no IPv6 at all, so a node that netboots over IPv6 reaches xNBA and stops
# at "No configuration methods succeeded" without ever sending a DHCPv6 solicit.
#
# config/local/general.h is included after the defaults, so it is the place to turn the
# protocol on. The guard keeps it out of undionly.kkpxe: a BIOS PXE ROM has a size limit to
# respect, and BIOS PXE has no IPv6 form to use it with.
mkdir -p src/config/local
cat > src/config/local/general.h <<'XNBALOCALCONFIG'
#if defined ( PLATFORM_efi )
#define NET_PROTO_IPV6
#endif
XNBALOCALCONFIG

%build

rm -rf %{buildroot}

cd src
make NO_WERROR=1 bin/undionly.kkpxe
make NO_WERROR=1 bin-x86_64-efi/snponly.efi


%install

mkdir -p  %{buildroot}/tftpboot/xcat
#Rename to avoid conflicting with potential vanilla undionly.kpxe that user may be using
cp src/bin/undionly.kkpxe %{buildroot}/tftpboot/xcat/xnba.kpxe
cp src/bin-x86_64-efi/snponly.efi %{buildroot}/tftpboot/xcat/xnba.efi


%post 

%preun

%clean
%{__rm} -rf %{buildroot}

%files
/tftpboot/xcat/xnba.kpxe
/tftpboot/xcat/xnba.efi
%changelog
