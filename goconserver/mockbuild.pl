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
my $version     = '0.3.3';
my $go_repo     = 'https://github.com/xcat2/goconserver.git';
# Immutable pin: goconserver 0.3.3 is unreleased (newest tag v0.3.2) so it lives only on master.
# mockbuild-all.pl passes --go-ref with the canonical pin; this default keeps standalone runs
# reproducible too. The committed go.mod/go.sum (no vendor tree) correspond to THIS SHA.
my $go_ref      = '6166fe5ec1c5b3c20475e322a9f0e8e93c87e45f';
my $release_suffix = '';   # CD Release bump (".snap<YYYYMMDDHHMM>.<n>"); passed by mockbuild-all.pl
my $build_timestamp;

GetOptions(
    'work-dir=s'       => \$work_dir,
    'mock-cfg=s'       => \$mock_cfg,
    'target-arch=s'    => \$target_arch,
    'mock-uniqueext=s' => \$mock_uniqueext,
    'result-dir=s'     => \$result_dir,
    'log-dir=s'        => \$log_dir,
    'version=s'        => \$version,
    'go-repo=s'        => \$go_repo,
    'go-ref=s'         => \$go_ref,
    'release-suffix=s' => \$release_suffix,
    'build-timestamp=i' => \$build_timestamp,
) or die usage();

die "Run as root (current uid=$>)\n" if $> != 0;

my $arch = capture('uname -m');
if (!$mock_cfg) {
    my $os_id = capture(q{bash -lc 'source /etc/os-release; echo $ID'});
    $mock_cfg = resolve_mock_cfg($os_id, '10', $arch);
}

my ($rel) = $mock_cfg =~ /-(\d+)-/;
$rel //= '10';

# --target-arch names the arch of the rpm to produce. It differs from the host arch only for a
# forcearch target (rocky-10-riscv64-xcat on an x86_64 host; see BUILD.md "riscv64").
$target_arch = $arch if $target_arch eq '';
my %goarch = (x86_64 => 'amd64', aarch64 => 'arm64', ppc64le => 'ppc64le', s390x => 's390x', riscv64 => 'riscv64');
my $cross = $target_arch ne $arch;
die "No GOARCH known for target arch $target_arch\n" if $cross && !exists $goarch{$target_arch};

# For the host arch the Go compile happens INSIDE the mock chroot (BuildRequires: golang), so the
# host only fetches the pinned source and drives mock. A forcearch chroot would run that compile
# under qemu, so the cross build instead cross-compiles on the host and packages the result with
# rpmbuild --target.
for my $bin (qw(git rpm), ($cross ? qw(go rpmbuild) : qw(mock))) {
    run("command -v " . sh_quote($bin) . " >/dev/null 2>&1");
}

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
print "build_cfg:    $build_cfg (el10 -- portable static build for arch $arch)\n" if !$cross;
print "arch:         $arch\n";
print "target_arch:  $target_arch" . ($cross ? " (GOARCH=$goarch{$target_arch}, rpmbuild --target)" : '') . "\n";
print "version:      $version\n";
print "go_ref:       $go_ref\n";
print "release_suffix: " . ($release_suffix ne '' ? $release_suffix : '(none)') . "\n";

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

my $service_unit = <<'SERVICE';
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
my $server_conf = <<'CONF';
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

if ($cross) {
    cross_build_and_package();
    exit 0;
}


# --- Assemble SRPM sources: the source tree (go.mod/go.sum, no vendor) + the xcat-authored unit + config ---
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

write_file("$sources_dir/goconserver.service", $service_unit);
write_file("$sources_dir/server.conf", $server_conf);

# --- Spec: the Go compile runs in %build INSIDE the chroot; modules fetched from the proxy, pinned by go.sum ---
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
# Scrub BOTH the chroot and its bootstrap: the el10 build cfg is bootstrap-image based, so
# --scrub=chroot alone leaves the ~190 MiB <cfg>-bootstrap-<uniqueext> tree behind (it accumulated
# one per target per run in /var/lib/mock -- the disk leak of VersatusHPC/xcat-core#51).
system("mock -r " . sh_quote($build_cfg) . $mock_uniqueext_opt .
       " --scrub=chroot --scrub=bootstrap >" . sh_quote("$log_dir/mock-scrub.log") . " 2>&1");

