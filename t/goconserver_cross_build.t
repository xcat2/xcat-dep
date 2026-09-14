#!/usr/bin/perl
# Behaviour test for the Go toolchain the Ubuntu goconserver build uses.
#
# riscv64 has no build host, so its chroot runs under qemu-user. A Go toolchain built FOR riscv64
# therefore runs emulated, and `go build` parks its threads in futex_wait and never finishes: three
# xcat-dep-ubuntu-cd riscv64 cells burned the whole 9000s budget with no CPU ticks at all. Go
# cross-compiles, so the toolchain must be the BUILD HOST's and the target must come from GOARCH.
#
# The test LIFTS the build shell out of goconserver/sbuild.pl, RUNS it, and asserts on what the run
# asked for -- the toolchain tarball it fetched, and the environment the real debian/rules passed to
# `go build`. It never matches the source of the thing it tests.
#
# Every command that could write outside the scratch tree is shadowed by a recorder that refuses the
# write and reports it, so a build that reaches for /usr/local is a FAILED assertion here rather than
# damage to the host running the suite.
use strict;
use warnings;
use Test::More;
use File::Temp qw(tempdir);
use File::Path qw(make_path);
use FindBin qw($RealBin);

my $pkg_dir = "$RealBin/../goconserver";
plan skip_all => 'goconserver/sbuild.pl not found' unless -f "$pkg_dir/sbuild.pl";
plan skip_all => 'bash is not available'           unless -x '/bin/bash';

my $LIFT = 'lifted by t/goconserver_cross_build.t';

# The build shell, produced by the real builder code. The whole marked region is evaluated, so the
# architecture the builder stamps into the script comes from the builder rather than from this test.
# die (never BAIL_OUT) when the lift stops matching: prove stops the WHOLE suite on a bail-out, and a
# silent miss would leave this file covering nothing.
sub build_script {
    open(my $fh, '<', "$pkg_dir/sbuild.pl") or die "read sbuild.pl: $!";
    my $src = do { local $/; <$fh> };
    close($fh);
    my ($region) = $src =~ /^\#[^\n]*\Q$LIFT\E[^\n]*\n(.*?^BUILD$)/ms
        or die "goconserver/sbuild.pl no longer marks its build script with '$LIFT' -- "
             . "this test can no longer reach the code it covers\n";
    my $build = eval "$region\n\$build";     ## no critic
    die "could not evaluate the lifted build script: $@\n" if $@;
    die "the lifted build script is empty\n" unless defined $build && $build =~ /\S/;
    return $build;
}

sub write_stub {
    my ($dir, $name, $body) = @_;
    open(my $fh, '>', "$dir/$name") or die "write $dir/$name: $!";
    print {$fh} "#!/bin/bash\n$body\n";
    close($fh);
    chmod(0755, "$dir/$name") or die "chmod $dir/$name: $!";
}

