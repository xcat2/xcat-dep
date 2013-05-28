#! /usr/bin/perl

# install pkg for build: gcc, openssl-dev, glibc-devel
use File::Find;

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
if (! -f "$pwd/cpio-2.11.tar.bz2"){
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
$cmd = "rm -rf $blddir/SOURCES/cpio*";
&runcmd($cmd);
$cmd = "rm -rf $blddir/SPECS/cpio*";
&runcmd($cmd);
$cmd = "rm -rf $blddir/BUILD/cpio*";
&runcmd($cmd);
$cmd = "rm -rf $blddir/RPMS/$arch/cpio*";
&runcmd($cmd);

# copy the build files
$cmd = "cp -rf ./cpio-2.11.tar.bz2 $blddir/SOURCES/";
&runcmd($cmd);

$cmd = "cp -rf ./*.patch $blddir/SOURCES/";
&runcmd($cmd);

$cmd = "cp -rf ./*.1 $blddir/SOURCES/";
&runcmd($cmd);

$cmd = "cp -rf ./cpio.spec $blddir/SPECS/";
&runcmd($cmd);

$cmd = "rpmbuild -bb $blddir/SPECS/cpio.spec";
&runcmd($cmd);

my $objrpm = "";
my @rpm = `find $blddir/RPMS/$arch/ -name "cpio-2.11-20*rpm"`;
my $dstdir = "/tmp/build/$os/$arch";

# check the build result
if ( @rpm == 0 ) {
  print "The rpm file was not generated successfully\n";
  exit 1;
} else {
  $objrpm = $rpm[0];
  chomp $objrpm;
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
