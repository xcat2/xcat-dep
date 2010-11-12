Name:           xnba-undi
Version:        1.0.2
Release:        1
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


Source0: ipxe-20101112.tar.bz2
Patch0: ipxe-branding.patch
Patch1: ipxe-registersan.patch
Patch2: ipxe-config.patch
Patch3: ipxe-droppackets.patch
Patch4: ipxe-xnbaclass.patch
Patch5: ipxe-undinetchange.patch
Patch6: ipxe-expandfilename.patch
Patch7: ipxe-cmdlinesize.patch
Patch8: ipxe-machyp.patch

%description
The xCAT Network Boot Agent is a slightly modified version of gPXE.  It provides enhanced boot features for any UNDI compliant x86 host.  This includes iSCSI, http/ftp downloads, and gPXE script based booting.

%prep

%setup  -n ipxe
%patch -p1
%patch1 -p1
%patch2 -p1
%patch3 -p1
%patch4 -p1
%patch5 -p1
%patch6 -p1
%patch7 -p1
%patch8 -p1

%build

rm -rf %{buildroot}

cd src
make bin/undionly.kkpxe


%install

mkdir -p  %{buildroot}/tftpboot/xcat
#Rename to avoid conflicting with potential vanilla undionly.kpxe that user may be using
cp src/bin/undionly.kkpxe %{buildroot}/tftpboot/xcat/xnba.kpxe


%post 

%preun

%clean
%{__rm} -rf %{buildroot}

%files
/tftpboot/xcat/xnba.kpxe
%changelog
