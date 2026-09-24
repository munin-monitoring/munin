#!/usr/bin/perl

use strict;
use warnings;
use File::Spec;
use File::Temp qw(tempdir);
use File::Basename qw(dirname);
use FindBin;
use Test::More;
use RRDs;
use File::Path qw(make_path remove_tree);

my $script = "$FindBin::Bin/../script/munin-migrate-rrd";
plan skip_all => "Script not found: $script" unless -f $script;

my $tmpdir = tempdir(CLEANUP => 1);
my $dbdir = "$tmpdir/rrd";
make_path($dbdir, { mode => 0755 });

sub create_rrd {
    my ($file, $ds_name, $type, $data) = @_;
    make_path(dirname($file), { mode => 0755 }) unless -d dirname($file);

    my $start = time() - 86400;
    RRDs::create($file,
        '--start', $start - 300, '-s', 300,
        "DS:$ds_name:$type:600:0:U",
        'RRA:AVERAGE:0.5:1:576',
        'RRA:MIN:0.5:1:576',
        'RRA:MAX:0.5:1:576',
    );
    die "RRDs::create: " . RRDs::error if RRDs::error;

    if ($data && @$data) {
        my $when = $start;
        for my $val (@$data) {
            RRDs::update($file, "$when:$val");
            die "RRDs::update: " . RRDs::error if RRDs::error;
            $when += 300;
        }
    }
}

sub get_rrd_data {
    my ($file, $ds) = @_;
    my ($s, $e, $step, $nb, $cols, $vals) = RRDs::xport(
        '--start', 'now-86400', '--end', 'now',
        "DEF:v=$file:$ds:AVERAGE", "XPORT:v",
    );
    return [] if RRDs::error;
    return [grep { defined $_ && $_ ne 'nan' } map { $_->[0] } @$vals];
}

sub ds_names {
    my ($file) = @_;
    my $info = RRDs::info($file);
    return () if RRDs::error;
    return sort map { /^ds\[([^\]]+)\]\.type$/ ? $1 : () } keys %$info;
}

sub ds_type {
    my ($file, $ds) = @_;
    my $info = RRDs::info($file);
    return $info->{"ds[$ds].type"} // undef;
}

sub run {
    my (@args) = @_;
    my $cmd = "perl $script --dbdir=$dbdir @args 2>&1";
    my $out = `$cmd`;
    return ($? >> 8, $out);
}

# Test 1: Basic copy (single-DS to multi-DS)
subtest 'basic_copy' => sub {
    my $f1 = "$dbdir/t1/idle.rrd";
    my $f2 = "$dbdir/t1/user.rrd";
    my $f3 = "$dbdir/t1/cpu.rrd";

    create_rrd($f1, '42', 'GAUGE', [50, 60, 70]);
    create_rrd($f2, '42', 'GAUGE', [10, 20, 30]);

    my ($rc, $out) = run(
        '-i', "$f1:42", '-o', "$f3:idle-g",
        '-i', "$f2:42", '-o', "$f3:user-g",
    );

    is($rc, 0, "copy succeeded");
    ok(-f $f3, "output created");
    ok(!-f $f1, "input1 removed");
    ok(!-f $f2, "input2 removed");

    my @ds = ds_names($f3);
    is(scalar @ds, 2, "output has 2 DS");
    is_deeply(\@ds, ['idle-g', 'user-g'], "DS names correct");

    my $d1 = get_rrd_data($f3, 'idle-g');
    my $d2 = get_rrd_data($f3, 'user-g');
    ok(scalar @$d1 > 0, "idle-g has data");
    ok(scalar @$d2 > 0, "user-g has data");
};

