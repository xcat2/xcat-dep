package XCAT::NativeInputs;

use strict;
use warnings;

use Cwd qw(abs_path);
use Digest::SHA ();
use Exporter qw(import);
use File::Basename qw(basename);
use File::Copy qw(copy);
use File::Path qw(make_path);
use File::Temp qw(tempdir);
use JSON::PP;

our @EXPORT_OK = qw(load_inputs stage_inputs verify_input rpm_identity validate_outputs publisher_trust);

sub read_file {
    my ($path) = @_;
    open my $fh, '<', $path or die "Cannot read $path: $!\n";
    local $/;
    my $data = <$fh>;
    close $fh or die "Cannot close $path: $!\n";
    return $data;
}

sub sha256 {
    my ($path) = @_;
    open my $fh, '<', $path or die "Cannot read $path: $!\n";
    binmode $fh;
    my $sha = Digest::SHA->new(256)->addfile($fh)->hexdigest;
    close $fh or die "Cannot close $path: $!\n";
    return $sha;
}

sub capture {
    my (@args) = @_;
    open my $fh, '-|', @args or die "Cannot execute $args[0]: $!\n";
    local $/;
    my $out = <$fh> // '';
    close $fh or die "Command failed: @args\n";
    $out =~ s/\s+\z//;
    return $out;
}

sub run {
    my (@args) = @_;
    system(@args) == 0 or die "Command failed: @args\n";
}

