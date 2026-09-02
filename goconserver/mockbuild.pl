#!/usr/bin/perl

use strict;
use warnings;
use Cwd qw(abs_path);
use File::Basename qw(dirname basename);
use File::Copy qw(copy);
use File::Path qw(make_path remove_tree);
use Getopt::Long qw(GetOptions);

my $script_dir = abs_path(dirname(__FILE__));
my $repo_root  = abs_path("$script_dir/..");
my $pkg_dir    = "$repo_root/goconserver";

my $work_dir    = '/tmp/goconserver-mockbuild';
my $mock_cfg    = '';
my $target_arch = '';
my $mock_uniqueext = '';
my $result_dir  = "$repo_root/build-output/list5/goconserver";
my $log_dir     = "$repo_root/build-logs/list5/goconserver";
my $skip_install = 0;
my $version     = '0.3.3';
my $go_repo     = 'https://github.com/xcat2/goconserver.git';
my $go_ref      = 'master';
my $build_timestamp;

GetOptions(
    'work-dir=s'       => \$work_dir,
    'mock-cfg=s'       => \$mock_cfg,
    'target-arch=s'    => \$target_arch,
    'mock-uniqueext=s' => \$mock_uniqueext,
    'result-dir=s'     => \$result_dir,
    'log-dir=s'        => \$log_dir,
    'skip-install!'    => \$skip_install,
    'version=s'        => \$version,
    'go-repo=s'        => \$go_repo,
    'go-ref=s'         => \$go_ref,
    'build-timestamp=i' => \$build_timestamp,
) or die usage();

die "Run as root (current uid=$>)\n" if $> != 0;

for my $bin (qw(go git rpmbuild rpm)) {
    run("command -v " . sh_quote($bin) . " >/dev/null 2>&1");
}

my $arch = capture('uname -m');
if (!$mock_cfg) {
    my $os_id = capture(q{bash -lc 'source /etc/os-release; echo $ID'});
    $mock_cfg = resolve_mock_cfg($os_id, '10', $arch);
}

my ($rel) = $mock_cfg =~ /-(\d+)-/;
$rel //= '10';
# Arch of the rpm to produce: the host arch unless --mock-cfg is a forcearch (cross) config,
# e.g. rocky-10-riscv64-xcat built on x86_64 (see BUILD.md "riscv64"). goconserver is not built
# in the chroot: go cross-compiles on the host and rpmbuild --target packages the result.
$target_arch = $arch if $target_arch eq '';
my %goarch = (x86_64 => 'amd64', aarch64 => 'arm64', ppc64le => 'ppc64le', s390x => 's390x', riscv64 => 'riscv64');
my $cross = $target_arch ne $arch;
die "No GOARCH known for target arch $target_arch\n" if $cross && !exists $goarch{$target_arch};

my $SOURCE_DATE_EPOCH;
$SOURCE_DATE_EPOCH = $build_timestamp if defined $build_timestamp;
if (!$SOURCE_DATE_EPOCH && -f "$repo_root/Gitepoch") {
    my $epoch_content = '';
    if (open my $efh, '<', "$repo_root/Gitepoch") {
        $epoch_content = <$efh>;
        close $efh;
        chomp $epoch_content;
    }
    $SOURCE_DATE_EPOCH = $epoch_content;
}
unless ($SOURCE_DATE_EPOCH && $SOURCE_DATE_EPOCH =~ /^\d+$/) {
    $SOURCE_DATE_EPOCH = `git -C \Q$repo_root\E log -1 --format=%ct HEAD 2>/dev/null`;
    chomp $SOURCE_DATE_EPOCH;
}
$SOURCE_DATE_EPOCH = time() unless $SOURCE_DATE_EPOCH =~ /^\d+$/;
$ENV{SOURCE_DATE_EPOCH} = $SOURCE_DATE_EPOCH;

print_step("Configuration");
print "repo_root:  $repo_root\n";
print "pkg_dir:    $pkg_dir\n";
print "work_dir:   $work_dir\n";
print "result_dir: $result_dir\n";
print "log_dir:    $log_dir\n";
print "mock_cfg:   $mock_cfg\n";
print "arch:       $arch\n";
print "target_arch:$target_arch" . ($cross ? " (GOARCH=$goarch{$target_arch}, rpmbuild --target)" : '') . "\n";
print "version:    $version\n";
print "go_repo:    $go_repo\n";
print "go_ref:     $go_ref\n";
print "skip_install: $skip_install\n";

