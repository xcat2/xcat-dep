#! /usr/bin/perl

# install pkg for build: gcc, openssl-dev, glibc-devel

#check the distro
$cmd = "cat /etc/*release";
@output = `$cmd`;
my $os;
if (grep /Red Hat Enterprise Linux Server release 5\.\d/, @output) {
  $os = "rh5";
} elsif (grep /Red Hat Enterprise Linux Server release 6\.\d/, @output) {
  $os = "rh6";
} elsif (grep /SUSE Linux Enterprise Server 10/, @output) {
  $os = "sles10";
} elsif (grep /SUSE Linux Enterprise Server 11/, @output) {
  $os = "sles11";
} elsif (grep /Fedora release/, @output) {
  $os = "fedora";
} else {
  print "unknow os\n";
  exit 1;
}

$cmd = "uname -p";
my $arch = `$cmd`;
chomp($arch);
$arch =~ s/i686/i386/;

print "The build env is: $os-$arch\n";

# check the source files
my $pwd = `pwd`;
chomp($pwd);
if ( (! -f "$pwd/conserver-8.1.16.tar.gz")
  || (! -f "$pwd/conserver.spec")
  || (! -f "$pwd/certificate-auth.patch")
  || (! -f "$pwd/initscript.patch")
  || (! -f "$pwd/initscript1.patch")
  || (! -f "$pwd/segfault-sslopt.patch")) {
  print "missed some necessary files for building.\n";
  exit 1;
}

my $blddir;
if ($os eq "rh5") {
  $blddir = "/usr/src/redhat";
} elsif ($os eq "rh6" || $os eq "fedora") {
  $blddir = "/root/rpmbuild";
} elsif ($os =~ /sles1\d/) {
  $blddir = "/usr/src/packages";
}

#&runcmd("mkdir -p $blddir/SOURCES");
#&runcmd("mkdir -p $blddir/SPECS");
#&runcmd("mkdir -p $blddir/BUILD");
#&runcmd("mkdir -p $blddir/RPMS");

# clean the env
$cmd = "rm -rf $blddir/SOURCES/conserver*";
&runcmd($cmd);
$cmd = "rm -rf $blddir/SPECS/conserver*";
&runcmd($cmd);
$cmd = "rm -rf $blddir/BUILD/conserver*";
&runcmd($cmd);
$cmd = "rm -rf $blddir/RPMS/$arch/conserver*";
&runcmd($cmd);

# copy the build files
$cmd = "cp -rf ./conserver-8.1.16.tar.gz $blddir/SOURCES/";
&runcmd($cmd);

$cmd = "cp -rf ./*.patch $blddir/SOURCES/";
&runcmd($cmd);

$cmd = "cp -rf ./conserver.spec $blddir/SPECS/";
&runcmd($cmd);

$cmd = "rpmbuild -bb $blddir/SPECS/conserver.spec";
&runcmd($cmd);

my $objrpm = "$blddir/RPMS/$arch/conserver-xcat-8.1.16-10.$arch.rpm";
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
