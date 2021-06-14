Name:           xnba-undi
Version:        1.20.1 
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


Source:  xnba-1.20.1.tar.bz2 
Patch1:  ipxe-branding.patch
Patch2:  ipxe-machyp.patch
Patch3:  ipxe-xnbaclass.patch
Patch4:  ipxe-dhcp.patch
Patch5:  ipxe-verbump.patch

%description
The xCAT Network Boot Agent is a slightly modified version of iPXE.  It provides enhanced boot features for any UNDI compliant x86 host.  This includes iSCSI, http/ftp downloads, and iPXE script based booting.

%prep

%setup  -n xnba-1.20.1 
%patch1 -p1
%patch2 -p1
%patch3 -p1
%patch4 -p1
%patch5 -p1

%build

rm -rf %{buildroot}

cd src
make bin/undionly.kkpxe
make bin-x86_64-efi/snponly.efi


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
