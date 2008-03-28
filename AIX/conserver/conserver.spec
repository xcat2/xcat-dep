#
# rpm spec file for conserver, but I don't think it'll work on any
# platform that doesn't have red hat rpm >= 4.0.2 installed.
#

%define pkg  conserver
%define ver  8.1.16

# define the name of the machine on which the main conserver
# daemon will be running if you don't want to use the default
# hostname (console)
%define master console

# what red hat (or other distibution) version are you running?
%define distver 2

Summary: Serial console server daemon/client
Name: %{pkg}
Version: %{ver}
Release: %{distver}
License: BSD
Group: System Environment/Daemons
URL: http://www.conserver.com/
Source: http://www.conserver.com/%{pkg}-%{ver}.tar.gz
Patch: certificate-auth.patch
BuildRoot: %{_tmppath}/%{pkg}-buildroot
Prefix: %{_prefix}


%description
Conserver is an application that allows multiple users to watch a
serial console at the same time.  It can log the data, allows users to
take write-access of a console (one at a time), and has a variety of
bells and whistles to accentuate that basic functionality.


%prep
%{__rm} -rf %{buildroot}
%setup -q
%patch -p1


%build
# we don't want to install the solaris conserver.rc file
f="conserver/Makefile.in"
%{__mv} $f $f.orig
%{__sed} -e 's/^.*conserver\.rc.*$//' < $f.orig > $f

%configure --with-master=%{master} --with-openssl --with-cffile=/etc/conserver.cf
make


%install
%{makeinstall}

# put commented copies of the sample configure files in the
# system configuration directory
%{__mkdir_p} %{buildroot}/%{_sysconfdir}
%{__sed} -e 's/^/#/' \
  < conserver.cf/conserver.cf \
  > %{buildroot}/%{_sysconfdir}/conserver.cf
%{__sed} -e 's/^/#/' \
  < conserver.cf/conserver.passwd \
  > %{buildroot}/%{_sysconfdir}/conserver.passwd

# install copy of init script

%ifos Linux
%{__mkdir_p} %{buildroot}/%{_initrddir}
%{__cp} contrib/redhat-rpm/conserver.init %{buildroot}/%{_initrddir}/conserver
%endif


%clean
%{__rm} -rf %{buildroot}


%post
# Make sure /etc/services has a conserver entry
#
if ! egrep conserver /etc/services > /dev/null 2>&1 ; then
  echo "console  782/tcp  conserver" >> /etc/services
fi

# Remove any existing entry, then add the current one
#
 rmitab "conserver" > /dev/null 2>&1
 mkitab "conserver:2:once:/opt/conserver/bin/conserver -d -i -m 64"

# If the pid file exists, the daemon may be running
#
if [[ -s /var/run/conserver.pid ]]; then
    # kill the daemon
    #
    kill -15 `cat /var/run/conserver.pid` > /dev/null 2>&1

    # Does a configuration file exist?
    #
    if [[ -s /etc/opt/conserver/conserver.cf ]]; then
        # is it a pre-8.0 configuration file?
        #
        OLD_FORMAT = grep "%%" /etc/opt/conserver/conserver.cf > /dev/null 2>&1

        if [[ $OLD_FORMAT = "0" ]]; then
            # 8.0 style config file, OK to try and start the daemon
            #
            /opt/conserver/bin/conserver -d -i -m 64
        fi
    fi
fi

%preun
%ifos Linux
if [ "$1" = 0 ]; then
  if [ -x %{_initrddir}/conserver ]; then
    %{_initrddir}/conserver stop
    /sbin/chkconfig --del conserver
  fi
fi
%endif

# Only if we're the last package
#
if [[ "$1" = 0 ]]; then
 # Remove the existing entry
 #
 rmitab "conserver" > /dev/null 2>&1
fi

%postun

# Only if we're the last package
#
if [[ "$1" = 0 ]]; then
    # Remove conserver-specific directories
    #
    rm -fr /var/log/consoles

    # If the pid file exists, the daemon may be running
    #
    if [[ -s /var/run/conserver.pid ]]; then
        # kill the daemon
        #
        kill -15 `cat /var/run/conserver.pid` > /dev/null 2>&1

        # Now remove the pid file
        #
        rm -f /var/run/conserver.pid
    fi
fi

%files
%defattr(-,root,root)
%doc CHANGES FAQ INSTALL README conserver.cf
%config(noreplace) %{_sysconfdir}/conserver.cf
%config(noreplace) %{_sysconfdir}/conserver.passwd
#   %attr(555,root,root) /%{_initrddir}/conserver
%{prefix}/bin/console
#   %{prefix}/lib64/conserver/convert
%{prefix}/man/man1/console.1
%{prefix}/man/man8/conserver.8
%{prefix}/man/man5/conserver.cf.5
%{prefix}/man/man5/conserver.passwd.5
%{prefix}/share/examples/conserver/conserver.cf
%{prefix}/share/examples/conserver/conserver.passwd
%{prefix}/sbin/conserver
