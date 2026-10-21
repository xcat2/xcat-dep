#!/usr/bin/perl
# Every openEuler ppc64le native prerequisite after procenv itself fails before rpmbuild starts:
#
#   FileNotFoundError: [Errno 2] No such file or directory: '/usr/bin/procenv'
#
# raised from mock's procenv plugin prebuild hook. The plugin runs ["/usr/bin/procenv"] through
# mockbuild.util.do with no chroot prefix, so it executes the BUILD HOST's copy, and
# xcat-master-ppc has none. Installing procenv in the chroot does not help: mock already appends it
# to preexisting_deps itself, and the run that did so still failed with the same line while
# root.log recorded "Installing : procenv-0.60-1.ppc64le".
#
# mock ships procenv_enable False. The overlays turned it on, which made every native build depend
# on a host package that neither repository declares, for a procenv.log nothing reads. They now
# leave it at the default.
#
# native_overlay_text is pure, so this runs no mock.
use strict;
use warnings;
use Test::More;
use FindBin qw($RealBin);
use lib "$RealBin/../lib";
use XCAT::NativeInputs qw(native_overlay_text);

my $base    = '/opt/xcat-ci-shared/builds/oe264/work/native-base.cfg';
my $prereqs = '/opt/xcat-ci-shared/builds/oe264/work/native-prerequisites';

for my $purpose (1000, 0, 'procenv') {
    my $text = native_overlay_text($purpose, $base, $prereqs);
    unlike($text, qr/procenv_enable'\]\s*=\s*True/,
           "overlay $purpose does not enable the procenv plugin, which needs a host binary");
    # The overlay must still carry what the native build does depend on.
    like($text, qr/\[xcat-native-inputs\]/, "overlay $purpose still declares the prerequisite repository");
    like($text, qr/bind_mount_enable'\]\s*=\s*True/, "overlay $purpose still binds the prerequisite tree");
}

# The uid split is declared in the inputs and must not move: genesis builds as root, the rest as
# 1000, and the procenv overlay runs as 1000 too.
is((native_overlay_text(1000, $base, $prereqs) =~ /chrootuid'\]\s*=\s*(\d+)/)[0], 1000,
   'the unprivileged overlay still runs as uid 1000');
is((native_overlay_text(0, $base, $prereqs) =~ /chrootuid'\]\s*=\s*(\d+)/)[0], 0,
   'the genesis overlay still runs as root');

done_testing();
