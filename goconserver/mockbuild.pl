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
my $mock_uniqueext = '';
my $result_dir  = "$repo_root/build-output/list5/goconserver";
my $log_dir     = "$repo_root/build-logs/list5/goconserver";
my $skip_install = 0;
my $version     = '0.3.3';
my $go_repo     = 'https://github.com/xcat2/goconserver.git';
# Immutable pin: goconserver 0.3.3 is unreleased (newest tag v0.3.2) so it lives only on master.
# mockbuild-all.pl passes --go-ref with the canonical pin; this default keeps standalone runs
# reproducible too. The committed vendored/ tree (go.mod/go.sum/vendor) corresponds to THIS SHA.
my $go_ref      = '6166fe5ec1c5b3c20475e322a9f0e8e93c87e45f';
my $release_suffix = '';   # CD Release bump (".snap<YYYYMMDDHHMM>.<n>"); passed by mockbuild-all.pl
my $build_timestamp;

GetOptions(
    'work-dir=s'       => \$work_dir,
    'mock-cfg=s'       => \$mock_cfg,
    'mock-uniqueext=s' => \$mock_uniqueext,
    'result-dir=s'     => \$result_dir,
    'log-dir=s'        => \$log_dir,
    'skip-install!'    => \$skip_install,
    'version=s'        => \$version,
    'go-repo=s'        => \$go_repo,
    'go-ref=s'         => \$go_ref,
    'release-suffix=s' => \$release_suffix,
    'build-timestamp=i' => \$build_timestamp,
) or die usage();

die "Run as root (current uid=$>)\n" if $> != 0;

# The Go compile happens INSIDE the mock chroot (BuildRequires: golang); the host only needs to
# fetch the pinned source and drive mock. (No host `go` build any more -- that was the non-hermetic
# path this rewrite removes.)
for my $bin (qw(git rpm mock)) {
    run("command -v " . sh_quote($bin) . " >/dev/null 2>&1");
}

my $arch = capture('uname -m');
if (!$mock_cfg) {
    my $os_id = capture(q{bash -lc 'source /etc/os-release; echo $ID'});
    $mock_cfg = resolve_mock_cfg($os_id, '10', $arch);
}

my ($rel) = $mock_cfg =~ /-(\d+)-/;
$rel //= '10';

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

# goconserver is a CGO-free static Go binary. el8/el9 chroots ship a Go too old to build 0.3.3, so
# always COMPILE in the el10 chroot for this arch (regardless of the target EL), then ship the static
# binary to every EL repo. The Release still carries the target's dist tag (4.el$rel) so each EL repo
# gets a correctly-named, byte-identical rpm.
(my $build_cfg = $mock_cfg) =~ s/-\d+-/-10-/;

print_step("Configuration");
print "repo_root:    $repo_root\n";
print "pkg_dir:      $pkg_dir\n";
print "work_dir:     $work_dir\n";
print "result_dir:   $result_dir\n";
print "log_dir:      $log_dir\n";
print "mock_cfg:     $mock_cfg (target dist tag: el$rel)\n";
print "build_cfg:    $build_cfg (el10 -- portable static build for arch $arch)\n";
print "arch:         $arch\n";
print "version:      $version\n";
print "go_ref:       $go_ref\n";
print "release_suffix: " . ($release_suffix ne '' ? $release_suffix : '(none)') . "\n";
print "skip_install: $skip_install\n";

make_path($result_dir);
make_path($log_dir);

print_step("Stage build environment");
remove_tree($work_dir) if -d $work_dir;
make_path($work_dir);

