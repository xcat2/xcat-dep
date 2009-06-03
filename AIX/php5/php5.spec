%define version 5.2.6
%define so_version 5
%define release 0

Name: php
Summary: PHP: Hypertext Preprocessor
Group: Development/Languages
Version: %{version}
Release: %{release}
License: The PHP license (see "LICENSE" file included in distribution)
Source: php-%{version}.tar.gz
#Icon: php.gif
URL: http://www.php.net/
Packager: PHP Group <group@php.net>

BuildRoot: /var/tmp/php-%{version}

BuildRequires: make

BuildRequires: gd-devel >= 1.8.4
BuildRequires: bzip2, libpng-devel, libjpeg-devel, zlib-devel
BuildRequires: freetype2-devel >= 2.1.7, freetype-devel >= 1.3.1 
BuildRequires: libxml2-devel >= 2.6.21

Provides: mod_php = %{version}-%{release}

Requires: gd >= 1.8.4, gd-progs >= 1.8.4
Requires: bzip2, libjpeg, libpng, zlib
Requires: freetype2 >= 2.1.7, freetype >= 1.3.1
Requires: gettext >= 0.10.40, libxml2 >= 2.6.21

%description
PHP is an HTML-embedded scripting language. Much of its syntax is
borrowed from C, Java and Perl with a couple of unique PHP-specific
features thrown in. The goal of the language is to allow web
developers to write dynamically generated pages quickly.

%prep
export PATH=/opt/freeware/bin:/usr/IBM/HTTPServer/bin:$PATH
export LD_LIBRARY_PATH=/usr/IBM/HTTPServer/lib:$LD_LIBRARY_PATH
%{__rm} -rf %{buildroot}
%setup -q

%build
set -x
%configure \
	--with-config-file-path=/usr/IBM/HTTPServer/conf/php.ini \
 	--enable-shared \
	--disable-static \
	--enable-maintainer-zts \
	--enable-calendar \
	--enable-bcmath \
	--enable-sockets \
	--enable-zip \
	--with-gd \
	--with-zlib \
	--with-libxml-dir=/opt/freeware \
	--with-zlib-dir=/opt/freeware \
	--with-bz2 \
	--with-gettext=/opt/freeware \
	--with-jpeg-dir=/opt/freeware \
	--with-png-dir=/opt/freeware \
	--with-freetype-dir=/opt/freeware \
    --with-openssl
make

%install
make INSTALL_ROOT=%{buildroot} install
cp php.ini-recommended %{buildroot}/%{_sysconfdir}

%preun
rm /usr/IBM/HTTPServer/conf/php.ini
cp /usr/IBM/HTTPServer/conf/httpd.conf.bak /usr/IBM/HTTPServer/conf/http.conf
/usr/IBM/HTTPServer/bin/apachectl stop

%postun
/usr/IBM/HTTPServer/bin/apachectl start

%post
cp %{_sysconfdir}/php.ini-recommended /usr/IBM/HTTPServer/conf/php.ini

cp /usr/IBM/HTTPServer/conf/httpd.conf /usr/IBM/HTTPServer/conf/httpd.conf.bak

sed 's/^\(DirectoryIndex index\.html.*\)\s*$/\1 index.php/' /usr/IBM/HTTPServer/conf/httpd.conf > /usr/IBM/HTTPServer/conf/httpd.tmp
mv /usr/IBM/HTTPServer/conf/httpd.tmp /usr/IBM/HTTPServer/conf/httpd.conf

cat <<END >>/usr/IBM/HTTPServer/conf/httpd.conf
ScriptAlias  /php5-cgi /opt/freeware/bin/php-cgi
Action php-cgi /php5-cgi
AddHandler php-cgi .php
END

/usr/IBM/HTTPServer/bin/apachectl stop
/usr/IBM/HTTPServer/bin/apachectl start

%files
%defattr (-,root,system)
%{_sysconfdir}/php.ini-recommended
%{_bindir}/pear
%{_bindir}/peardev
%{_bindir}/pecl
%{_bindir}/php
%{_bindir}/php-cgi
%{_bindir}/php-config
%{_bindir}/phpize

%{_libdir}/php

%{_includedir}/php

%config(noreplace) %{_sysconfdir}/pear.conf

%{_mandir}/man1/php.1
%{_mandir}/man1/php-config.1
%{_mandir}/man1/phpize.1

