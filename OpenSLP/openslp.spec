%define pkg  openslp 
%define ver  1.2.1

# what red hat (or other distibution) version are you running?
%define distver 1 

Summary: Open source implementation of Service Location Protocol V2 
Name: %{pkg}-xcat
Version: %{ver}
Release: %{distver}
License: BSD
Group: System/Utilities
URL: http:/openslp.sourceforge.net 
Source: %{pkg}-%{ver}.tar.gz
Patch0: openslp-conf.patch 
Patch1: openslp-attr.patch 
Patch2: openslp-network.patch 
BuildRoot: %{_tmppath}/%{pkg}-%{ver}-root
Prefix: %{_prefix}

%description
Open source implementation of Service Location Protocol V2

%prep
# Set the path to pick up AIX toolbox patch program
export PATH=/opt/freeware/bin:$PATH
%{__rm} -rf %{buildroot}
%setup -q -n %{pkg}-%{ver}
%patch0 -p1
%patch1 -p1 
%patch2 -p1 

%build
%configure --enable-shared=no
make

%install
mkdir -p $RPM_BUILD_ROOT/usr/local/bin
cp slptool/slptool $RPM_BUILD_ROOT/usr/local/bin
mkdir -p $RPM_BUILD_ROOT/usr/local/etc
cp etc/slp.conf $RPM_BUILD_ROOT/usr/local/etc

%clean
%{__rm} -rf %{buildroot}

%files
%defattr(-,root,root)
/usr/local/bin/slptool
/usr/local/etc/slp.conf