# Test 2: Comma syntax
subtest 'comma_syntax' => sub {
    my $f1 = "$dbdir/t2/a.rrd";
    my $f2 = "$dbdir/t2/b.rrd";
    my $f3 = "$dbdir/t2/merged.rrd";

    create_rrd($f1, '42', 'GAUGE', [100]);
    create_rrd($f2, '42', 'GAUGE', [200]);

    my ($rc, $out) = run(
        '-i', "$f1:42,$f2:42",
        '-o', "$f3:a-g,b-g",
    );

    is($rc, 0, "comma syntax works");
    my @ds = ds_names($f3);
    is(scalar @ds, 2, "has 2 DS");
};

# Test 3: Fail if output exists without --append
subtest 'no_overwrite' => sub {
    my $f1 = "$dbdir/t3/src.rrd";
    my $f2 = "$dbdir/t3/dst.rrd";

    create_rrd($f1, '42', 'GAUGE', [10]);
    create_rrd($f2, '42', 'GAUGE', [20]);

    my ($rc, $out) = run(
        '-i', "$f1:42", '-o', "$f2:new-g",
    );

    isnt($rc, 0, "fails without --append");
    like($out, qr/Output exists/, "error about existing file");
};

# Test 4: --append adds DS to existing file
subtest 'append' => sub {
    my $f1 = "$dbdir/t4/new.rrd";
    my $f2 = "$dbdir/t4/existing.rrd";

    create_rrd($f1, '42', 'GAUGE', [100, 200, 300]);
    create_rrd($f2, '42', 'GAUGE', [10, 20, 30]);

    my ($rc, $out) = run('--append',
        '-i', "$f1:42", '-o', "$f2:new-g",
    );

    is($rc, 0, "append succeeded");
    ok(-f "$f2.bak", "backup created");

    my @ds = ds_names($f2);
    is(scalar @ds, 2, "has 2 DS after append");
    is(ds_type($f2, '42'), 'GAUGE', "original DS preserved");
    is(ds_type($f2, 'new-g'), 'GAUGE', "new DS added");

    my $d1 = get_rrd_data($f2, '42');
    my $d2 = get_rrd_data($f2, 'new-g');
    ok(scalar @$d1 > 0, "original data preserved");
    ok(scalar @$d2 > 0, "new data added");
};

# Test 5: Fail on RRA mismatch
subtest 'rra_mismatch' => sub {
    my $f1 = "$dbdir/t5/a.rrd";
    my $f2 = "$dbdir/t5/b.rrd";
    my $f3 = "$dbdir/t5/out.rrd";

    # Create with different RRAs
    my $start = time() - 86400;
    make_path("$dbdir/t5", { mode => 0755 });

    RRDs::create($f1,
        '--start', $start - 300, '-s', 300,
        "DS:42:GAUGE:600:0:U",
        'RRA:AVERAGE:0.5:1:576',
    );
    RRDs::update($f1, "$start:50");

    RRDs::create($f2,
        '--start', $start - 300, '-s', 300,
        "DS:42:GAUGE:600:0:U",
        'RRA:AVERAGE:0.5:6:432',  # Different RRA
    );
    RRDs::update($f2, "$start:60");

    my ($rc, $out) = run(
        '-i', "$f1:42", '-o', "$f3:a-g",
        '-i', "$f2:42", '-o', "$f3:b-g",
    );

    isnt($rc, 0, "fails on RRA mismatch");
    like($out, qr/RRA mismatch/, "error about RRA");
};

# Test 6: Fail on DS name collision in --append
subtest 'ds_collision' => sub {
    my $f1 = "$dbdir/t6/src.rrd";
    my $f2 = "$dbdir/t6/dst.rrd";

    create_rrd($f1, '42', 'GAUGE', [100]);
    create_rrd($f2, 'myfield', 'GAUGE', [200]);

    my ($rc, $out) = run('--append',
        '-i', "$f1:42", '-o', "$f2:myfield",
    );

    isnt($rc, 0, "fails on DS collision");
    like($out, qr/already exists/, "error about collision");
};