print_step("Completed");
print "Results in: $result_dir\n";
exit 0;


# A forcearch mock chroot runs every command through qemu, so an in-chroot Go compile would run the
# whole toolchain emulated. For a foreign target arch the build cross-compiles on the host with the
# same pinned go.mod/go.sum and lets rpmbuild --target name the arch. See BUILD.md ("riscv64").
sub cross_build_and_package {
    my $rpmbuild_top = "$work_dir/rpmbuild";
    remove_tree($rpmbuild_top) if -d $rpmbuild_top;
    make_path("$rpmbuild_top/$_") for qw(BUILD BUILDROOT RPMS SOURCES SPECS SRPMS);

    print_step("Cross-compile goconserver for $target_arch");
    local $ENV{GOPATH}      = "$work_dir/gopath";
    local $ENV{GOCACHE}     = "$work_dir/gocache";
    local $ENV{GOMODCACHE}  = "$work_dir/gomodcache";
    local $ENV{CGO_ENABLED} = '0';
    local $ENV{GOFLAGS}     = '-mod=mod';
    local $ENV{GOTOOLCHAIN} = 'local';
    local $ENV{GOARCH}      = $goarch{$target_arch};

    my $bin_dir = "$work_dir/bin";
    make_path($bin_dir);
    # rpm's brp-strip cannot strip a foreign-arch ELF, so the Go linker strips instead.
    my $ldflags = "-X main.Version=$version -s -w";
    for my $target (['goconserver', 'goconserver.go'], ['congo', 'cmd/congo.go']) {
        my ($out, $main) = @{$target};
        run("cd " . sh_quote($src_dir) . " && go build -trimpath -buildvcs=false -ldflags " .
            sh_quote($ldflags) . " -o " . sh_quote("$bin_dir/$out") . " " . sh_quote($main) .
            " >" . sh_quote("$log_dir/go-build-$out.log") . " 2>&1");
        die "$out binary not built\n" if !-x "$bin_dir/$out";
    }

    print_step("Assemble SRPM sources");
    my $srctop  = "goconserver-$version";
    my $payload = "$work_dir/$srctop";
    remove_tree($payload) if -d $payload;
    make_path("$payload/usr/bin", "$payload/usr/lib/systemd/system", "$payload/etc/goconserver");
    for my $out (qw(goconserver congo)) {
        copy("$bin_dir/$out", "$payload/usr/bin/$out") or die "copy $out: $!\n";
        chmod 0755, "$payload/usr/bin/$out";
    }
    write_file("$payload/usr/lib/systemd/system/goconserver.service", $service_unit);
    write_file("$payload/etc/goconserver/server.conf", $server_conf);
    run("tar --sort=name --owner=0 --group=0 --mtime=\@$SOURCE_DATE_EPOCH" .
        " -C " . sh_quote($work_dir) . " -czf " . sh_quote("$rpmbuild_top/SOURCES/$srctop.tar.gz") .
        " " . sh_quote($srctop));

    print_step("Write spec");
    my $spec_file = "$rpmbuild_top/SPECS/goconserver.spec";
    # The payload is already compiled, so there is no %build. rpm refuses a foreign 'BuildArch:'
    # here; rpmbuild --target below sets the arch.
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

Source0:        goconserver-%{version}.tar.gz

%description
goconserver is a scalable console server written in Go. It provides
console logging and management for xCAT cluster nodes.

%prep
%setup -q -n goconserver-%{version}

%install
install -Dm0755 usr/bin/goconserver %{buildroot}/usr/bin/goconserver
install -Dm0755 usr/bin/congo       %{buildroot}/usr/bin/congo
install -Dm0644 usr/lib/systemd/system/goconserver.service %{buildroot}/usr/lib/systemd/system/goconserver.service
install -Dm0644 etc/goconserver/server.conf %{buildroot}/etc/goconserver/server.conf
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
- Cross-compile on the build host (GOARCH=$goarch{$target_arch}) with the committed go.mod/go.sum,
  and package with rpmbuild --target $target_arch. The forcearch chroot would run the Go toolchain
  under qemu.
- Ship /etc/goconserver/server.conf as YAML (the format the goconserver binary parses).
- Replace archived github.com/kr/pty with github.com/creack/pty (console fork on modern Go).
SPEC

    print_step("Build RPM with rpmbuild --target $target_arch");
    run("rpmbuild --define " . sh_quote("_topdir $rpmbuild_top") .
        " --define " . sh_quote("use_source_date_epoch_as_buildtime 1") .
        " --define " . sh_quote("clamp_mtime_to_source_date_epoch 1") .
        " --define " . sh_quote("_buildhost xcat-build") .
        " --target " . sh_quote($target_arch) .
        " -ba " . sh_quote($spec_file) .
        " >" . sh_quote("$log_dir/rpmbuild.log") . " 2>&1");

    print_step("Collect results");
    my @arch_rpms = sort glob("$rpmbuild_top/RPMS/$target_arch/goconserver-*.rpm");
    die "No goconserver $target_arch rpm generated in $rpmbuild_top/RPMS\n" if !@arch_rpms;
    for my $rpm (@arch_rpms, glob("$rpmbuild_top/SRPMS/*.src.rpm")) {
        my $dest = "$result_dir/" . basename($rpm);
        copy($rpm, $dest) or die "Failed to copy $rpm to $dest: $!\n";
        print "Copied: $dest\n";
    }

    # The rpm cannot be installed on this host, and nothing else runs the cross-built binaries.
    # Unpack it and run them through the binfmt_misc handler the forcearch chroot needs anyway.
    print_step("Smoke test the $target_arch binaries (binfmt)");
    my $smoke_root = "$work_dir/smoke-root";
    remove_tree($smoke_root) if -d $smoke_root;
    make_path($smoke_root);
    run("cd " . sh_quote($smoke_root) . " && rpm2cpio " . sh_quote($arch_rpms[0]) .
        " | cpio -idm --quiet >" . sh_quote("$log_dir/smoke-unpack.log") . " 2>&1");
    for my $out (qw(goconserver congo)) {
        my $path = "$smoke_root/usr/bin/$out";
        die "Missing $path in the $target_arch rpm\n" if !-x $path;
        # -h exits 0 or 1 depending on the subcommand parser; anything above that is a real failure.
        my $rc = run_rc(sh_quote($path) . " -h >" . sh_quote("$log_dir/smoke-$out.log") . " 2>&1");
        die "$out -h failed (rc=$rc): running a $target_arch binary on this $arch host needs the" .
            " qemu-user-static binfmt handler\n" if $rc > 1;
    }
    print "Smoke tests passed ($target_arch binaries ran through binfmt).\n";

    print_step("Completed");
    print "Results in: $result_dir\n";
    return;
}

