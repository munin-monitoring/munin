#!/usr/bin/perl

=head1 NAME

t/munin_migrate_rrd.t - Tests for munin-migrate-rrd tool

=cut

use strict;
use warnings;
use File::Spec;
use File::Temp qw(tempdir);
use File::Basename qw(dirname);
use FindBin;
use Test::More;
use RRDs;
use File::Path qw(make_path remove_tree);

# Find the script
my $script = "$FindBin::Bin/../script/munin-migrate-rrd";
plan skip_all => "Script not found: $script" unless -f $script;

# Create temp directory for test
my $tmpdir = tempdir(CLEANUP => 1);
my $dbdir = "$tmpdir/rrd";

# Create directories
make_path($dbdir, { mode => 0755 });

# Create single-DS RRD file
sub create_single_ds_rrd {
    my ($filepath, $type, $data) = @_;
    
    my $dir = dirname($filepath);
    make_path($dir, { mode => 0755 }) unless -d $dir;
    
    my $heartbeat = 600;
    my $start = time() - 86400;
    
    RRDs::create($filepath,
        '--start', $start - 300,
        '-s', 300,
        "DS:42:$type:$heartbeat:0:U",
        'RRA:AVERAGE:0.5:1:576',
        'RRA:MIN:0.5:1:576',
        'RRA:MAX:0.5:1:576',
    );
    
    die "RRDs::create failed: " . RRDs::error if RRDs::error;
    
    # Add data
    if ($data && @$data) {
        my $when = $start;
        for my $val (@$data) {
            RRDs::update($filepath, "$when:$val");
            die "RRDs::update failed: " . RRDs::error if RRDs::error;
            $when += 300;
        }
    }
}

# Create multi-DS RRD file
sub create_multi_ds_rrd {
    my ($filepath, $ds_defs, $data) = @_;
    
    my $dir = dirname($filepath);
    make_path($dir, { mode => 0755 }) unless -d $dir;
    
    my $heartbeat = 600;
    my $start = time() - 86400;
    
    my @ds_args;
    for my $ds (@$ds_defs) {
        push @ds_args, "DS:$ds->{name}:$ds->{type}:$heartbeat:0:U";
    }
    
    RRDs::create($filepath,
        '--start', $start - 300,
        '-s', 300,
        @ds_args,
        'RRA:AVERAGE:0.5:1:576',
        'RRA:MIN:0.5:1:576',
        'RRA:MAX:0.5:1:576',
    );
    
    die "RRDs::create failed: " . RRDs::error if RRDs::error;
    
    # Add data
    if ($data && @$data) {
        my $when = $start;
        for my $vals (@$data) {
            RRDs::update($filepath, "$when:" . join(':', @$vals));
            die "RRDs::update failed: " . RRDs::error if RRDs::error;
            $when += 300;
        }
    }
}

# Get RRD data
sub get_rrd_data {
    my ($filepath, $ds_name) = @_;
    
    my ($start, $end, $step, $nb, $cols, $values) = RRDs::xport(
        '--start', 'now-86400',
        '--end', 'now',
        "DEF:val=$filepath:$ds_name:AVERAGE",
        "XPORT:val",
    );
    
    if (RRDs::error) {
        return [];
    }
    
    return [grep { defined $_ && $_ ne 'nan' } map { $_->[0] } @$values];
}

# Get DS names
sub get_ds_names {
    my ($filepath) = @_;
    
    my $info = RRDs::info($filepath);
    return () if RRDs::error;
    
    my @ds_names;
    for my $key (sort keys %$info) {
        if ($key =~ /^ds\[([^\]]+)\]\.type$/) {
            push @ds_names, $1;
        }
    }
    return @ds_names;
}

# Run migration tool
sub run_migrate {
    my (@args) = @_;
    
    my $cmd = "perl $script --dbdir=$dbdir @args 2>&1";
    my $output = `$cmd`;
    my $exit_code = $? >> 8;
    
    return ($exit_code, $output);
}