# Test 7: Mismatched input/output count
subtest 'mismatched_count' => sub {
    my $f = "$dbdir/t7/a.rrd";
    create_rrd($f, '42', 'GAUGE', [10]);

    my ($rc, $out) = run(
        '-i', "$f:42",
        '-o', "$f:x", '-o', "$f:y",
    );

    isnt($rc, 0, "fails on count mismatch");
    like($out, qr/must equal/, "error about count");
};

# Test 8: No args
subtest 'no_args' => sub {
    my ($rc, $out) = run();
    isnt($rc, 0, "fails without args");
};

# Test 9: DS type preserved
subtest 'type_preserved' => sub {
    my $f1 = "$dbdir/t9/gauge.rrd";
    my $f2 = "$dbdir/t9/derive.rrd";
    my $f3 = "$dbdir/t9/merged.rrd";

    create_rrd($f1, '42', 'GAUGE', [50]);
    create_rrd($f2, '42', 'DERIVE', [100]);

    my ($rc) = run(
        '-i', "$f1:42", '-o', "$f3:g-g",
        '-i', "$f2:42", '-o', "$f3:d-d",
    );

    is($rc, 0, "copy succeeded");
    is(ds_type($f3, 'g-g'), 'GAUGE', "GAUGE preserved");
    is(ds_type($f3, 'd-d'), 'DERIVE', "DERIVE preserved");
};

# Test 10: Split multi-DS to single-DS
subtest 'split' => sub {
    my $src = "$dbdir/t10/multi.rrd";
    my $f1 = "$dbdir/t10/a.rrd";
    my $f2 = "$dbdir/t10/b.rrd";

    my $start = time() - 86400;
    make_path("$dbdir/t10", { mode => 0755 });

    RRDs::create($src,
        '--start', $start - 300, '-s', 300,
        "DS:x:GAUGE:600:0:U",
        "DS:y:GAUGE:600:0:U",
        'RRA:AVERAGE:0.5:1:576',
    );
    RRDs::update($src, "$start:10,20");

    my ($rc) = run(
        '-i', "$src:x", '-o', "$f1:42",
        '-i', "$src:y", '-o', "$f2:42",
    );

    is($rc, 0, "split succeeded");
    ok(-f $f1, "output1 created");
    ok(-f $f2, "output2 created");
    ok(!-f $src, "source removed");
    is(scalar @{ds_names($f1)}, 1, "output1 has 1 DS");
    is(scalar @{ds_names($f2)}, 1, "output2 has 1 DS");
};

# Test 11: Dry run
subtest 'dry_run' => sub {
    my $f1 = "$dbdir/t11/src.rrd";
    my $f2 = "$dbdir/t11/dst.rrd";

    create_rrd($f1, '42', 'GAUGE', [50]);

    my ($rc, $out) = run('--dry-run',
        '-i', "$f1:42", '-o', "$f2:my-g",
    );

    is($rc, 0, "dry run succeeds");
    ok(!-f $f2, "output not created");
    like($out, qr/Dry run/, "shows dry run message");
};

# Test 12: Help
subtest 'help' => sub {
    my ($rc, $out) = run('--help');
    like($out, qr/munin-migrate-rrd/, "help shows script name");
    like($out, qr/--append/, "help shows --append");
};

# Test 13: --append preserves original data
subtest 'append_data_preserved' => sub {
    my $new = "$dbdir/t13/new.rrd";
    my $old = "$dbdir/t13/old.rrd";

    create_rrd($new, '42', 'GAUGE', [100, 200, 300]);
    create_rrd($old, 'myfield', 'GAUGE', [10, 20, 30]);

    my $before = get_rrd_data($old, 'myfield');
    my $count_before = scalar @$before;

    run('--append', '-i', "$new:42", '-o', "$old:extra-g");

    my $after_old = get_rrd_data($old, 'myfield');
    my $after_new = get_rrd_data($old, 'extra-g');

    ok(scalar @$after_old >= $count_before * 0.8, "original data roughly preserved");
    ok(scalar @$after_new > 0, "new data added");
};

END {
    remove_tree($tmpdir) if $tmpdir && -d $tmpdir;
}

done_testing();
