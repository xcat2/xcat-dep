Name:           xnba-undi
Version:        0.9.7
Release:        8
Summary:        xCAT Network Boot Agent for x86 PXE hosts
Obsoletes:	gpxe-xcat
Obsoletes:	gpxe-undi

Group:          System Environment/Kernel
License:        GPL
URL:            http://etherboot.org/wiki/index.php
BuildRoot:      %{_tmppath}/%{name}-%{version}-%{release}
BuildArch:	noarch

%define Distribution %(rpm -q -qf /etc/redhat-release --qf '%%{name}' | cut -d"-"  -f 1)
%define os_version %(rpm -q --qf '%%{version}' %{Distribution}-release)
%define os_release %(rpm -q --qf '%%{release}' %{Distribution}-release | cut -d"." -f 1)


Source0: gpxe-0.9.7.tar.gz
Patch0: gpxe-0.9.7-branding.patch
Patch1: gpxe-0.9.7-registeriscsionpxe.patch
Patch2: gpxe-0.9.7-config.patch
Patch3: gpxe-0.9.7-ignorepackets.patch
Patch4: gpxe-0.9.7-kvmworkaround.patch
Patch5: gpxe-0.9.7-hdboot.patch

%description
The xCAT Network Boot Agent is a slightly modified version of gPXE.  It provides enhanced boot features for any UNDI compliant x86 host.  This includes iSCSI, http/ftp downloads, and gPXE script based booting.

%prep

%setup  -n gpxe-%{version}
%patch -p1
%patch1 -p1
%patch2 -p1
%patch3 -p1
%patch4 -p1
%patch5 -p1

%build

rm -rf %{buildroot}

cd src
make bin/undionly.kpxe


%install

mkdir -p  %{buildroot}/tftpboot/xcat
#Rename to avoid conflicting with potential vanilla undionly.kpxe that user may be using
cp src/bin/undionly.kpxe %{buildroot}/tftpboot/xcat/xnba.kpxe


%post 

%preun

%clean
%{__rm} -rf %{buildroot}

%files
/tftpboot/xcat/xnba.kpxe
%changelog