# Test 1: Basic merge (single-DS to multi-DS)
subtest 'merge_single_to_multi_ds' => sub {
    my $idle_file = "$dbdir/acme.com/localhost/cpu-idle-g.rrd";
    my $user_file = "$dbdir/acme.com/localhost/cpu-user-g.rrd";
    my $system_file = "$dbdir/acme.com/localhost/cpu-system-g.rrd";
    my $target_file = "$dbdir/acme.com/localhost/cpu-g.rrd";
    
    create_single_ds_rrd($idle_file, 'GAUGE', [50, 60, 70, 80]);
    create_single_ds_rrd($user_file, 'GAUGE', [10, 20, 30, 40]);
    create_single_ds_rrd($system_file, 'GAUGE', [5, 10, 15, 20]);
    
    # Verify single-DS files exist
    ok(-f $idle_file, "Single-DS idle file exists");
    ok(-f $user_file, "Single-DS user file exists");
    ok(-f $system_file, "Single-DS system file exists");
    
    # Get data before merge
    my $idle_before = get_rrd_data($idle_file, '42');
    my $user_before = get_rrd_data($user_file, '42');
    my $system_before = get_rrd_data($system_file, '42');
    
    # Run merge
    my ($exit_code, $output) = run_migrate(
        '--merge', '--verbose',
        '-i', "$idle_file:42", '-o', "$target_file:idle-g",
        '-i', "$user_file:42", '-o', "$target_file:user-g",
        '-i', "$system_file:42", '-o', "$target_file:system-g",
    );
    
    is($exit_code, 0, "Merge succeeded");
    like($output, qr/Created $target_file/, "Created multi-DS file");
    like($output, qr/Wrote \d+ updates/, "Wrote updates");
    
    # Verify multi-DS file exists
    ok(-f $target_file, "Multi-DS file exists");
    
    # Verify single-DS files removed
    ok(!-f $idle_file, "Single-DS idle removed");
    ok(!-f $user_file, "Single-DS user removed");
    ok(!-f $system_file, "Single-DS system removed");
    
    # Verify DS names
    my @ds_names = get_ds_names($target_file);
    is(scalar @ds_names, 3, "Multi-DS has 3 DS");
    is_deeply(\@ds_names, ['idle-g', 'system-g', 'user-g'], "DS names correct");
    
    # Verify data was copied
    my $idle_after = get_rrd_data($target_file, 'idle-g');
    my $user_after = get_rrd_data($target_file, 'user-g');
    my $system_after = get_rrd_data($target_file, 'system-g');
    
    ok(scalar @$idle_after > 0, "Data copied for idle");
    ok(scalar @$user_after > 0, "Data copied for user");
    ok(scalar @$system_after > 0, "Data copied for system");
};

# Test 2: Dry run
subtest 'dry_run' => sub {
    my $idle_file = "$dbdir/test-dry/cpu-idle-g.rrd";
    my $target_file = "$dbdir/test-dry/cpu-g.rrd";
    
    create_single_ds_rrd($idle_file, 'GAUGE', [50, 60]);
    
    my $size_before = -s $idle_file;
    
    my ($exit_code, $output) = run_migrate(
        '--merge', '--dry-run', '--verbose',
        '-i', "$idle_file:42", '-o', "$target_file:idle-g",
    );
    
    is($exit_code, 0, "Dry run succeeded");
    like($output, qr/Dry run/, "Shows dry run message");
    like($output, qr/:idle-g/, "Shows mapping");
    
    # Verify original file still exists
    ok(-f $idle_file, "Original file still exists");
    is(-s $idle_file, $size_before, "File not modified");
    ok(!-f $target_file, "Target file not created");
};

# Test 3: Split (multi-DS to single-DS)
subtest 'split_multi_to_single_ds' => sub {
    my $source_file = "$dbdir/test-split/cpu-g.rrd";
    my $idle_file = "$dbdir/test-split/cpu-idle-g.rrd";
    my $user_file = "$dbdir/test-split/cpu-user-g.rrd";
    
    create_multi_ds_rrd($source_file,
        [
            { name => 'idle-g', type => 'GAUGE' },
            { name => 'user-g', type => 'GAUGE' },
        ],
        [[50, 10], [60, 20], [70, 30]],
    );
    
    ok(-f $source_file, "Multi-DS file exists");
    
    my $idle_before = get_rrd_data($source_file, 'idle-g');
    my $user_before = get_rrd_data($source_file, 'user-g');
    
    my ($exit_code, $output) = run_migrate(
        '--split', '--verbose',
        '-i', "$source_file:idle-g", '-o', "$idle_file:42",
        '-i', "$source_file:user-g", '-o', "$user_file:42",
    );
    
    is($exit_code, 0, "Split succeeded");
    like($output, qr/Created $idle_file/, "Created idle file");
    like($output, qr/Created $user_file/, "Created user file");
    
    # Verify single-DS files exist
    ok(-f $idle_file, "Single-DS idle exists");
    ok(-f $user_file, "Single-DS user exists");
    
    # Verify multi-DS file removed
    ok(!-f $source_file, "Multi-DS source removed");
    
    # Verify DS count
    is(scalar get_ds_names($idle_file), 1, "idle has 1 DS");
    is(scalar get_ds_names($user_file), 1, "user has 1 DS");
    
    # Verify data was copied
    my $idle_after = get_rrd_data($idle_file, '42');
    my $user_after = get_rrd_data($user_file, '42');
    
    ok(scalar @$idle_after > 0, "Data copied for idle");
    ok(scalar @$user_after > 0, "Data copied for user");
};