make_path($result_dir);
make_path($log_dir);

print_step("Stage build environment");
remove_tree($work_dir) if -d $work_dir;
make_path($work_dir);

# Unique per run (nested under the run/target-scoped --work-dir) so concurrent builds -- e.g.
# parallel EL targets on one host -- don't wipe each other. (Was a shared
# /var/tmp/xcat-rpmbuild-goconserver, which collided under parallelism.)
my $rpmbuild_top = "$work_dir/rpmbuild";
remove_tree($rpmbuild_top) if -d $rpmbuild_top;
for my $d (qw(BUILD BUILDROOT RPMS SOURCES SPECS SRPMS)) {
    make_path("$rpmbuild_top/$d");
}

print_step("Clone goconserver source");
my $src_dir = "$work_dir/goconserver-src";
run("git clone --depth 1 --branch " . sh_quote($go_ref) . " " .
    sh_quote($go_repo) . " " . sh_quote($src_dir) .
    " >" . sh_quote("$log_dir/git-clone.log") . " 2>&1");

# etcd storage backend has broken deps with modern Go modules;
# xCAT only uses file storage, so remove etcd before building.
unlink "$src_dir/storage/etcd.go";
remove_tree("$src_dir/storage/etcd") if -d "$src_dir/storage/etcd";

print_step("Initialize Go modules");
$ENV{GOPATH}      = "$work_dir/gopath";
$ENV{GOCACHE}     = "$work_dir/gocache";
$ENV{GOMODCACHE}  = "$work_dir/gomodcache";
$ENV{CGO_ENABLED} = '0';
$ENV{GOARCH}      = $goarch{$target_arch} if $cross;

# The archived github.com/kr/pty sets SysProcAttr.Ctty to the parent-side fd,
# which modern Go's os/exec rejects with "Setctty set but Ctty not valid in
# child". Replace it with the API-identical maintained fork creack/pty.
run("cd " . sh_quote($src_dir) . " && " .
    "go mod init github.com/xcat2/goconserver && " .
    "go mod edit -replace github.com/kr/pty=github.com/creack/pty\@v1.1.21 && " .
    "go mod tidy" .
    " >" . sh_quote("$log_dir/go-mod.log") . " 2>&1");

print_step("Build goconserver binaries");
my $go_build_dir = "$work_dir/bin";
make_path($go_build_dir);

my $ldflags = "-X main.Version=$version";
# rpm's brp-strip on the host cannot strip a foreign-arch ELF, so let the Go linker do it.
$ldflags .= ' -s -w' if $cross;

run("cd " . sh_quote($src_dir) . " && " .
    "go build -trimpath -buildvcs=false -ldflags " . sh_quote($ldflags) .
    " -o " . sh_quote("$go_build_dir/goconserver") . " goconserver.go" .
    " >" . sh_quote("$log_dir/go-build-server.log") . " 2>&1");

run("cd " . sh_quote($src_dir) . " && " .
    "go build -trimpath -buildvcs=false -ldflags " . sh_quote($ldflags) .
    " -o " . sh_quote("$go_build_dir/congo") . " cmd/congo.go" .
    " >" . sh_quote("$log_dir/go-build-client.log") . " 2>&1");

die "goconserver binary not built\n" if !-x "$go_build_dir/goconserver";
die "congo binary not built\n"       if !-x "$go_build_dir/congo";

print_step("Create source tarball");
my $payload_dir = "$work_dir/goconserver-$version";
make_path("$payload_dir/usr/bin");
make_path("$payload_dir/usr/lib/systemd/system");
make_path("$payload_dir/etc/goconserver");

copy("$go_build_dir/goconserver", "$payload_dir/usr/bin/goconserver")
    or die "copy goconserver: $!\n";
copy("$go_build_dir/congo", "$payload_dir/usr/bin/congo")
    or die "copy congo: $!\n";
chmod 0755, "$payload_dir/usr/bin/goconserver";
chmod 0755, "$payload_dir/usr/bin/congo";

write_file("$payload_dir/usr/lib/systemd/system/goconserver.service", <<'SERVICE');
[Unit]
Description=goconserver console server
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/goconserver
Restart=on-failure
StateDirectory=goconserver

[Install]
WantedBy=multi-user.target
SERVICE