sub pinned_file {
    my ($root, $entry) = @_;
    die "Invalid pinned path\n" unless ($entry->{path} // '') =~ m{\A[\w./-]+\z}
        && $entry->{path} !~ m{(?:\A|/)\.\.(?:/|\z)|\A/};
    die "Missing input $entry->{path}\n" unless -f "$root/$entry->{path}";
    my $path = abs_path("$root/$entry->{path}") // die "Missing input $entry->{path}\n";
    die "Input escapes repository: $entry->{path}\n" unless index($path, "$root/") == 0;
    die "Input SHA256 mismatch: $entry->{path}\n" unless sha256($path) eq ($entry->{sha256} // '');
    return $path;
}

sub load_inputs {
    my ($root, $required) = @_;
    $root = abs_path($root) // die "Missing repository\n";
    my $catalog_path = "$root/openeuler/24.03-ppc64le.inputs.json";
    my $catalog = JSON::PP->new->decode(read_file($catalog_path));
    die "Unsupported native input catalog\n" unless ($catalog->{version} // 0) == 1
        && ($catalog->{target} // '') eq 'openeuler-24.03-ppc64le';
    my $key = $catalog->{publisher_key};
    die "Invalid publisher fingerprint\n" unless ($key->{fingerprint} // '') =~ /\A[0-9A-F]{40}\z/;
    my $key_path = pinned_file($root, $key);
    my (%nodes, %outputs);
    for my $node (@{$catalog->{inputs}}) {
        my $name = $node->{name} // '';
        die "Invalid native input name '$name'\n" unless $name =~ /\A[\w+.-]+\z/;
        die "Duplicate native input '$name'\n" if $nodes{$name};
        my $type = $node->{type} // '';
        die "Invalid native input type '$type'\n" unless $type =~ /\A(?:srpm|publisher|owner)\z/;
        if ($type eq 'owner') {
            die "Unsupported native build owner '$name'\n" unless grep { $_ eq $name }
                qw(goconserver grub2-xcat ipmitool-xcat syslinux-xcat xnba-undi xCAT-genesis-base
                   perl-Crypt-Rijndael perl-Crypt-SSLeay perl-HTTP-Async perl-IO-Stty perl-Net-HTTPS-NB perl-Net-Telnet);
        }
        if ($type ne 'publisher') {
            my $uid = $type eq 'owner' && ($name eq 'xnba-undi' || $name eq 'xCAT-genesis-base') ? 0 : 1000;
            die "Invalid native build UID for $name\n" unless ($node->{build_uid} // -1) == $uid;
        }
        if ($type ne 'owner') {
            die "Invalid pinned native URL for $name\n" unless ($node->{url} // '') =~
                m{\Ahttps://repo\.openeuler\.org/openEuler-24\.03-LTS(?:-SP3)?/[A-Za-z0-9_./+-]+\.rpm\z};
            die "Invalid native SHA256 for $name\n" unless ($node->{sha256} // '') =~ /\A[0-9a-f]{64}\z/;
            die "Publisher binary must be exact GA: $name\n" if $type eq 'publisher'
                && $node->{url} !~ m{/openEuler-24\.03-LTS/.*\.noarch\.rpm\z};
        }
        die "Missing output ownership for $name\n" unless ref($node->{outputs}) eq 'ARRAY' && @{$node->{outputs}};
        for my $output (@{$node->{outputs}}) {
            die "Invalid native output name\n" unless $output =~ /\A[\w+.-]+\z/;
            die "Conflicting output ownership: $output\n" if $outputs{$output};
            $outputs{$output} = $name;
        }
        die "Invalid publisher outputs for $name\n" if $type eq 'publisher'
            && (@{$node->{outputs}} != 1 || $node->{outputs}[0] ne $name);
        for my $patch (@{$node->{patches} // []}) {
            die "Only source inputs accept patches\n" unless $type eq 'srpm';
            $patch->{absolute_path} = pinned_file($root, $patch);
        }
        for my $define (@{$node->{defines} // []}) {
            die "Invalid native spec definition for $name\n" unless $type eq 'srpm'
                && $define =~ /\A(?:llvmjit|external_libpq|runselftest|test) [01]\z/;
        }
        $nodes{$name} = $node;
    }
    for my $name (sort keys %nodes) {
        my $type = $nodes{$name}{type};
        for my $dependency (@{$nodes{$name}{needs} // []}) {
            die "Missing native dependency '$dependency'\n" unless $nodes{$dependency};
            die "Unsupported native execution edge: $name -> $dependency\n"
                if $type eq 'publisher' || $nodes{$dependency}{type} eq 'owner';
        }
    }
    my (%mark, @order);
    my $visit;
    $visit = sub {
        my ($name) = @_;
        die "Missing native dependency '$name'\n" unless $nodes{$name};
        die "Cyclic native dependency at '$name'\n" if ($mark{$name} // '') eq 'visiting';
        return if $mark{$name};
        $mark{$name} = 'visiting';
        $visit->($_) for @{$nodes{$name}{needs} // []};
        $mark{$name} = 'done';
        push @order, $name;
    };
    $visit->($_) for sort keys %nodes;
    my %selected;
    my $select;
    $select = sub {
        my ($name) = @_;
        die "Missing native dependency '$name'\n" unless $nodes{$name};
        return if $selected{$name}++;
        $select->($_) for @{$nodes{$name}{needs} // []};
    };
    for my $output (sort keys %$required) {
        my $owner = $outputs{$output} // ($nodes{$output} ? $output : undef);
        die "No native output owner for '$output'\n" unless $owner;
        $select->($owner);
    }
    $select->($_) for @{$catalog->{build_inputs} // []};
    return {catalog => $catalog, nodes => \%nodes, outputs => \%outputs,
        order => [grep { $selected{$_} } @order], selected => \%selected,
        publisher_key => $key_path, publisher_fingerprint => $key->{fingerprint},
        catalog_sha256 => sha256($catalog_path)};
}

sub rpm_identity {
    my ($path) = @_;
    my @fields = split /\n/, capture('rpm', '-qp', '--qf',
        '%{NAME}\n%{ARCH}\n%{SOURCEPACKAGE}\n%{RELEASE}\n', $path);
    die "Invalid RPM header: $path\n" unless @fields == 4;
    return {name => $fields[0], arch => $fields[1], source => $fields[2] eq '1', release => $fields[3]};
}

sub read_exact {
    my ($fh, $size) = @_;
    my $data = '';
    while (length($data) < $size) {
        my $got = read($fh, $data, $size - length($data), length($data));
        die "Truncated RPM payload\n" unless defined($got) && $got > 0;
    }
    return $data;
}

sub reject_elf_payload {
    my ($path) = @_;
    open my $fh, '-|', 'rpm2cpio', $path or die "Cannot read RPM payload: $!\n";
    binmode $fh;
    my $error;
    eval {
        while (1) {
            my $header = read_exact($fh, 110);
            die "Invalid RPM cpio header\n" unless $header =~ /\A07070[12][0-9A-Fa-f]{104}\z/;
            my @fields = map { hex($_) } $header =~ /\A.{6}(.{8})(.{8})(.{8})(.{8})(.{8})(.{8})(.{8})(.{8})(.{8})(.{8})(.{8})(.{8})(.{8})\z/s;
            my ($size, $namesize) = @fields[6, 11];
            die "Invalid RPM cpio filename\n" unless $namesize > 0 && $namesize <= 1048576;
            my $name = read_exact($fh, $namesize);
            die "Invalid RPM cpio filename terminator\n" unless $name =~ s/\0\z//;
            read_exact($fh, (4 - (110 + $namesize) % 4) % 4);
            last if $name eq 'TRAILER!!!' && $size == 0;
            my $prefix = read_exact($fh, $size < 4 ? $size : 4);
            die "ELF payload in publisher noarch RPM: $name\n" if $prefix eq "\x7fELF";
            $size -= length($prefix);
            while ($size) { my $count = $size < 65536 ? $size : 65536; read_exact($fh, $count); $size -= $count; }
            read_exact($fh, (4 - $fields[6] % 4) % 4);
        }
        my $tail;
        while (read($fh, $tail, 65536)) { die "Unexpected data after RPM cpio trailer\n" if $tail =~ /[^\0]/; }
        1;
    } or $error = $@;
    my $closed = close($fh);
    die $error if $error;
    die "rpm2cpio failed: $path\n" unless $closed;
}

sub verify_input {
    my ($plan, $node, $path, $db) = @_;
    die "Native input SHA256 mismatch: $path\n" unless sha256($path) eq $node->{sha256};
    my $out = capture('rpmkeys', '--dbpath', $db, '--checksig', '--verbose', $path);
    die "Publisher signature missing or invalid: $path\n" unless $out =~ /Signature.*: OK/i
        && $out !~ /NOKEY|NOT OK|BAD|UNSIGNED/i;
    my $id = rpm_identity($path);
    die "Native input NAME mismatch: $path\n" unless $id->{name} eq $node->{name};
    if ($node->{type} eq 'publisher') {
        die "Publisher input is not a noarch binary: $path\n" if $id->{source} || $id->{arch} ne 'noarch';
        die "Publisher input is not exact GA: $path\n" unless $id->{release} =~ /\.oe2403\z/;
        reject_elf_payload($path);
    } else {
        die "Native input is not a source RPM: $path\n" unless $id->{source};
    }
    die "Native input changed during verification: $path\n" unless sha256($path) eq $node->{sha256};
    return $id;
}

sub publisher_trust {
    my ($plan, $work) = @_;
    make_path("$work/trust", "$work/gnupg");
    chmod 0700, "$work/gnupg";
    my $listing = capture('gpg', '--homedir', "$work/gnupg", '--batch', '--with-colons', '--show-keys', $plan->{publisher_key});
    my @primary;
    my $pub;
    for my $line (split /\n/, $listing) {
        my @fields = split /:/, $line;
        $pub = 1 if $fields[0] eq 'pub';
        if ($pub && $fields[0] eq 'fpr') { push @primary, $fields[9]; $pub = 0; }
    }
    die "Publisher public key fingerprint mismatch\n" unless @primary == 1 && $primary[0] eq $plan->{publisher_fingerprint};
    run('rpmkeys', '--dbpath', "$work/trust", '--import', $plan->{publisher_key});
    return "$work/trust";
}

sub stage_inputs {
    my ($plan, $work) = @_;
    die "Native input staging already exists: $work\n" if -e $work;
    make_path($work);
    my $db = publisher_trust($plan, $work);
    my @ledger;
    for my $name (@{$plan->{order}}) {
        my $node = $plan->{nodes}{$name};
        next if $node->{type} eq 'owner';
        make_path("$work/$name");
        for my $patch (@{$node->{patches} // []}) {
            make_path("$work/$name/patches");
            my $staged = "$work/$name/patches/" . basename($patch->{path});
            die "Conflicting staged patch: $staged\n" if -e $staged;
            copy($patch->{absolute_path}, $staged) or die "Cannot stage native patch: $!\n";
            die "Staged patch SHA256 mismatch: $staged\n" unless sha256($staged) eq $patch->{sha256};
            chmod 0444, $staged or die "Cannot protect native patch: $!\n";
            $patch->{staged} = $staged;
        }
        my $dest = "$work/$name/" . basename($node->{url});
        run('wget', '--https-only', '--tries=3', '--timeout=60', '-O', "$dest.part", $node->{url});
        verify_input($plan, $node, "$dest.part", $db);
        rename("$dest.part", $dest) or die "Cannot preserve native input: $!\n";
        chmod 0444, $dest or die "Cannot protect native input: $!\n";
        $node->{staged} = $dest;
        push @ledger, {name => $name, type => $node->{type}, url => $node->{url},
            sha256 => $node->{sha256}, path => $dest, publisher => $plan->{publisher_fingerprint},
            defines => $node->{defines} // [],
            patches => [map { {path => $_->{path}, sha256 => $_->{sha256}, staged => $_->{staged}} } @{$node->{patches} // []}]};
    }
    open my $fh, '>', "$work/inputs.json" or die "Cannot record native input ledger: $!\n";
    print {$fh} JSON::PP->new->canonical->pretty->encode({catalog_sha256 => $plan->{catalog_sha256}, inputs => \@ledger});
    close $fh or die "Cannot close native input ledger: $!\n";
    $plan->{trust_db} = $db;
}

sub validate_outputs {
    my ($node, $paths, $require_all) = @_;
    my %allowed = map { $_ => 1 } @{$node->{outputs}};
    my %seen;
    for my $path (@$paths) {
        my $id = rpm_identity($path);
        next if $id->{source};
        die "Unexpected output from $node->{name}: $id->{name}\n" unless $allowed{$id->{name}};
        die "Duplicate output from $node->{name}: $id->{name}\n" if $seen{$id->{name}}++;
        die "Foreign output architecture: $id->{arch}\n" unless $id->{arch} eq 'ppc64le' || $id->{arch} eq 'noarch';
    }
    if ($require_all) {
        die "Missing output from $node->{name}: $_\n" for grep { !$seen{$_} } sort keys %allowed;
    }
    return \%seen;
}

1;
