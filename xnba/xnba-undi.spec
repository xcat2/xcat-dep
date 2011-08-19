Name:           xnba-undi
Version:        1.0.2
Release:        4
Summary:        xCAT Network Boot Agent for x86 PXE hosts
Obsoletes:	gpxe-undi

Group:          System Environment/Kernel
License:        GPL
URL:            http://ipxe.org
BuildRoot:      %{_tmppath}/%{name}-%{version}-%{release}
BuildArch:	noarch

%define Distribution %(rpm -q -qf /etc/redhat-release --qf '%%{name}' | cut -d"-"  -f 1)
%define os_version %(rpm -q --qf '%%{version}' %{Distribution}-release)
%define os_release %(rpm -q --qf '%%{release}' %{Distribution}-release | cut -d"." -f 1)


Source0: xnba-%{version}.tar.bz2

%description
The xCAT Network Boot Agent is a slightly modified version of gPXE.  It provides enhanced boot features for any UNDI compliant x86 host.  This includes iSCSI, http/ftp downloads, and gPXE script based booting.

%prep

%setup  -n xnba-%{version}

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