# --- Fetch the pinned goconserver source (immutable SHA -> reproducible) ---
print_step("Clone goconserver source");
my $src_dir = "$work_dir/goconserver-src";
my $clone_log = sh_quote("$log_dir/git-clone.log");
run("git init -q " . sh_quote($src_dir) . " >$clone_log 2>&1");
run("git -C " . sh_quote($src_dir) . " remote add origin " . sh_quote($go_repo) . " >>$clone_log 2>&1");
run("git -C " . sh_quote($src_dir) . " fetch --depth 1 origin " . sh_quote($go_ref) . " >>$clone_log 2>&1");
run("git -C " . sh_quote($src_dir) . " checkout -q FETCH_HEAD >>$clone_log 2>&1");

# etcd storage backend has broken deps with modern Go modules; xCAT only uses file storage.
unlink "$src_dir/storage/etcd.go";
remove_tree("$src_dir/storage/etcd") if -d "$src_dir/storage/etcd";
remove_tree("$src_dir/.git") if -d "$src_dir/.git";   # keep the SRPM tarball clean + reproducible

# --- Overlay the committed, PINNED go.mod/go.sum (no vendored tree) ---
# go.mod already replaces the archived github.com/kr/pty with creack/pty (see gomod/README.md), and
# go.sum integrity-checks every module. The in-chroot build downloads the modules from the Go proxy
# (mock networking is enabled) but is reproducible because go.sum pins them -- no `go mod tidy`, and
# no 400k-line vendor tree committed.
print_step("Overlay pinned go.mod/go.sum");
my $gomod_dir = "$pkg_dir/gomod";
die "pinned go.mod/go.sum missing under $gomod_dir (regenerate per gomod/README.md)\n"
    unless -f "$gomod_dir/go.mod" && -f "$gomod_dir/go.sum";
copy("$gomod_dir/go.mod", "$src_dir/go.mod") or die "copy go.mod: $!\n";
copy("$gomod_dir/go.sum", "$src_dir/go.sum") or die "copy go.sum: $!\n";

# --- Assemble SRPM sources: the source tree (incl. vendor) + the xcat-authored unit + config ---
print_step("Assemble SRPM sources");
my $srctop = "goconserver-$version";
my $staged = "$work_dir/$srctop";
remove_tree($staged) if -d $staged;
run("cp -a " . sh_quote($src_dir) . " " . sh_quote($staged));
my $sources_dir = "$work_dir/sources";
make_path($sources_dir);
my $tarball = "$sources_dir/goconserver-$version.tar.gz";
run("tar --sort=name --owner=0 --group=0 --mtime=\@$SOURCE_DATE_EPOCH" .
    " -C " . sh_quote($work_dir) . " -czf " . sh_quote($tarball) . " " . sh_quote($srctop));

write_file("$sources_dir/goconserver.service", <<'SERVICE');
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

# The goconserver binary parses server.conf as YAML. Ship a VALID YAML default (the old INI-style
# [server] block is read by the YAML parser as a sequence -> `panic: cannot unmarshal !!seq` at
# startup -> systemd rate-limits the service to `failed`). On an xCAT MN, xCAT::Goconserver.pm
# overwrites this with a cert-enabled config; this default only has to PARSE and start.
write_file("$sources_dir/server.conf", <<'CONF');
global:
  host: 0.0.0.0
  logfile: /var/log/goconserver/server.log
api:
  port: 12429
console:
  datadir: /var/lib/goconserver/
  port: 12430
  log_timestamp: true
CONF

# --- Spec: the Go compile runs in %build INSIDE the chroot, offline, from the vendored tree ---
print_step("Write spec");
my $spec_file = "$work_dir/goconserver.spec";
write_file($spec_file, <<"SPEC");
# Go binaries carry no useful DWARF debugsource; the empty debuginfo subpackage otherwise fails
# packaging ("Empty %files debugsourcefiles.list"). Disable it.
%global debug_package %{nil}
Name:           goconserver
Version:        $version
Release:        4.el$rel$release_suffix
Summary:        Console server written in Go for xCAT
License:        EPL-1.0
URL:            https://github.com/xcat2/goconserver
BuildArch:      $arch

Source0:        goconserver-%{version}.tar.gz
Source1:        goconserver.service
Source2:        server.conf

