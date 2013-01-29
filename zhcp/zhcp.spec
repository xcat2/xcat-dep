%define name zhcp

Summary: System z hardware control point (zHCP)
Name: %{name}
Version: 2.0
Release: snap%(date +"%Y%m%d%H%M")
Source: zhcp-build.tar.gz
Vendor: IBM
License: IBM Copyright 2012 Eclipse Public License
Group: System/tools
BuildRoot: %{_tmppath}/zhcp
Prefix: /opt/zhcp

%description
The System z hardware control point (zHCP) is C program API to interface with 
z/VM SMAPI. It is used by xCAT to manage virtual machines running Linux on 
System z.

%prep
tar -zxvf ../SOURCES/zhcp-build.tar.gz -C ../BUILD/ --strip 1

%build
make

%install
make install
make post
make clean

mkdir -p $RPM_BUILD_ROOT/usr/bin
ln -sfd %{prefix}/bin/smcli $RPM_BUILD_ROOT/usr/bin
chmod 644 $RPM_BUILD_ROOT/usr/bin/smcli
mkdir -p $RPM_BUILD_ROOT/usr/share/man/man1/
cp smcli.1.gz $RPM_BUILD_ROOT/usr/share/man/man1/
mkdir -p $RPM_BUILD_ROOT/var/opt/zhcp
cp config/tracing.conf $RPM_BUILD_ROOT/var/opt/zhcp

%post
echo "/opt/zhcp/lib" > /etc/ld.so.conf.d/zhcp.conf

# Create log file for zHCP
mkdir -p /var/log/zhcp
touch /var/log/zhcp/zhcp.log

# syslog located in different directories in Red Hat/SUSE
ZHCP_LOG_HEADER="# Logging for xCAT zHCP"
ZHCP_LOG="/var/log/zhcp/zhcp.log"
echo "Configuring syslog"

# SUSE Linux Enterprise Server
if [ -e "/etc/init.d/syslog" ]; then
    # Syslog is the standard for log messages
    grep ${ZHCP_LOG} /etc/syslog.conf > /dev/null || (echo -e "\n${ZHCP_LOG_HEADER}\nlocal4.*        ${ZHCP_LOG}" >> /etc/syslog.conf)
fi
if [ -e "/etc/syslog-ng/syslog-ng.conf" ]; then
    # Syslog-ng is the replacement for syslogd
    grep ${ZHCP_LOG} /etc/syslog-ng/syslog-ng.conf > /dev/null || (echo -e "\n${ZHCP_LOG_HEADER}\n\
filter f_xcat_zhcp  { facility(local4); };\n\
destination zhcplog { file(\"${ZHCP_LOG}\"); };\n\
log { source(src); filter(f_xcat_zhcp); destination(zhcplog); };" >> /etc/syslog-ng/syslog-ng.conf)
fi

# Red Hat Enterprise Linux
if [ -e "/etc/rc.d/init.d/rsyslog" ]; then
    grep ${ZHCP_LOG} /etc/rsyslog.conf > /dev/null || (echo -e "\n${ZHCP_LOG_HEADER}\nlocal4.*        ${ZHCP_LOG}" >> /etc/rsyslog.conf)
fi

# Restart syslog
if [ -e "/etc/redhat-release" ]; then
    /etc/rc.d/init.d/rsyslog restart
else
    /etc/init.d/syslog restart
fi

/sbin/ldconfig

%preun
# Delete man page and smcli command
rm -rf /etc/ld.so.conf.d/zhcp.conf
rm -rf /usr/bin/smcli
rm -rf /usr/share/man/man1/smcli.1.gz

%files
# Files provided by this package
%defattr(-,root,root)
/opt/zhcp/*
%config(noreplace) /usr/bin/smcli
%config(noreplace) /usr/share/man/man1/smcli.1.gz
%config(noreplace) /var/opt/zhcp/tracing.conf