write_file("$payload_dir/etc/goconserver/server.conf", <<'CONF');
[server]
host = 0.0.0.0
port = 12430
console_port = 12431
log_file = /var/log/goconserver/server.log
log_timestamp = true
log_level = info
CONF

my $tarball = "$rpmbuild_top/SOURCES/goconserver-$version.tar.gz";
run("tar --sort=name --owner=0 --group=0 --mtime=\@$SOURCE_DATE_EPOCH" .
    " -C " . sh_quote($work_dir) . " -czf " . sh_quote($tarball) .
    " goconserver-$version");

print_step("Create spec and build RPM");
# rpm refuses 'BuildArch: <foreign arch>' on this host, so a cross build gets its arch from
# rpmbuild --target instead.
my $buildarch_line = $cross ? '' : "BuildArch:      $arch";
my $spec_content = <<"SPEC";
Name:           goconserver
Version:        $version
Release:        3.el$rel
Summary:        Console server written in Go for xCAT
License:        EPL-1.0
URL:            https://github.com/xcat2/goconserver
$buildarch_line

Source0:        goconserver-%{version}.tar.gz

%description
goconserver is a scalable console server written in Go. It provides
console logging and management for xCAT cluster nodes.

%prep
%setup -n goconserver-%{version}

%install
mkdir -p %{buildroot}/usr/bin
mkdir -p %{buildroot}/usr/lib/systemd/system
mkdir -p %{buildroot}/etc/goconserver
mkdir -p %{buildroot}/var/log/goconserver
mkdir -p %{buildroot}/var/lib/goconserver

install -m 755 usr/bin/goconserver %{buildroot}/usr/bin/goconserver
install -m 755 usr/bin/congo %{buildroot}/usr/bin/congo
install -m 644 usr/lib/systemd/system/goconserver.service %{buildroot}/usr/lib/systemd/system/goconserver.service
install -m 644 etc/goconserver/server.conf %{buildroot}/etc/goconserver/server.conf

%files
/usr/bin/goconserver
/usr/bin/congo
/usr/lib/systemd/system/goconserver.service
%config(noreplace) /etc/goconserver/server.conf
%dir /var/log/goconserver
%dir /var/lib/goconserver

%changelog
* Mon Jun 08 2026 xCAT EL10 build - 0.3.3-2.el10
- Replace archived github.com/kr/pty with github.com/creack/pty to fix
  "Setctty set but Ctty not valid in child" console fork failure on modern Go.
SPEC

my $spec_file = "$rpmbuild_top/SPECS/goconserver.spec";
write_file($spec_file, $spec_content);

run(
    "rpmbuild --define " . sh_quote("_topdir $rpmbuild_top") .
    " --define " . sh_quote("use_source_date_epoch_as_buildtime 1") .
    " --define " . sh_quote("clamp_mtime_to_source_date_epoch 1") .
    " --define " . sh_quote("_buildhost xcat-build") .
    ($cross ? " --target " . sh_quote($target_arch) : '') .
    " -ba " . sh_quote($spec_file) .
    " >" . sh_quote("$log_dir/rpmbuild.log") . " 2>&1"
);

print_step("Collect results");
for my $rpm (glob("$rpmbuild_top/RPMS/*/*.rpm"), glob("$rpmbuild_top/SRPMS/*.rpm")) {
    my $dest = "$result_dir/" . basename($rpm);
    copy($rpm, $dest) or die "Failed to copy $rpm to $dest: $!\n";
    print "Copied: $dest\n";
}

