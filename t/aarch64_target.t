#!/usr/bin/env perl
# The EL10 aarch64 target: its manifest cell, the x86 boot loaders it builds natively like ppc64le,
# and the grub2.aarch64 network loader grub2-xcat generates for aarch64 nodes.
#
# alma+epel-10-aarch64 is a native EPEL target, so it must ship what the EL10 x86_64 cell ships: a
# service node perl package missing there would leave `dnf install xCATsn` unresolvable on aarch64
# only. aarch64 nodes boot through UEFI and grub2, and xCAT hands them boot/grub2/grub2.aarch64.
# The distro grubaa64.efi cannot be that file (its prefix is the distro's /EFI/<vendor>), so the
# spec generates one with grub2-mkimage and the /boot/grub2 prefix; efi_uga must stay out of the
# module list, because it is x86 only and grub2-mkimage aborts on it for arm64-efi.
use strict;
use warnings;

use File::Temp qw(tempdir);
use FindBin qw($RealBin);
use Test::More;

use lib $RealBin, "$RealBin/..";
use MockBuildUtils qw(read_manifest);

my $root   = "$RealBin/..";
my $target = 'alma+epel-10-aarch64';

sub slurp {
    my ($path) = @_;
    open(my $fh, '<', $path) or die "read $path: $!";
    local $/;
    return scalar <$fh>;
}

# The body of one spec section (%build, %install, %post, ...), up to the next section.
sub section {
    my ($spec, $name) = @_;
    my ($body) = $spec =~ /^%\Q$name\E[ \t]*\n(.*?)(?=^%(?:prep|build|install|check|clean|files|pre|post|preun|postun|changelog|description|package)\b|\z)/ms;
    return $body // '';
}

# The grub2-mkimage invocation of a spec text, joined across its continuation lines.
sub mkimage_command {
    my ($text) = @_;
    my ($cmd) = $text =~ /^(grub2-mkimage\b(?:[^\n]*\\\n)*[^\n]*)$/m;
    return unless defined $cmd;
    $cmd =~ s/\\\n/ /g;
    return $cmd;
}

# rpmspec -P of a spec under extra macro definitions, or undef when rpmspec is unavailable.
my $have_rpmspec = system('command -v rpmspec >/dev/null 2>&1') == 0;
sub parsed_spec {
    my ($spec, %define) = @_;
    return unless $have_rpmspec;
    my @args = map { ('--define', "$_ $define{$_}") } sort keys %define;
    # rpmspec warns about the specs' old %patchN and macros in comments; keep that out of TAP.
    open(my $save, '>&', \*STDERR) or die "dup STDERR: $!";
    open(STDERR, '>', '/dev/null') or die "mute STDERR: $!";
    my $out;
    if (open(my $fh, '-|', 'rpmspec', '-P', @args, $spec)) {
        local $/;
        $out = <$fh>;
        $out = undef unless close($fh);
    }
    open(STDERR, '>&', $save) or die "restore STDERR: $!";
    return $out;
}

# ---- the manifest cell ---------------------------------------------------------------------------
{
    my %m = read_manifest("$root/packages-manifest.conf");
    my $cell = $m{$target};
    ok($cell, "the manifest has a [$target] section") or $cell = {};

    # A native EPEL target: the same packages at the same pins as EL10 x86_64, the service node
    # perl set (perl-Crypt-CBC ... perl-Net-DNS) and xCAT-genesis-base included.
    is_deeply($cell, $m{'alma+epel-10-x86_64'},
        "[$target] lists what [alma+epel-10-x86_64] lists, at the same pins");

    # The x86 boot loaders are noarch and an aarch64 management node serves the x86 nodes of a mixed
    # cluster, as a ppc64le one does.
    for my $boot (qw(elilo-xcat grub2-xcat ipxe-xcat syslinux-xcat xnba-undi)) {
        is($cell->{$boot}, $m{'alma+epel-10-ppc64le'}{$boot},
            "$boot pinned in [$target] as in the EL10 ppc64le target");
    }
}

