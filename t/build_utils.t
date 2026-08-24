use strict;
use warnings;

use File::Path qw(make_path);
use File::Temp qw(tempdir);
use FindBin;
use Test::More;

use lib "$FindBin::Bin/../lib";
use XCAT::BuildUtils qw(
  capture_command
  command_exists
  digest_file
  digest_manifest
  display_quote
  every_step_failed
  hashes_equal
  read_binary
  read_first_line
  read_lines
  relative_files
  require_command
  run_command
  shell_quote
  write_binary
);

my $tmp = tempdir(CLEANUP => 1);
write_binary("$tmp/alpha", "abc");
make_path("$tmp/nested");
write_binary("$tmp/nested/lines", "first\r\nsecond\n");

is(read_binary("$tmp/alpha"), 'abc', 'binary files round trip');
is_deeply(
    [ read_lines("$tmp/nested/lines") ],
    [ 'first', 'second' ],
    'line reader accepts CRLF and LF',
);
is(read_first_line("$tmp/nested/lines"), 'first', 'first line is returned');
is_deeply(
    [ relative_files($tmp) ],
    [ 'alpha', 'nested/lines' ],
    'regular files are sorted and relative',
);

my $sha256 = 'ba7816bf8f01cfea414140de5dae2223'
  . 'b00361a396177a9cb410ff61f20015ad';
is(digest_file("$tmp/alpha", 'sha256'), $sha256, 'SHA-256 matches a known value');
is(digest_file("$tmp/alpha", 'md5'), '900150983cd24fb0d6963f7d28e17f72',
    'MD5 matches a known value');
is(
    digest_manifest($tmp, 'sha256', 'alpha'),
    "$sha256  alpha\n",
    'digest manifest uses the release format',
);

ok(command_exists($^X), 'current Perl interpreter is executable');
is(capture_command($^X, '-e', 'print "captured\\n"'), 'captured',
    'command output is captured without a shell');
ok(run_command($^X, '-e', 'exit 0'), 'successful command returns true');

eval { run_command($^X, '-e', 'exit 7'); 1 };
like($@, qr/Command failed \(rc=7\)/, 'command failure reports its exit status');
eval { require_command("xcat-missing-command-$$"); 1 };
like($@, qr/Required command not found/, 'missing command is rejected');
eval { digest_file("$tmp/alpha", 'unknown'); 1 };
like($@, qr/Unsupported digest algorithm/, 'unknown digest is rejected');

is(display_quote('plain/value'), 'plain/value', 'simple display value is unquoted');
is(display_quote('two words'), q{'two words'}, 'display value with spaces is quoted');
is(shell_quote("it's"), q{'it'"'"'s'}, 'shell quote escapes apostrophes');
ok(every_step_failed(6, 6), 'every attempted step failing is reported');
ok(!every_step_failed(6, 5), 'one surviving step is not a total failure');
ok(!every_step_failed(0, 0), 'attempting no steps is not a failure');

ok(hashes_equal({ a => 1 }, { a => 1 }), 'equal hashes match');
ok(!hashes_equal({ a => 1 }, { a => 2 }), 'different hashes do not match');

my $link = "$tmp/link";
if (symlink('alpha', $link)) {
    eval { relative_files($tmp); 1 };
    like($@, qr/Symbolic links are not allowed/, 'directory walk rejects symlinks');
} else {
    fail('test filesystem supports symbolic links');
}

done_testing();