# Test 4: Comma syntax
subtest 'comma_syntax' => sub {
    my $idle_file = "$dbdir/test-comma/cpu-idle-g.rrd";
    my $user_file = "$dbdir/test-comma/cpu-user-g.rrd";
    my $target_file = "$dbdir/test-comma/cpu-g.rrd";
    
    create_single_ds_rrd($idle_file, 'GAUGE', [50, 60]);
    create_single_ds_rrd($user_file, 'GAUGE', [10, 20]);
    
    # Use comma syntax
    my ($exit_code, $output) = run_migrate(
        '--merge', '--verbose',
        '-i', "$idle_file:42,$user_file:42",
        '-o', "$target_file:idle-g,user-g",
    );
    
    is($exit_code, 0, "Comma syntax merge succeeded");
    ok(-f $target_file, "Target file created");
    
    my @ds = get_ds_names($target_file);
    is(scalar @ds, 2, "Has 2 DS");
};

# Test 5: Mismatched input/output count
subtest 'mismatched_count' => sub {
    my $file = "$dbdir/test-mismatch/cpu.rrd";
    create_single_ds_rrd($file, 'GAUGE', [50]);
    
    my ($exit_code, $output) = run_migrate(
        '--merge',
        '-i', "$file:42",
        '-o', "$file:idle-g",
        '-o', "$file:user-g",
    );
    
    isnt($exit_code, 0, "Fails with mismatched count");
    like($output, qr/Number of inputs.*must equal/, "Error message about mismatch");
};

# Test 6: Missing input file
subtest 'missing_input_file' => sub {
    my ($exit_code, $output) = run_migrate(
        '--merge',
        '-i', "/nonexistent/file.rrd:42",
        '-o', "$dbdir/test-missing/cpu.rrd:idle-g",
    );
    
    isnt($exit_code, 0, "Fails with missing input");
    like($output, qr/does not exist/, "Error message about missing file");
};

# Test 7: No --merge or --split
subtest 'no_mode' => sub {
    my ($exit_code, $output) = run_migrate(
        '-i', "file.rrd:42",
        '-o', "file.rrd:idle-g",
    );
    
    isnt($exit_code, 0, "Fails without mode");
    like($output, qr/Must specify --merge or --split/, "Error message about mode");
};

# Test 8: Help message
subtest 'help_message' => sub {
    my ($exit_code, $output) = run_migrate('--help');
    
    like($output, qr/munin-migrate-rrd/, "Help contains script name");
    like($output, qr/--merge/, "Help contains --merge");
    like($output, qr/--split/, "Help contains --split");
    like($output, qr/-i/, "Help contains -i");
    like($output, qr/-o/, "Help contains -o");
};

# Test 9: Merge with different types
subtest 'merge_different_types' => sub {
    my $gauge_file = "$dbdir/test-types/cpu-idle-g.rrd";
    my $derive_file = "$dbdir/test-types/cpu-tx-d.rrd";
    my $target_file = "$dbdir/test-types/cpu-g.rrd";
    
    create_single_ds_rrd($gauge_file, 'GAUGE', [50, 60]);
    create_single_ds_rrd($derive_file, 'DERIVE', [100, 200]);
    
    my ($exit_code, $output) = run_migrate(
        '--merge',
        '-i', "$gauge_file:42", '-o', "$target_file:idle-g",
        '-i', "$derive_file:42", '-o', "$target_file:tx-d",
    );
    
    is($exit_code, 0, "Merge with different types succeeded");
    
    # Verify DS types
    my $info = RRDs::info($target_file);
    is($info->{'ds[idle-g].type'}, 'GAUGE', "idle-g is GAUGE");
    is($info->{'ds[tx-d].type'}, 'DERIVE', "tx-d is DERIVE");
};

# Test 10: Data integrity after merge
subtest 'data_integrity' => sub {
    my $idle_file = "$dbdir/test-integrity/cpu-idle-g.rrd";
    my $target_file = "$dbdir/test-integrity/cpu-g.rrd";
    
    my @data = (50, 60, 70, 80, 90, 100);
    create_single_ds_rrd($idle_file, 'GAUGE', \@data);
    
    my $before = get_rrd_data($idle_file, '42');
    
    my ($exit_code, $output) = run_migrate(
        '--merge',
        '-i', "$idle_file:42", '-o', "$target_file:idle-g",
    );
    
    is($exit_code, 0, "Merge succeeded");
    
    my $after = get_rrd_data($target_file, 'idle-g');
    
    # Both should have data (exact count depends on xport resolution)
    ok(scalar @$before > 0, "Input has data");
    ok(scalar @$after > 0, "Output has data");
    
    if (@$before && @$after) {
        # Values should be similar (RRD consolidation may affect exact values)
        ok(abs($before->[0] - $after->[0]) < 10, "First values similar");
        ok(abs($before->[-1] - $after->[-1]) < 10, "Last values similar");
    }
};

# Clean up
END {
    if ($tmpdir && -d $tmpdir) {
        remove_tree($tmpdir, { error => \my $err });
        if (@$err) {
            warn "Error removing $tmpdir: " . join(", ", map { values %$_ } @$err);
        }
    }
}

done_testing();