# ---- grub2-xcat: generate, ship and install grub2.aarch64 --------------------------------------
my $grub_spec_file = "$root/grub2-xcat/grub2-xcat.spec";
my $grub_spec = slurp($grub_spec_file);
{
    like($grub_spec, qr/^BuildRequires:\s*grub2-tools\s*$/m, 'grub2-xcat BuildRequires grub2-tools');
    like($grub_spec, qr/^BuildRequires:\s*grub2-efi-aa64-modules\s*$/m,
        'grub2-xcat BuildRequires the noarch arm64-efi grub modules');

    my $cmd = mkimage_command(section($grub_spec, 'build'));
    ok(defined $cmd, '%build runs grub2-mkimage') or $cmd = '';
    like($cmd, qr/(?:^|\s)-O\s+arm64-efi(?:\s|$)/, '... for the arm64-efi platform');
    like($cmd, qr/(?:^|\s)-p\s+\/boot\/grub2(?:\s|$)/, '... with the /boot/grub2 prefix grub2.ppc uses');
    like($cmd, qr/(?:^|\s)-o\s+\S*grubaa64\.efi(?:\s|$)/, '... into grubaa64.efi');
    my @modules = split ' ', ($cmd =~ /grubaa64\.efi\s+(.*)$/)[0] // '';
    for my $mod (qw(tftp efinet net http normal linux configfile search)) {
        ok((grep { $_ eq $mod } @modules), "... with the $mod module");
    }
    ok(!(grep { $_ eq 'efi_uga' } @modules), '... and without efi_uga (x86 only)');

    like(section($grub_spec, 'install'),
        qr{^install -m 0644 \S*grubaa64\.efi \$RPM_BUILD_ROOT/%\{prefix\}/aarch64-efi/grubaa64\.efi$}m,
        '%install ships it as aarch64-efi/grubaa64.efi');
    like(section($grub_spec, 'files'), qr{^%\{prefix\}/aarch64-efi/$}m, '%files owns aarch64-efi/');
    like(section($grub_spec, 'post'),
        qr{^\s*cp\s+%\{prefix\}/aarch64-efi/grubaa64\.efi %\{prefix\}/grub2\.aarch64$}m,
        '%post installs it as grub2.aarch64');
    like(section($grub_spec, 'postun'), qr{^\s*rm -f %\{prefix\}/grub2\.aarch64$}m,
        '%postun removes grub2.aarch64');

  SKIP: {
        skip 'rpmspec not available', 4 unless $have_rpmspec;
        my $el = parsed_spec($grub_spec_file, rhel => 10);
        ok(defined $el, 'rpmspec parses grub2-xcat.spec for EL10') or $el = '';
        like($el, qr/^BuildRequires:\s*grub2-efi-aa64-modules\s*$/m, '... and EL keeps the aarch64 image');

        # openEuler's x86_64 repositories carry no grub2-efi-aa64-modules: there the image is
        # neither required nor shipped, and %post must not copy a file that is not there.
        my $oe = parsed_spec($grub_spec_file, openEuler => 1);
        ok(defined $oe && $oe !~ /grub2-efi-aa64-modules|grub2-mkimage|aarch64-efi\/$/m,
            'openEuler builds without the aarch64 image');
        like($oe // '', qr{if \[ -f /tftpboot/boot/grub2/aarch64-efi/grubaa64\.efi \]},
            '... and its %post copies grub2.aarch64 only when the image exists');
    }

    # Run the spec's own command where the arm64-efi modules are installed: a module the grub
    # build does not carry, or efi_uga, makes grub2-mkimage fail.
  SKIP: {
        my $moddir = '/usr/lib/grub/arm64-efi';
        # Debian and Ubuntu name the tool grub-mkimage and EL names it grub2-mkimage. The CI
        # runner is Ubuntu, so looking only for the EL name skips the checks exactly where the
        # suite runs, which measures nothing.
        my ($mkimage) = grep { system("command -v $_ >/dev/null 2>&1") == 0 }
                        qw(grub2-mkimage grub-mkimage);
        skip 'no grub2-mkimage or grub-mkimage, or the arm64-efi grub modules are not installed', 4
            unless -d $moddir && $mkimage;
        skip 'no grub2-mkimage command in the spec', 4 if $cmd eq '';
        my $tmp = tempdir(CLEANUP => 1);
        my $run = $cmd;
        $run =~ s/\Agrub2-mkimage\b/$mkimage/;
        $run =~ s/(?<=\s-o\s)\S+/$tmp\/grubaa64.efi/;
        is(system("$run >/dev/null 2>&1"), 0, "the spec's grub2-mkimage command succeeds");
        my $image = '';
        if (open(my $fh, '<:raw', "$tmp/grubaa64.efi")) { local $/; $image = <$fh> // ''; }
        my $pe = length($image) > 0x40 ? unpack('V', substr($image, 0x3c, 4)) : 0;
        is(length($image) > $pe + 6 ? unpack('v', substr($image, $pe + 4, 2)) : 0, 0xaa64,
            '... and writes an AArch64 PE image');
        like($image, qr{/boot/grub2\0}, '... whose embedded prefix is /boot/grub2');
        isnt(system("$run efi_uga >/dev/null 2>&1"), 0, 'adding efi_uga makes the command fail');
    }
}

# ---- the x86 boot loaders build natively on aarch64, as on ppc64le -----------------------------
{
    my $syslinux = slurp("$root/syslinux/syslinux-xcat.spec");
    my ($exclusive) = $syslinux =~ /^ExclusiveArch:\s*(.*?)\s*$/m;
    my %arches = map { $_ => 1 } split ' ', $exclusive // '';
    ok($arches{aarch64} && $arches{ppc64le}, 'syslinux ExclusiveArch admits aarch64 beside ppc64le');
    my @ppc_only = $syslinux =~ /^%ifn?arch ppc64le\s*$/mg;
    is_deeply(\@ppc_only, [], 'every ppc64le arch conditional of syslinux covers aarch64 as well');

    my $elilo_file = "$root/elilo/elilo-xcat.spec";
  SKIP: {
        skip 'rpmspec not available', 2 unless $have_rpmspec;
        my $aa64 = parsed_spec($elilo_file, _host_cpu => 'aarch64', rhel => 10) // '';
        unlike($aa64, qr/^BuildRequires:\s*gnu-efi/m,
            'elilo on aarch64 needs no gnu-efi (it ships the tracked prebuilt EFI payload)');
        my $x86 = parsed_spec($elilo_file, _host_cpu => 'x86_64', rhel => 10) // '';
        like($x86, qr/^BuildRequires:\s*gnu-efi/m, '... while EL10 x86_64 still compiles it');
    }
}

done_testing;