sub run_rc {
    my ($cmd) = @_;
    print "+ $cmd\n";
    my $rc = system($cmd);
    return $rc == -1 ? 255 : ($rc >> 8);
}

sub usage {
    return <<"USAGE";
Usage: $0 [options]

Build the goconserver RPM: fetch the pinned source, overlay the committed go.mod/go.sum, and
compile (modules downloaded at build time but pinned by go.sum -- no vendored tree, no
`go mod tidy`). For the host arch the compile runs IN-CHROOT, in the el10 chroot (goconserver is a
CGO-free static binary; el8/el9 ship too old a Go). For a foreign --target-arch it cross-compiles on
the host, because a forcearch chroot would run the Go toolchain under qemu. Either way the rpm is
tagged with the target EL (4.el<rel>) so every EL repo gets an identical static binary.

Options:
  --work-dir PATH       Working directory (default: /tmp/goconserver-mockbuild)
  --mock-cfg NAME       Target mock config (sets the EL dist tag; the build runs in its el10 peer)
  --target-arch ARCH    Arch of the rpm to build (default: uname -m); another arch is
                        cross-compiled (GOARCH) and packaged with rpmbuild --target
  --mock-uniqueext STR  Mock uniqueext (for concurrency isolation under mockbuild-all.pl)
  --result-dir PATH     Output directory for RPMs
  --log-dir PATH        Output directory for logs
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
