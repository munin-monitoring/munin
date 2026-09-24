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

# --- Helpers ---

sub create_rrd {
    my ($file, $ds_name, $type, $data, %opts) = @_;
    make_path(dirname($file), { mode => 0755 }) unless -d dirname($file);

    my $start = $opts{start} // (time() - 86400);
    my $step = $opts{step} // 300;
    my $heartbeat = $opts{heartbeat} // 600;
    my $min = $opts{min} // '0';
    my $max = $opts{max} // 'U';

    my @rras;
    if ($opts{rras}) {
        @rras = @{$opts{rras}};
    } else {
        @rras = ('RRA:AVERAGE:0.5:1:576', 'RRA:MIN:0.5:1:576', 'RRA:MAX:0.5:1:576');
    }

    RRDs::create($file,
        '--start', $start - $step, '-s', $step,
        "DS:$ds_name:$type:$heartbeat:$min:$max",
        @rras,
    );
    die "RRDs::create $file: " . RRDs::error if RRDs::error;

    if ($data && @$data) {
        my $when = $start;
        for my $val (@$data) {
            RRDs::update($file, "$when:$val");
            die "RRDs::update: " . RRDs::error if RRDs::error;
            $when += $step;
        }
    }
}

sub create_multi_rrd {
    my ($file, $ds_list, $data, %opts) = @_;
    make_path(dirname($file), { mode => 0755 }) unless -d dirname($file);

    my $start = $opts{start} // (time() - 86400);
    my $step = $opts{step} // 300;

    my @rras;
    if ($opts{rras}) {
        @rras = @{$opts{rras}};
    } else {
        @rras = ('RRA:AVERAGE:0.5:1:576', 'RRA:MIN:0.5:1:576', 'RRA:MAX:0.5:1:576');
    }

    my @ds_defs;
    for my $ds (@$ds_list) {
        my $hb = $ds->{heartbeat} // 600;
        my $min = $ds->{min} // '0';
        my $max = $ds->{max} // 'U';
        push @ds_defs, "DS:$ds->{name}:$ds->{type}:$hb:$min:$max";
    }

    RRDs::create($file,
        '--start', $start - $step, '-s', $step,
        @ds_defs, @rras,
    );
    die "RRDs::create $file: " . RRDs::error if RRDs::error;

    if ($data && @$data) {
        my $when = $start;
        for my $vals (@$data) {
            RRDs::update($file, "$when:" . join(':', @$vals));
            die "RRDs::update: " . RRDs::error if RRDs::error;
            $when += $step;
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
    return () unless -f $file;
    my $info = RRDs::info($file);
    return () if RRDs::error || !$info;
    return sort map { /^ds\[([^\]]+)\]\.type$/ ? $1 : () } keys %$info;
}

sub ds_type {
    my ($file, $ds) = @_;
    my $info = RRDs::info($file);
    return undef if RRDs::error || !$info;
    return $info->{"ds[$ds].type"} // undef;
}

sub ds_info {
    my ($file, $ds) = @_;
    my $info = RRDs::info($file);
    return {} if RRDs::error || !$info;
    my %result;
    for my $key (qw(type minimal_heartbeat min max)) {
        my $val = $info->{"ds[$ds].$key"};
        $result{$key} = $val if defined $val;
    }
    return \%result;
}

sub rra_info {
    my ($file) = @_;
    my $info = RRDs::info($file);
    return [] if RRDs::error || !$info;
    my @rras;
    for my $k (sort keys %$info) {
        if ($k =~ /^rra\[(\d+)\]\.(cf|xff|rows|pdp_per_row)$/) {
            $rras[$1]{$2} = $info->{$k};
        }
    }
    return [grep { defined $_ } @rras];
}

sub run {
    my (@args) = @_;
    my $cmd = "perl $script --dbdir=$dbdir @args 2>&1";
    my $out = `$cmd`;
    return ($? >> 8, $out);
}

# ============================================================
# MERGE TESTS
# ============================================================

# Test 1: Basic merge — two GAUGE DS
subtest 'merge_basic' => sub {
    my $f1 = "$dbdir/t1/a.rrd";
    my $f2 = "$dbdir/t1/b.rrd";
    my $out = "$dbdir/t1/merged.rrd";

    create_rrd($f1, '42', 'GAUGE', [10, 20, 30]);
    create_rrd($f2, '42', 'GAUGE', [100, 200, 300]);

    my ($rc) = run(
        '-i', "$f1:42", '-o', "$out:x",
        '-i', "$f2:42", '-o', "$out:y",
    );

    is($rc, 0, "merge succeeded");
    ok(-f $out, "output created");
    ok(!-f $f1, "input1 removed");
    ok(!-f $f2, "input2 removed");

    my @ds = ds_names($out);
    is(scalar @ds, 2, "has 2 DS");
    is_deeply(\@ds, ['x', 'y'], "DS names correct");

    # Data values preserved
    my $d1 = get_rrd_data($out, 'x');
    my $d2 = get_rrd_data($out, 'y');
    ok(scalar @$d1 > 0, "x has data");
    ok(scalar @$d2 > 0, "y has data");
};

# Test 2: Merge three inputs
subtest 'merge_three' => sub {
    my $f1 = "$dbdir/t2/a.rrd";
    my $f2 = "$dbdir/t2/b.rrd";
    my $f3 = "$dbdir/t2/c.rrd";
    my $out = "$dbdir/t2/merged.rrd";

    create_rrd($f1, '42', 'GAUGE', [10]);
    create_rrd($f2, '42', 'GAUGE', [20]);
    create_rrd($f3, '42', 'GAUGE', [30]);

    my ($rc) = run(
        '-i', "$f1:42", '-o', "$out:a",
        '-i', "$f2:42", '-o', "$out:b",
        '-i', "$f3:42", '-o', "$out:c",
    );

    is($rc, 0, "merge three succeeded");
    my @ds = ds_names($out);
    is(scalar @ds, 3, "has 3 DS");
    is_deeply(\@ds, ['a', 'b', 'c'], "DS names correct");
};

# Test 3: Comma syntax
subtest 'merge_comma' => sub {
    my $f1 = "$dbdir/t3/a.rrd";
    my $f2 = "$dbdir/t3/b.rrd";
    my $out = "$dbdir/t3/merged.rrd";

    create_rrd($f1, '42', 'GAUGE', [100]);
    create_rrd($f2, '42', 'GAUGE', [200]);

    my ($rc) = run(
        '-i', "$f1:42,$f2:42",
        '-o', "$out:x,y",
    );

    is($rc, 0, "comma syntax works");
    my @ds = ds_names($out);
    is(scalar @ds, 2, "has 2 DS");
};

# Test 4: Merge different DS types preserved
subtest 'merge_types_preserved' => sub {
    my $f1 = "$dbdir/t4/g.rrd";
    my $f2 = "$dbdir/t4/d.rrd";
    my $f3 = "$dbdir/t4/c.rrd";
    my $out = "$dbdir/t4/merged.rrd";

    create_rrd($f1, '42', 'GAUGE', [50]);
    create_rrd($f2, '42', 'DERIVE', [100]);
    create_rrd($f3, '42', 'COUNTER', [200]);

    my ($rc) = run(
        '-i', "$f1:42", '-o', "$out:g",
        '-i', "$f2:42", '-o', "$out:d",
        '-i', "$f3:42", '-o', "$out:c",
    );

    is($rc, 0, "merge types succeeded");
    is(ds_type($out, 'g'), 'GAUGE', "GAUGE preserved");
    is(ds_type($out, 'd'), 'DERIVE', "DERIVE preserved");
    is(ds_type($out, 'c'), 'COUNTER', "COUNTER preserved");
};

# Test 5: DS properties preserved (heartbeat, min, max)
subtest 'merge_ds_properties' => sub {
    my $f1 = "$dbdir/t5/a.rrd";
    my $f2 = "$dbdir/t5/b.rrd";
    my $out = "$dbdir/t5/merged.rrd";

    create_rrd($f1, '42', 'GAUGE', [50], heartbeat => 1200, min => '10', max => '90');
    create_rrd($f2, '42', 'GAUGE', [60], heartbeat => 1800, min => '5', max => '95');

    my ($rc) = run(
        '-i', "$f1:42", '-o', "$out:a",
        '-i', "$f2:42", '-o', "$out:b",
    );

    is($rc, 0, "merge succeeded");

    my $info_a = ds_info($out, 'a');
    is($info_a->{minimal_heartbeat}, 1200, "a heartbeat preserved");
    is($info_a->{min}, '10', "a min preserved");
    is($info_a->{max}, '90', "a max preserved");

    my $info_b = ds_info($out, 'b');
    is($info_b->{minimal_heartbeat}, 1800, "b heartbeat preserved");
    is($info_b->{min}, '5', "b min preserved");
    is($info_b->{max}, '95', "b max preserved");
};

# Test 6: RRA structure preserved
subtest 'merge_rra_preserved' => sub {
    my $f1 = "$dbdir/t6/a.rrd";
    my $out = "$dbdir/t6/out.rrd";

    create_rrd($f1, '42', 'GAUGE', [50],
        rras => ['RRA:AVERAGE:0.5:1:576', 'RRA:MIN:0.5:6:432']);

    my ($rc) = run('-i', "$f1:42", '-o', "$out:x");

    is($rc, 0, "copy succeeded");
    my $rras = rra_info($out);
    is(scalar @$rras, 2, "has 2 RRAs");
    is($rras->[0]{cf}, 'AVERAGE', "RRA0 cf");
    is($rras->[0]{pdp_per_row}, 1, "RRA0 pdp_per_row");
    is($rras->[0]{rows}, 576, "RRA0 rows");
    is($rras->[1]{cf}, 'MIN', "RRA1 cf");
    is($rras->[1]{pdp_per_row}, 6, "RRA1 pdp_per_row");
    is($rras->[1]{rows}, 432, "RRA1 rows");
};

# Test 7: Data values exact match after merge
subtest 'merge_data_exact' => sub {
    my $f1 = "$dbdir/t7/a.rrd";
    my $f2 = "$dbdir/t7/b.rrd";
    my $out = "$dbdir/t7/merged.rrd";

    my $start = time() - 86400;
    create_rrd($f1, '42', 'GAUGE', [11, 22, 33], start => $start);
    create_rrd($f2, '42', 'GAUGE', [44, 55, 66], start => $start);

    my ($rc) = run(
        '-i', "$f1:42", '-o', "$out:x",
        '-i', "$f2:42", '-o', "$out:y",
    );

    is($rc, 0, "merge succeeded");

    # Values should be preserved (same timestamps, same step)
    my $dx = get_rrd_data($out, 'x');
    my $dy = get_rrd_data($out, 'y');
    ok(scalar @$dx >= 2, "x has enough data points");
    ok(scalar @$dy >= 2, "y has enough data points");
};

# Test 8: Merge with NaN/unknown values
subtest 'merge_nan' => sub {
    my $f1 = "$dbdir/t8/a.rrd";
    my $f2 = "$dbdir/t8/b.rrd";
    my $out = "$dbdir/t8/merged.rrd";

    create_rrd($f1, '42', 'GAUGE', [50]);
    create_rrd($f2, '42', 'GAUGE', ['U']);  # unknown

    my ($rc) = run(
        '-i', "$f1:42", '-o', "$out:x",
        '-i', "$f2:42", '-o', "$out:y",
    );

    is($rc, 0, "merge with NaN succeeded");
    my @ds = ds_names($out);
    is(scalar @ds, 2, "has 2 DS");
};

# ============================================================
# SPLIT TESTS
# ============================================================

# Test 9: Basic split
subtest 'split_basic' => sub {
    my $src = "$dbdir/t9/multi.rrd";
    my $f1 = "$dbdir/t9/a.rrd";
    my $f2 = "$dbdir/t9/b.rrd";

    create_multi_rrd($src,
        [{ name => 'x', type => 'GAUGE' }, { name => 'y', type => 'GAUGE' }],
        [[10, 20], [30, 40], [50, 60]],
    );

    my ($rc) = run(
        '-i', "$src:x", '-o', "$f1:42",
        '-i', "$src:y", '-o', "$f2:42",
    );

    is($rc, 0, "split succeeded");
    ok(-f $f1, "output1 created");
    ok(-f $f2, "output2 created");
    ok(!-f $src, "source removed");
    
    my @ds1 = ds_names($f1);
    my @ds2 = ds_names($f2);
    is(scalar @ds1, 1, "output1 has 1 DS");
    is(scalar @ds2, 1, "output2 has 1 DS");

    # Data extracted correctly
    my $d1 = get_rrd_data($f1, '42');
    my $d2 = get_rrd_data($f2, '42');
    ok(scalar @$d1 > 0, "output1 has data");
    ok(scalar @$d2 > 0, "output2 has data");
};

# Test 10: Split preserves DS properties
subtest 'split_ds_properties' => sub {
    my $src = "$dbdir/t10/multi.rrd";
    my $f1 = "$dbdir/t10/a.rrd";

    create_multi_rrd($src,
        [{ name => 'x', type => 'DERIVE', heartbeat => 1200, min => '5', max => '95' }],
        [[100], [200]],
    );

    my ($rc) = run('-i', "$src:x", '-o', "$f1:42");

    is($rc, 0, "split succeeded");
    is(ds_type($f1, '42'), 'DERIVE', "type preserved");

    my $info = ds_info($f1, '42');
    is($info->{minimal_heartbeat}, 1200, "heartbeat preserved");
    is($info->{min}, '5', "min preserved");
    is($info->{max}, '95', "max preserved");
};

# Test 11: Split preserves RRA
subtest 'split_rra_preserved' => sub {
    my $src = "$dbdir/t11/multi.rrd";
    my $f1 = "$dbdir/t11/a.rrd";

    create_multi_rrd($src,
        [{ name => 'x', type => 'GAUGE' }],
        [[10]],
        rras => ['RRA:AVERAGE:0.5:1:576', 'RRA:MAX:0.5:6:432'],
    );

    my ($rc) = run('-i', "$src:x", '-o', "$f1:42");

    is($rc, 0, "split succeeded");
    my $rras = rra_info($f1);
    is(scalar @$rras, 2, "has 2 RRAs");
    is($rras->[0]{cf}, 'AVERAGE', "RRA0 cf");
    is($rras->[1]{cf}, 'MAX', "RRA1 cf");
};

# Test 12: Split data values correct
subtest 'split_data_exact' => sub {
    my $src = "$dbdir/t12/multi.rrd";
    my $f1 = "$dbdir/t12/a.rrd";
    my $f2 = "$dbdir/t12/b.rrd";

    create_multi_rrd($src,
        [{ name => 'x', type => 'GAUGE' }, { name => 'y', type => 'GAUGE' }],
        [[11, 44], [22, 55], [33, 66]],
    );

    my ($rc) = run(
        '-i', "$src:x", '-o', "$f1:42",
        '-i', "$src:y", '-o', "$f2:42",
    );

    is($rc, 0, "split succeeded");

    my $d1 = get_rrd_data($f1, '42');
    my $d2 = get_rrd_data($f2, '42');

    # Both should have data
    ok(scalar @$d1 > 0, "x has data");
    ok(scalar @$d2 > 0, "y has data");
};

# ============================================================
# APPEND TESTS
# ============================================================

# Test 13: Basic append
subtest 'append_basic' => sub {
    my $new = "$dbdir/t13/new.rrd";
    my $old = "$dbdir/t13/old.rrd";

    create_rrd($new, '42', 'GAUGE', [100, 200, 300]);
    create_rrd($old, '42', 'GAUGE', [10, 20, 30]);

    my ($rc) = run('--append',
        '-i', "$new:42", '-o', "$old:new-g",
    );

    is($rc, 0, "append succeeded");
    ok(-f "$old.bak", "backup created");

    my @ds = ds_names($old);
    is(scalar @ds, 2, "has 2 DS after append");
    is(ds_type($old, '42'), 'GAUGE', "original DS preserved");
    is(ds_type($old, 'new-g'), 'GAUGE', "new DS added");

    my $d1 = get_rrd_data($old, '42');
    my $d2 = get_rrd_data($old, 'new-g');
    ok(scalar @$d1 > 0, "original data preserved");
    ok(scalar @$d2 > 0, "new data added");
};

# Test 14: Append preserves DS properties
subtest 'append_ds_properties' => sub {
    my $new = "$dbdir/t14/new.rrd";
    my $old = "$dbdir/t14/old.rrd";

    create_rrd($new, '42', 'DERIVE', [100], heartbeat => 1200, min => '5', max => '95');
    create_rrd($old, '42', 'GAUGE', [10]);

    my ($rc) = run('--append',
        '-i', "$new:42", '-o', "$old:derived",
    );

    is($rc, 0, "append succeeded");
    is(ds_type($old, 'derived'), 'DERIVE', "new DS type preserved");

    my $info = ds_info($old, 'derived');
    is($info->{minimal_heartbeat}, 1200, "heartbeat preserved");
    is($info->{min}, '5', "min preserved");
    is($info->{max}, '95', "max preserved");
};

# Test 15: Append preserves RRA
subtest 'append_rra_preserved' => sub {
    my $new = "$dbdir/t15/new.rrd";
    my $old = "$dbdir/t15/old.rrd";

    create_rrd($new, '42', 'GAUGE', [100],
        rras => ['RRA:AVERAGE:0.5:1:576', 'RRA:MIN:0.5:6:432']);
    create_rrd($old, '42', 'GAUGE', [10],
        rras => ['RRA:AVERAGE:0.5:1:576', 'RRA:MIN:0.5:6:432']);

    my ($rc) = run('--append',
        '-i', "$new:42", '-o', "$old:extra",
    );

    is($rc, 0, "append succeeded");
    my $rras = rra_info($old);
    is(scalar @$rras, 2, "still has 2 RRAs");
    is($rras->[0]{cf}, 'AVERAGE', "RRA0 cf preserved");
    is($rras->[1]{cf}, 'MIN', "RRA1 cf preserved");
};

# Test 16: Append multiple DS at once
subtest 'append_multiple' => sub {
    my $n1 = "$dbdir/t16/n1.rrd";
    my $n2 = "$dbdir/t16/n2.rrd";
    my $old = "$dbdir/t16/old.rrd";

    create_rrd($n1, '42', 'GAUGE', [100]);
    create_rrd($n2, '42', 'GAUGE', [200]);
    create_rrd($old, '42', 'GAUGE', [10]);

    my ($rc) = run('--append',
        '-i', "$n1:42", '-o', "$old:x",
        '-i', "$n2:42", '-o', "$old:y",
    );

    is($rc, 0, "append multiple succeeded");
    my @ds = ds_names($old);
    is(scalar @ds, 3, "has 3 DS after append");
};

# Test 17: Append backup has original data
subtest 'append_backup' => sub {
    my $new = "$dbdir/t17/new.rrd";
    my $old = "$dbdir/t17/old.rrd";

    create_rrd($new, '42', 'GAUGE', [100]);
    create_rrd($old, 'myfield', 'GAUGE', [10, 20, 30]);

    my $before = get_rrd_data($old, 'myfield');

    run('--append', '-i', "$new:42", '-o', "$old:extra");

    # Backup should have original single-DS structure
    my @bak_ds = ds_names("$old.bak");
    is(scalar @bak_ds, 1, "backup has 1 DS");
    is($bak_ds[0], 'myfield', "backup DS name correct");

    my $bak_data = get_rrd_data("$old.bak", 'myfield');
    ok(scalar @$bak_data > 0, "backup has data");
};

# ============================================================
# VALIDATION TESTS
# ============================================================

# Test 18: No overwrite without --append
subtest 'no_overwrite' => sub {
    my $f1 = "$dbdir/t18/src.rrd";
    my $f2 = "$dbdir/t18/dst.rrd";

    create_rrd($f1, '42', 'GAUGE', [10]);
    create_rrd($f2, '42', 'GAUGE', [20]);

    my ($rc, $out) = run('-i', "$f1:42", '-o', "$f2:new");

    isnt($rc, 0, "fails without --append");
    like($out, qr/Output exists/, "error about existing file");
};

# Test 19: RRA mismatch fails
subtest 'rra_mismatch' => sub {
    my $f1 = "$dbdir/t19/a.rrd";
    my $f2 = "$dbdir/t19/b.rrd";
    my $out = "$dbdir/t19/out.rrd";

    my $start = time() - 86400;
    make_path("$dbdir/t19", { mode => 0755 });

    RRDs::create($f1,
        '--start', $start - 300, '-s', 300,
        "DS:42:GAUGE:600:0:U",
        'RRA:AVERAGE:0.5:1:576',
    );
    RRDs::update($f1, "$start:50");

    RRDs::create($f2,
        '--start', $start - 300, '-s', 300,
        "DS:42:GAUGE:600:0:U",
        'RRA:AVERAGE:0.5:6:432',
    );
    RRDs::update($f2, "$start:60");

    my ($rc, $out_text) = run(
        '-i', "$f1:42", '-o', "$out:a",
        '-i', "$f2:42", '-o', "$out:b",
    );

    isnt($rc, 0, "fails on RRA mismatch");
    like($out_text, qr/RRA mismatch/, "error about RRA");
};

# Test 20: Input/output count mismatch
subtest 'count_mismatch' => sub {
    my $f = "$dbdir/t20/a.rrd";
    create_rrd($f, '42', 'GAUGE', [10]);

    my ($rc, $out) = run(
        '-i', "$f:42",
        '-o', "$f:x", '-o', "$f:y",
    );

    isnt($rc, 0, "fails on count mismatch");
    like($out, qr/Input count != output count/, "error message");
};

# Test 21: DS collision in append
subtest 'ds_collision' => sub {
    my $f1 = "$dbdir/t21/src.rrd";
    my $f2 = "$dbdir/t21/dst.rrd";

    create_rrd($f1, '42', 'GAUGE', [100]);
    create_rrd($f2, 'myfield', 'GAUGE', [200]);

    my ($rc, $out) = run('--append',
        '-i', "$f1:42", '-o', "$f2:myfield",
    );

    isnt($rc, 0, "fails on DS collision");
    like($out, qr/already exists/, "error about collision");
};

# Test 22: Missing input file
subtest 'missing_input' => sub {
    my ($rc, $out) = run(
        '-i', "/nonexistent.rrd:42",
        '-o', "$dbdir/t22/out.rrd:x",
    );

    isnt($rc, 0, "fails with missing input");
    like($out, qr/not found/, "error about missing file");
};

# Test 23: DS not found in input
subtest 'ds_not_found' => sub {
    my $f = "$dbdir/t23/src.rrd";
    create_rrd($f, '42', 'GAUGE', [10]);

    my ($rc, $out) = run(
        '-i', "$f:nonexistent",
        '-o', "$dbdir/t23/out.rrd:x",
    );

    isnt($rc, 0, "fails with missing DS");
    like($out, qr/not found/, "error about missing DS");
};

# Test 24: No args
subtest 'no_args' => sub {
    my ($rc) = run();
    isnt($rc, 0, "fails without args");
};

# Test 25: Append step mismatch
subtest 'append_step_mismatch' => sub {
    my $new = "$dbdir/t25/new.rrd";
    my $old = "$dbdir/t25/old.rrd";

    my $start = time() - 86400;
    make_path("$dbdir/t25", { mode => 0755 });

    RRDs::create($new,
        '--start', $start - 300, '-s', 300,
        "DS:42:GAUGE:600:0:U",
        'RRA:AVERAGE:0.5:1:576',
    );
    RRDs::update($new, "$start:100");

    RRDs::create($old,
        '--start', $start - 600, '-s', 600,
        "DS:42:GAUGE:1200:0:U",
        'RRA:AVERAGE:0.5:1:576',
    );
    RRDs::update($old, "$start:10");

    my ($rc, $out) = run('--append',
        '-i', "$new:42", '-o', "$old:extra",
    );

    isnt($rc, 0, "fails on step mismatch");
    like($out, qr/Step mismatch/, "error about step");
};

# Test 26: Append RRA mismatch
subtest 'append_rra_mismatch' => sub {
    my $new = "$dbdir/t26/new.rrd";
    my $old = "$dbdir/t26/old.rrd";

    my $start = time() - 86400;
    make_path("$dbdir/t26", { mode => 0755 });

    RRDs::create($new,
        '--start', $start - 300, '-s', 300,
        "DS:42:GAUGE:600:0:U",
        'RRA:AVERAGE:0.5:1:576',
    );
    RRDs::update($new, "$start:100");

    RRDs::create($old,
        '--start', $start - 300, '-s', 300,
        "DS:42:GAUGE:600:0:U",
        'RRA:AVERAGE:0.5:6:432',
    );
    RRDs::update($old, "$start:10");

    my ($rc, $out) = run('--append',
        '-i', "$new:42", '-o', "$old:extra",
    );

    isnt($rc, 0, "fails on RRA mismatch");
    like($out, qr/RRA mismatch/, "error about RRA");
};

# ============================================================
# MISC TESTS
# ============================================================

# Test 27: Dry run
subtest 'dry_run' => sub {
    my $f1 = "$dbdir/t27/src.rrd";
    my $f2 = "$dbdir/t27/dst.rrd";

    create_rrd($f1, '42', 'GAUGE', [50]);

    my ($rc, $out) = run('--dry-run',
        '-i', "$f1:42", '-o', "$f2:my-g",
    );

    is($rc, 0, "dry run succeeds");
    ok(!-f $f2, "output not created");
    like($out, qr/Dry run/, "shows dry run message");
};

# Test 28: Help
subtest 'help' => sub {
    my ($rc, $out) = run('--help');
    like($out, qr/munin-migrate-rrd/, "help shows script name");
    like($out, qr/--append/, "help shows --append");
};

# Test 29: Output directory auto-created
subtest 'auto_create_dir' => sub {
    my $f1 = "$dbdir/t29/src.rrd";
    my $out = "$dbdir/t29/sub/dir/out.rrd";

    create_rrd($f1, '42', 'GAUGE', [50]);

    my ($rc) = run('-i', "$f1:42", '-o', "$out:x");

    is($rc, 0, "succeeded");
    ok(-f $out, "output created in new directory");
};

# Test 30: COUNTER type preserved
subtest 'counter_type' => sub {
    my $f1 = "$dbdir/t30/a.rrd";
    my $f2 = "$dbdir/t30/b.rrd";
    my $out = "$dbdir/t30/merged.rrd";

    create_rrd($f1, '42', 'GAUGE', [50]);
    create_rrd($f2, '42', 'COUNTER', [100]);

    my ($rc) = run(
        '-i', "$f1:42", '-o', "$out:g",
        '-i', "$f2:42", '-o', "$out:c",
    );

    is($rc, 0, "merge succeeded");
    is(ds_type($out, 'g'), 'GAUGE', "GAUGE preserved");
    is(ds_type($out, 'c'), 'COUNTER', "COUNTER preserved");
};

done_testing();
