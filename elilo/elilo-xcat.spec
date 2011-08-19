Name:           elilo-xcat
Version:        3.14
Release:        1
Summary:        xCAT patched variant of elilo

Group:          System Environment/Kernel
License:        GPL
URL:           http://sourceforge.net/projects/elilo
BuildRoot:      %{_tmppath}/%{name}-%{version}-%{release}
BuildArch:	noarch

%define Distribution %(rpm -q -qf /etc/redhat-release --qf '%%{name}' | cut -d"-"  -f 1)
%define os_version %(rpm -q --qf '%%{version}' %{Distribution}-release)
%define os_release %(rpm -q --qf '%%{release}' %{Distribution}-release | cut -d"." -f 1)


Source0: elilo-3.14-source.tar.gz
Patch: elilo-xcat.patch

%description
elilo with patches from the xCAT team.  Most significantly, adds iPXE usage to the network support

%prep

%setup   -n elilo
%patch -p1

%build

rm -rf %{buildroot}

make


%install

mkdir -p  %{buildroot}/tftpboot/xcat
cp elilo.efi %{buildroot}/tftpboot/xcat/elilo-x64.efi


%post 

%preun

%clean
%{__rm} -rf %{buildroot}

%files
/tftpboot/xcat/elilo-x64.efi
%changelog