BuildRequires:  golang

%description
goconserver is a scalable console server written in Go. It provides
console logging and management for xCAT cluster nodes.

%prep
%setup -q -n goconserver-%{version}

%build
# Compile in-chroot. Modules are downloaded from the Go proxy at build time (mock networking is on)
# but PINNED + integrity-checked by the committed go.sum, so the build is reproducible without a
# vendored tree. GOTOOLCHAIN=local pins the chroot's Go (never auto-downloads a toolchain).
export GOFLAGS=-mod=mod GOTOOLCHAIN=local CGO_ENABLED=0
export GOCACHE=%{_builddir}/.gocache GOPATH=%{_builddir}/.gopath GOMODCACHE=%{_builddir}/.gomodcache
go build -trimpath -buildvcs=false -ldflags "-X main.Version=%{version}" -o goconserver goconserver.go
go build -trimpath -buildvcs=false -ldflags "-X main.Version=%{version}" -o congo cmd/congo.go

%install
install -Dm0755 goconserver %{buildroot}/usr/bin/goconserver
install -Dm0755 congo       %{buildroot}/usr/bin/congo
install -Dm0644 %{SOURCE1} %{buildroot}/usr/lib/systemd/system/goconserver.service
install -Dm0644 %{SOURCE2} %{buildroot}/etc/goconserver/server.conf
mkdir -p %{buildroot}/var/log/goconserver %{buildroot}/var/lib/goconserver

%files
/usr/bin/goconserver
/usr/bin/congo
/usr/lib/systemd/system/goconserver.service
%config(noreplace) /etc/goconserver/server.conf
%dir /var/log/goconserver
%dir /var/lib/goconserver

%changelog
* Mon Aug 10 2026 xCAT build - $version-4.el$rel
- Build inside a mock chroot (no host build). Modules are downloaded at build time but pinned +
  integrity-checked by a committed go.sum (no `go mod tidy`, no vendored tree). Compiled in the
  el10 chroot for the arch and shipped to every EL repo (CGO-free static binary).
- Ship /etc/goconserver/server.conf as YAML (the format the goconserver binary parses).
- Replace archived github.com/kr/pty with github.com/creack/pty (console fork on modern Go).
SPEC

# --- Build in the el10 chroot for this arch ---
my $mock_uniqueext_opt = $mock_uniqueext ne '' ? ' --uniqueext ' . sh_quote($mock_uniqueext) : '';
print_step("Mock config check");
run("mock -r " . sh_quote($build_cfg) . $mock_uniqueext_opt . " --print-root-path >/dev/null");
my $det_cfg = create_deterministic_mock_cfg($build_cfg, $SOURCE_DATE_EPOCH, $work_dir);

print_step("Build SRPM with mock");
my $srpm_out = "$work_dir/srpm";
make_path($srpm_out);
run("mock -r " . sh_quote($det_cfg) . $mock_uniqueext_opt .
    " --buildsrpm --spec " . sh_quote($spec_file) .
    " --sources " . sh_quote($sources_dir) .
    " --define " . sh_quote("use_source_date_epoch_as_buildtime 1") .
    " --define " . sh_quote("clamp_mtime_to_source_date_epoch 1") .
    " --define " . sh_quote("_buildhost xcat-build") .
    " --resultdir " . sh_quote($srpm_out) .
    " >" . sh_quote("$log_dir/mock-buildsrpm.log") . " 2>&1");
my @srpms = sort glob("$srpm_out/goconserver-*.src.rpm");
die "SRPM not generated in $srpm_out\n" if !@srpms;
my $srpm = $srpms[-1];
print "SRPM: $srpm\n";