if (!$skip_install && $cross) {
    # A cross-built rpm cannot be installed on this host. Unpack it and run the static Go
    # binaries through the binfmt_misc handler (qemu-user-static) that the forcearch mock
    # builds of the other deps need anyway.
    print_step("Smoke test the $target_arch binaries (binfmt)");
    my @built = glob("$rpmbuild_top/RPMS/$target_arch/goconserver-*.rpm");
    die "No $target_arch RPM found\n" if !@built;
    my $smoke_root = "$work_dir/smoke-root";
    remove_tree($smoke_root) if -d $smoke_root;
    make_path($smoke_root);
    run("cd " . sh_quote($smoke_root) . " && rpm2cpio " . sh_quote($built[0]) . " | cpio -idm --quiet" .
        " >" . sh_quote("$log_dir/smoke-unpack.log") . " 2>&1");
    for my $bin (qw(goconserver congo)) {
        my $path = "$smoke_root/usr/bin/$bin";
        die "Missing $path in the $target_arch rpm\n" if !-x $path;
        my $rc = run_rc(sh_quote($path) . " -h >" . sh_quote("$log_dir/smoke-$bin.log") . " 2>&1");
        die "$bin -h failed (rc=$rc): running a $target_arch binary on this $arch host needs the"
          . " qemu-user-static binfmt handler (or pass --skip-install)\n" if $rc > 1;
    }
    print "Smoke tests passed ($target_arch binaries ran through binfmt).\n";
}
elsif (!$skip_install) {
    print_step("Install and smoke test");
    my @built = glob("$rpmbuild_top/RPMS/$arch/goconserver-*.rpm");
    die "No arch RPM found\n" if !@built;
    my $main_rpm = $built[0];

    run("dnf -y install " . sh_quote($main_rpm) .
        " >" . sh_quote("$log_dir/dnf-install.log") . " 2>&1");

    die "Missing /usr/bin/goconserver\n" if !-x '/usr/bin/goconserver';
    die "Missing /usr/bin/congo\n"       if !-x '/usr/bin/congo';

    my $rc_help = run_rc("goconserver -h >" . sh_quote("$log_dir/smoke-help.log") . " 2>&1");
    die "goconserver -h failed (rc=$rc_help)\n" if $rc_help > 1;

    my $rc_congo = run_rc("congo -h >" . sh_quote("$log_dir/smoke-congo.log") . " 2>&1");
    die "congo -h failed (rc=$rc_congo)\n" if $rc_congo > 1;

    print "Smoke tests passed.\n";
}

print_step("Completed");
print "Results in: $result_dir\n";
exit 0;

sub usage {
    return <<"USAGE";
Usage: $0 [options]

Build goconserver RPM from source.

Options:
  --work-dir PATH       Working directory (default: /tmp/goconserver-mockbuild)
  --mock-cfg NAME       Mock config name (auto-detected if omitted)
  --target-arch ARCH    Arch of the rpm to build (default: uname -m); another arch is
                        cross-compiled (GOARCH) and packaged with rpmbuild --target
  --mock-uniqueext STR  Mock uniqueext value (for compatibility with mockbuild-all.pl)
  --result-dir PATH     Output directory for RPMs
  --log-dir PATH        Output directory for logs
  --skip-install        Skip dnf install + smoke tests
  --version VER         Version string (default: 0.3.3)
  --go-repo URL         Git repo URL (default: github.com/xcat2/goconserver)
  --go-ref REF          Git ref to build (default: master)
  --build-timestamp EPOCH  SOURCE_DATE_EPOCH for deterministic builds
USAGE
}

sub print_step {
    my ($msg) = @_;
    print "\n== $msg ==\n";
}

sub sh_quote {
    my ($s) = @_;
    $s = '' if !defined $s;
    $s =~ s/'/'"'"'/g;
    return "'$s'";
}

sub run {
    my ($cmd) = @_;
    print "+ $cmd\n";
    my $rc = system($cmd);
    if ($rc != 0) {
        my $exit = $rc == -1 ? 255 : ($rc >> 8);
        die "Command failed (rc=$exit): $cmd\n";
    }
}

sub run_rc {
    my ($cmd) = @_;
    print "+ $cmd\n";
    my $rc = system($cmd);
    return $rc == -1 ? 255 : ($rc >> 8);
}

sub capture {
    my ($cmd) = @_;
    my $out = `$cmd`;
    chomp $out;
    return $out;
}

sub write_file {
    my ($path, $content) = @_;
    open my $fh, '>', $path or die "Cannot write $path: $!\n";
    print $fh $content;
    close $fh;
}

sub resolve_mock_cfg {
    my ($os_id, $rel, $arch) = @_;
    my %short_forms = (almalinux => 'alma', rocky => 'rocky');
    my $candidate = "${os_id}+epel-${rel}-${arch}";
    my $rc = system("mock -r " . sh_quote($candidate) . " --print-root-path >/dev/null 2>&1");
    return $candidate if $rc == 0;
    if (exists $short_forms{$os_id}) {
        $candidate = "$short_forms{$os_id}+epel-${rel}-${arch}";
        $rc = system("mock -r " . sh_quote($candidate) . " --print-root-path >/dev/null 2>&1");
        return $candidate if $rc == 0;
    }
    return "${os_id}+epel-${rel}-${arch}";
}
