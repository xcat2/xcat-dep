#! /usr/bin/perl

my $version = "1.8.18";
my $release = "4";

#check the distro
$cmd = "cat /etc/*release";
@output = `$cmd`;
my $os;
if (grep /Red Hat Enterprise Linux Server release 5\.\d/, @output) {
  $os = "rh5";
} elsif (grep /Red Hat Enterprise Linux Server release 6\.\d/, @output) {
  $os = "rh6";
} elsif (grep /Red Hat Enterprise Linux Server release 7\.\d/, @output) {
  $os = "rh7";
} elsif (grep /Red Hat Enterprise Linux release 8\.\d/, @output) {
  $os = "rh8";
} elsif (grep /Red Hat Enterprise Linux release 9\.\d/, @output) {
  $os = "rh9";
} elsif (grep /CentOS Linux release 7\.\d/, @output) {
  $os = "rh7";
} elsif (grep /CentOS release 6\.\d/, @output) {
  $os = "rh6";
} elsif (grep /AlmaLinux 8\.\d/, @output) {
  $os = "rh8";
} elsif (grep /AlmaLinux 9\.\d/, @output) {
  $os = "rh9";
} elsif (grep /Rocky Linux 8\.\d/, @output) {
  $os = "rh8";
} elsif (grep /Rocky Linux 9\.\d/, @output) {
  $os = "rh9";
} elsif (grep /SUSE Linux Enterprise Server 10/, @output) {
  $os = "sles10";
} elsif (grep /SUSE Linux Enterprise Server 11/, @output) {
  $os = "sles11";
} elsif (grep /SUSE Linux Enterprise Server 12/, @output) {
  $os = "sles12";
} elsif (grep /SUSE Linux Enterprise Server 15/, @output) {
  $os = "sles15";
} else {
  print "unknow os\n";
  exit 1;
}

$cmd = "uname -p";
my $arch = `$cmd`;
chomp($arch);

print "The build env is: $os-$arch\n";

# check whether the openssl-devel has been isntalled
my $cmd = "rpm -qa | grep openssl";
my @output = `$cmd`;
if ( ! grep /openssl-devel|libopenssl/, @output ) {
  print "Please installed openssl-devel/libopenssl first. (openssl-devel for rh5/sles10; libopenssl for sles11)\n";
  exit 1;
}

# check the source files
my $pwd = `pwd`;
chomp($pwd);
if ( (! -f "$pwd/ipmitool-$version.tar.gz")
  || (! -f "$pwd/ipmitool.spec")
  || (! -f "$pwd/ipmitool-$version-saneretry.patch")
  || (! -f "$pwd/ipmitool-$version-rflash.patch")
  || (! -f "$pwd/ipmitool-$version-signal.patch")  
  || (! -f "$pwd/0012-CVE-2020-5208.patch")) {  
  print "missed some necessary files for building.\n";
  exit 1;
}

my $blddir;
if ($os eq "rh5") {
  $blddir = "/usr/src/redhat";
} elsif ($os =~ /rh\d/) {
  $blddir = "/root/rpmbuild";
} elsif ($os =~ /sles1\d/) {
  $blddir = "/usr/src/packages";
}

&runcmd("mkdir -p $blddir/SOURCES");
&runcmd("mkdir -p $blddir/SPECS");
&runcmd("mkdir -p $blddir/BUILD");
&runcmd("mkdir -p $blddir/RPMS");

# clean the env
$cmd = "rm -rf $blddir/SOURCES/ipmitool*";
&runcmd($cmd);
$cmd = "rm -rf $blddir/SPECS/ipmitool*";
&runcmd($cmd);
$cmd = "rm -rf $blddir/BUILD/ipmitool*";
&runcmd($cmd);
$cmd = "rm -rf $blddir/RPMS/$arch/ipmitool*";
&runcmd($cmd);

# copy the build files
$cmd = "cp -rf ./ipmitool-$version.tar.gz $blddir/SOURCES/";
&runcmd($cmd);

$cmd = "cp -rf ./*.patch $blddir/SOURCES/";
&runcmd($cmd);

$cmd = "cp -rf ./ipmitool.spec $blddir/SPECS/";
&runcmd($cmd);

$cmd = "rpmbuild -bb $blddir/SPECS/ipmitool.spec";
&runcmd($cmd);

#check whether the ssl has been enabled
my $binfile = "$blddir/BUILD/ipmitool-$version/src/ipmitool";
$cmd = "ldd $binfile";
@output = `$cmd`;
if (! grep /libcrypto.so/, @output) {
  print "The ssl was not enabled.\n";
  exit 1;
}

my $objrpm = "$blddir/RPMS/$arch/ipmitool-xcat-$version-$release.$arch.rpm";
my $dstdir = "/tmp/build/$os/$arch";

# check the build result
if (! -f $objrpm) {
  print "The rpm file was not generated successfully\n";
  exit 1;
} else {
  $cmd = "mkdir -p $dstdir";
  &runcmd ($cmd);
  $cmd = "cp -rf  $objrpm $dstdir";
  &runcmd ($cmd);
  print "The obj file has been built successfully, you can get it here: $dstdir\n";
  exit 0;
}

sub runcmd () {
  my $cmd = shift;
  print "++++Trying to run command: [$cmd]\n";
  my @output = `$cmd`;
  if ($?) {
    print "A error happened when running the comamnd [$cmd]\n";
    print "error message: @output\n";
    exit 1;
  }
  if ($verbose) {
    print "run cmd message: @output\n";
  }
}