print_step("Rebuild RPM with mock (offline, in-chroot go build)");
my $rpm_out = "$work_dir/rpm";
make_path($rpm_out);
run("mock -r " . sh_quote($det_cfg) . $mock_uniqueext_opt .
    " --rebuild " . sh_quote($srpm) .
    " --define " . sh_quote("use_source_date_epoch_as_buildtime 1") .
    " --define " . sh_quote("clamp_mtime_to_source_date_epoch 1") .
    " --define " . sh_quote("_buildhost xcat-build") .
    " --resultdir " . sh_quote($rpm_out) .
    " >" . sh_quote("$log_dir/mock-rebuild.log") . " 2>&1");

print_step("Collect results");
my @arch_rpms = sort grep { !/\.src\.rpm$/ } glob("$rpm_out/goconserver-*.$arch.rpm");
die "No goconserver $arch rpm generated in $rpm_out\n" if !@arch_rpms;
for my $rpm (@arch_rpms, glob("$rpm_out/*.src.rpm")) {
    my $dest = "$result_dir/" . basename($rpm);
    copy($rpm, $dest) or die "Failed to copy $rpm to $dest: $!\n";
    print "Copied: $dest\n";
}
for my $log (qw(build.log root.log state.log)) {
    my $s = "$rpm_out/$log";
    copy($s, "$log_dir/mock-$log") if -f $s;
}

# Reclaim goconserver's own build chroot. mockbuild-all's scrub keys on the TARGET cfg (el$rel), not
# the el10 build cfg used here, so scrub it ourselves to avoid leaking /var/lib/mock. Best-effort.
system("mock -r " . sh_quote($build_cfg) . $mock_uniqueext_opt .
       " --scrub=chroot >" . sh_quote("$log_dir/mock-scrub.log") . " 2>&1");

if (!$skip_install) {
    print_step("Install and smoke test");
    my $main_rpm = $arch_rpms[0];
    run("dnf -y install " . sh_quote($main_rpm) . " >" . sh_quote("$log_dir/dnf-install.log") . " 2>&1");
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

Build the goconserver RPM inside a mock chroot: fetch the pinned source, overlay the committed
go.mod/go.sum, and compile IN-CHROOT (modules downloaded at build time but pinned by go.sum -- no
vendored tree, no `go mod tidy`). The compile runs in the el10 chroot for the host arch (goconserver
is a CGO-free static binary; el8/el9 ship too old a Go), and the rpm is tagged with the target EL
(4.el<rel>) so every EL repo gets an identical static binary.

Options:
  --work-dir PATH       Working directory (default: /tmp/goconserver-mockbuild)
  --mock-cfg NAME       Target mock config (sets the EL dist tag; the build runs in its el10 peer)
  --mock-uniqueext STR  Mock uniqueext (for concurrency isolation under mockbuild-all.pl)
  --result-dir PATH     Output directory for RPMs
  --log-dir PATH        Output directory for logs
  --skip-install        Skip dnf install + smoke tests
  --version VER         Version string (default: 0.3.3)
  --go-repo URL         Git repo URL (default: github.com/xcat2/goconserver)
  --go-ref REF          Git ref/SHA to build (default: the pinned commit)
  --release-suffix STR  Appended to Release for CD (e.g. .snap<ts>.<n>)
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

sub create_deterministic_mock_cfg {
    my ($base_cfg, $epoch, $dir) = @_;
    my $cfg_path = "$dir/mock-deterministic.cfg";
    open my $fh, '>', $cfg_path or die "Cannot write $cfg_path: $!\n";
    print $fh "include('/etc/mock/${base_cfg}.cfg')\n";
    print $fh "config_opts['environment']['SOURCE_DATE_EPOCH'] = '$epoch'\n";
    print $fh "config_opts['environment']['ZERO_AR_DATE'] = '1'\n";
    # Allow network during %build so `go build` can download the (go.sum-pinned) modules -- we build
    # against the proxy rather than committing a vendored tree.
    print $fh "config_opts['rpmbuild_networking'] = True\n";
    print $fh "config_opts['use_host_resolv'] = True\n";
    close $fh;
    return $cfg_path;
}