# run_build($target_arch): run the build shell with the chroot's architecture reported as
# $target_arch, and return what it asked the outside world to do.
sub run_build {
    my ($target_arch) = @_;
    my $root = tempdir(CLEANUP => 1);
    my ($bin, $rec, $work) = ("$root/bin", "$root/rec", "$root/work");
    make_path($bin, $rec, $work);

    # The build runs with CWD = a copy of the package dir, and reads ../gomod and ./debian from it.
    system('cp', '-rL', "$pkg_dir/$_", "$work/$_") == 0 or die "stage $_: $!" for qw(gomod debian);

    # dpkg answers for the CHROOT, which is the architecture the build must produce.
    write_stub($bin, 'dpkg', qq{
        [ "\$1" = --print-architecture ] && { echo '$target_arch'; exit 0; }
        exec /usr/bin/dpkg "\$\@"
    });
    write_stub($bin, 'curl', qq{
        for a in "\$\@"; do case "\$a" in http*) echo "\$a" >> '$rec/curl-urls';; esac; done
        exit 0
    });
    # tar and rm police their target: anything outside the scratch tree is recorded, not performed.
    write_stub($bin, 'tar', qq{
        dest=''; prev=''
        for a in "\$\@"; do [ "\$prev" = -C ] && dest="\$a"; prev="\$a"; done
        case "\$dest" in '$root'/*) ;; *) echo "tar -C \$dest" >> '$rec/escapes';; esac
        exit 0
    });
    write_stub($bin, 'rm', qq{
        for a in "\$\@"; do
            case "\$a" in
                -*|'$root'/*) ;;
                /*) echo "rm \$a" >> '$rec/escapes'; exit 0;;
            esac
        done
        exec /bin/rm "\$\@"
    });
    # Only `git init <dir>` has to have an effect; the clone has no source this test needs.
    write_stub($bin, 'git', qq{
        if [ "\$1" = init ]; then shift
            for a in "\$\@"; do case "\$a" in -*) ;; *) mkdir -p "\$a";; esac; done
        fi
        exit 0
    });
    write_stub($bin, 'dch', 'exit 0');
    # The real debian/rules has to see the environment, so run its build target for real.
    write_stub($bin, 'dpkg-buildpackage', 'make -f debian/rules override_dh_auto_build');
    # The downloaded toolchain never lands, so `go` always resolves here. It records the environment
    # of each invocation, which is the thing under test.
    write_stub($bin, 'go', qq{
        echo "GOARCH=\${GOARCH-} GOOS=\${GOOS-} ARGV=\$*" >> '$rec/go-calls'
        exit 0
    });

    open(my $fh, '>', "$root/build.sh") or die "write build.sh: $!";
    print {$fh} build_script();
    close($fh);

    my $rc = system('/bin/bash', '-c',
        "cd '$work' && PATH=\"$bin:\$PATH\" SOURCE_DATE_EPOCH=1789413339 "
      . "bash '$root/build.sh' > '$root/build.log' 2>&1");

    my $slurp = sub {
        my ($f) = @_;
        return () unless -f "$rec/$f";
        open(my $h, '<', "$rec/$f") or return ();
        my @l = <$h>; close($h); chomp @l; return @l;
    };
    open(my $lh, '<', "$root/build.log") or die "read build.log: $!";
    my $log = do { local $/; <$lh> };
    close($lh);
    return { rc => $rc, log => $log // '',
             curl     => [ $slurp->('curl-urls') ],
             go_calls => [ $slurp->('go-calls') ],
             escapes  => [ $slurp->('escapes') ] };
}

# The architecture the toolchain must be built for: this machine's, in Go's spelling.
my $host_deb = `dpkg --print-architecture 2>/dev/null` // '';
chomp $host_deb;
plan skip_all => 'dpkg is not available' unless $host_deb =~ /^[a-z0-9]+$/;
my $host_go = $host_deb eq 'ppc64el' ? 'ppc64le' : $host_deb;

# ---- the cell that failed: a riscv64 chroot on this build host ----------------------------------
my $r = run_build('riscv64');

my ($toolchain) = grep { m{/go[\d.]+\.linux-} } @{ $r->{curl} };
ok(defined $toolchain, 'the build fetches a pinned Go toolchain')
    or diag("curl was asked for: @{ $r->{curl} }\n$r->{log}");

SKIP: {
    skip 'no toolchain download to inspect', 1 unless defined $toolchain;
    like($toolchain, qr/\.linux-\Q$host_go\E\.tar\.gz$/,
        "the toolchain is built for the build host ($host_go), so it runs natively not under qemu")
        or diag("fetched: $toolchain");
}

# compiles_for($result, $goarch, $label): every `go build` the run reached was told to emit $goarch.
# A run that reached NO `go build` fails here: an empty list would otherwise satisfy any claim.
sub compiles_for {
    my ($res, $goarch, $label) = @_;
    my @builds = grep { /ARGV=.*\bbuild\b/ } @{ $res->{go_calls} };
    unless (@builds) {
        fail("$label -- the run never reached `go build`");
        diag("go was called: @{ $res->{go_calls} }\nrc=$res->{rc}\n$res->{log}");
        return;
    }
    is_deeply([ grep { !/\bGOARCH=\Q$goarch\E\b/ } @builds ], [], $label)
        or diag("go build calls:\n" . join("\n", @builds));
}

compiles_for($r, 'riscv64',
    'every `go build` is told to emit riscv64, so the native toolchain cross-compiles');

is_deeply($r->{escapes}, [],
    'the build writes and deletes only inside its own build tree')
    or diag("escaped the build tree:\n" . join("\n", @{ $r->{escapes} }));

# ---- a chroot of the host's own architecture still builds natively ------------------------------
my $n = run_build($host_deb);
my ($native) = grep { m{/go[\d.]+\.linux-} } @{ $n->{curl} };
like($native // '', qr/\.linux-\Q$host_go\E\.tar\.gz$/,
    'a native cell fetches the same toolchain');
compiles_for($n, $host_go, 'a native cell compiles for its own architecture');

# ---- dpkg and Go spell the POWER architecture differently ----------------------------------------
my $p = run_build('ppc64el');
compiles_for($p, 'ppc64le', 'the dpkg name ppc64el reaches go as ppc64le');

done_testing;
