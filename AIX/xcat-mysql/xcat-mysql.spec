Summary: Metapackage for MySQL on AIX
Name: xcat-mysql
Version: 5.1
Release: 1
License: EPL
Group: Applications/System
Vendor: IBM Corp.
Packager: IBM Corp.
Distribution: %{?_distribution:%{_distribution}}%{!?_distribution:%{_vendor}}
BuildRoot: /var/tmp/%{name}-%{version}-%{release}-root
BuildArch: ppc
Source1: mysql-5.1.26-rc-aix5.3-powerpc.tar.gz
Provides: xcat-mysql = %{version}

%description
Installs and configures MySQL 5.1 on AIX systems.

%prep

%build

%install
mkdir -p $RPM_BUILD_ROOT/usr/local
cp %{SOURCE1} $RPM_BUILD_ROOT/usr/local

%post

cd /usr/local

# uwrap
gunzip mysql-5.1.26-rc-aix5.3-powerpc.tar.gz
tar -xvf mysql-5.1.26-rc-aix5.3-powerpc.tar

#  set up link for mysql
ln -s /usr/local/mysql-5.1.26-rc-aix5.3-powerpc mysql

# create group & user id
mkgroup  mysql
mkuser   mysql

# TODO - add call to script (xcatcfgmysql) to do config!

# set PATH??
echo "PATH=\$PATH:/usr/local/mysql:/usr/local/mysql/bin:/usr/local/mysql/lib:/usr/local/mysql/include
export PATH" >>/etc/profile

echo "The PATH environment variable has been updated in /etc/profile."


# TODO - add postun section to remove MySQL - 

%clean

%files
/usr/local/mysql-5.1.26-rc-aix5.3-powerpc.tar.gz
%defattr(-,root,root)
