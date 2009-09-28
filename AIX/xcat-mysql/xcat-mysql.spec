Summary: Metapackage for MySQL on AIX
Name: xcat-mysql
Version: 5.1
Release: 37
License: EPL
Group: Applications/System
Vendor: IBM Corp.
Packager: IBM Corp.
Distribution: %{?_distribution:%{_distribution}}%{!?_distribution:%{_vendor}}
BuildRoot: /var/tmp/%{name}-%{version}-%{release}-root
BuildArch: ppc
Source1: mysql-5.1.37-aix5.3-powerpc-64bit.tar.gz
Provides: xcat-mysql = %{version}

%description
Installs and configures MySQL 5.1.37 on AIX systems.

%prep

%pre

#chfs -a size=+400M  /usr

%build

%install

mkdir -p $RPM_BUILD_ROOT/usr/local
cp %{SOURCE1} $RPM_BUILD_ROOT/usr/local

%post

cd /usr/local

# uwrap
gunzip /usr/local/mysql-5.1.37-aix5.3-powerpc-64bit.tar.gz
tar -xvf /usr/local/mysql-5.1.37-aix5.3-powerpc-64bit.tar

#  set up link for mysql
ln -s /usr/local/mysql-5.1.37-aix5.3-powerpc-64bit mysql

# get rid of the tar file
rm -rf /usr/local/mysql-5.1.37-aix5.3-powerpc-64bit.tar

# set PATH??
echo "PATH=\$PATH:/usr/local/mysql:/usr/local/mysql/bin:/usr/local/mysql/lib:/usr/local/mysql/include
export PATH" >>/etc/profile

echo "The PATH environment variable has been updated in /etc/profile."

%clean

%postun
# ----------------------------------------------------------------------
# The 'postun' step is executed just after the rpm package is removed.
# ----------------------------------------------------------------------

rm -rf /usr/local/mysql
rm -rf /usr/local/mysql-5.1.37-aix5.3-powerpc-64bit

%files
/usr/local/mysql-5.1.37-aix5.3-powerpc-64bit.tar.gz
%defattr(-,root,root)
