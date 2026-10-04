use strict;
use warnings;

use lib qw(lib t/lib);

use Test::More;
use File::Temp qw(tempfile);
use TestUtils;
use TestState;

# Must set up config BEFORE loading UpdateWorker, as it captures $config
# at module load time via: my $config = Munin::Master::Config->instance()->{config}
use Munin::Master::Config;

my $temp_dir = TestState::state_dir();
my $config = Munin::Master::Config->instance()->{config};
$config->{dbdir}  = $temp_dir;
$config->{logdir} = $temp_dir;

use Munin::Master::Update;
use Munin::Master::UpdateWorker;
use RRDs;

# Production schema: all tables the exercised worker paths read
my ($dbh, $dbfile);
BEGIN {
    ($dbh, $dbfile) = tempfile(CLEANUP => 1);
    $dbh = TestUtils::dbh_rw($dbfile);
}
Munin::Master::Update::_db_init(bless({}, "Munin::Master::Update"), $dbh);

# The exercised paths JOIN node (and grp through it) for override lookup
$dbh->do("INSERT INTO grp (id, p_id, name, path) VALUES (1, 0, 'testgroup', 'testgroup')");
$dbh->do("INSERT INTO node (id, grp_id, name, path) VALUES (1, 1, 'testhost', 'testhost')");

# Mock host: _get_rrd_file_name/_get_rrd_group_file_name need get_full_path
{
    package MockHost;
    sub get_full_path { return $_[0]->{path}; }
}

sub make_worker {
    return bless {
        dbh     => $dbh,
        node_id => 1,
        host    => bless({ path => "testhost" }, "MockHost"),
    }, "Munin::Master::UpdateWorker";
}

# The RRD file/DS mapping of one field, from ds_rrd
sub get_rrd_map {
    my ($plugin, $field) = @_;
    return $dbh->selectrow_array(
        "SELECT r.file, r.field FROM ds_rrd r
         JOIN ds d ON d.id = r.ds_id
         JOIN service s ON s.id = d.service_id
         WHERE s.node_id = 1 AND s.name = ? AND d.name = ?",
        undef, $plugin, $field);
}

sub get_ds_deleted {
    my ($plugin, $field) = @_;
    return $dbh->selectrow_array(
        "SELECT d.deleted FROM ds d
         JOIN service s ON s.id = d.service_id
         WHERE s.node_id = 1 AND s.name = ? AND d.name = ?",
        undef, $plugin, $field);
}

# RRDs::info plus a name=>type map of the file's DS
sub rrd_ds_info {
    my ($file) = @_;
    my $info = RRDs::info($file);
    my %types;
    for my $key (keys %$info) {
        $types{$1} = $info->{$key} if $key =~ /^ds\[(.+)\]\.type$/;
    }
    return ($info, \%types);
}

# Last value RRDtool recorded for one DS (verifies a fetch batch landed
# in the right DS of the right file)
sub last_ds {
    my ($file, $ds_name) = @_;
    my $info = RRDs::info($file);
    return $info->{"ds[$ds_name].last_ds"};
}

my $multi_file  = "$temp_dir/testhost-cpu.rrd";
my $steal_file  = "$temp_dir/testhost-cpu-steal-g.rrd";
my $nice_file   = "$temp_dir/testhost-cpu-nice-g.rrd";

my $t1 = int(time() / 300) * 300 - 600;    # aligned, strictly in the past
my $t2 = $t1 + 300;
my $t3 = $t2 + 300;
my $t4 = $t3 + 300;
my $t5 = $t4 + 300;
my $t6 = $t5 + 300;

# Full service config for the cpu plugin at a given timestamp set.
# steal has a different RRA layout -> cannot share the multi-DS file.
sub cpu_config {
    my ($args) = @_;    # { when => ts, field => value, ... }
    my $when = $args->{when};
    my %vals = %$args;
    delete $vals{when};
    my @lines = (
        "graph_title Test CPU",
        "graph_category system",
        "update_rate 5m",
        "idle.label Idle",
        "user.label User",
        "rx.label Received",
        "rx.type DERIVE",
        "rx.min 0",
        "rx.max 100000",
        "steal.label Steal",
        "steal.graph_data_size huge",
    );
    push @lines, "nice.label Nice" if exists $vals{nice};
    for my $field (sort keys %vals) {
        push @lines, "$field.value $when:$vals{$field}";
    }
    return @lines;
}

# ============================================================================
# TEST: _get_rrd_group_key
# ============================================================================

subtest "_get_rrd_group_key: fields group by effective RRD layout" => sub {
    my $worker = make_worker();
    my $k = sub { return $worker->_get_rrd_group_key($_[0]); };

    is($k->({ update_rate => 300 }), $k->({ update_rate => "5m" }),
       "300 and 5m normalize to the same key");

    # 'normal'/'huge'/'debug' hard-code the 300s step in _create_rrd_file,
    # so update_rate must not split fields that get an identical layout
    is($k->({ update_rate => 300, graph_data_size => "normal" }),
       $k->({ update_rate => 600, graph_data_size => "normal" }),
       "normal resolution groups regardless of update_rate");
    is($k->({ update_rate => 600, graph_data_size => "huge" }),
       $k->({ update_rate => 300, graph_data_size => "huge" }),
       "huge resolution groups regardless of update_rate");

    isnt($k->({ graph_data_size => "normal" }), $k->({ graph_data_size => "huge" }),
         "different graph_data_size -> different key");
    isnt($k->({ update_rate => 300, graph_data_size => "custom 1h" }),
         $k->({ update_rate => 600, graph_data_size => "custom 1h" }),
         "custom resolution: RRAs depend on update_rate -> different keys");

    # Type/min/max are per-DS and must not affect grouping
    is($k->({ type => "GAUGE", min => 0, max => 100 }),
       $k->({ type => "DERIVE", min => "U", max => "U" }),
       "type/min/max do not affect the key");
};

# ============================================================================
# TEST: _flush_rrd_updates — grouped template updates
# ============================================================================

subtest "_flush_rrd_updates: one update per (file, template)" => sub {
    my $worker = make_worker();

    my @calls;
    {
        no warnings 'redefine';
        local *RRDs::update = sub { push @calls, [@_]; return };
        local *RRDs::error  = sub { return undef };

        $worker->_flush_rrd_updates({
            "host/a.rrd" => {
                1000 => { "x-g" => 1, "y-g" => "1.5e3" },
                2000 => { "x-g" => 3 },
                3000 => { "x-g" => 4 },
            },
            "host/b.rrd" => { 1500 => { "z-d" => 9 } },
        });
    }

    is(scalar @calls, 3, "one call per (file, template) run");

    # Files processed in sorted order; within a file, timestamps ascend
    is($calls[0][0], "$temp_dir/host/a.rrd", "file path dbdir-qualified");
    is($calls[0][1], "-t", "template flag used");
    is($calls[0][2], "x-g:y-g", "template lists the DS with values, sorted");
    is($calls[0][3], "1000:1:1500.0000",
       "row: sorted DS order, scientific value pre-converted");

    is($calls[1][2], "x-g", "template change starts a new call");
    is_deeply([ @{$calls[1]}[3 .. $#{$calls[1]}] ], [ "2000:3", "3000:4" ],
              "consecutive same-template rows vectorized in timestamp order");

    is($calls[2][0], "$temp_dir/host/b.rrd", "second file processed");
    is($calls[2][2], "z-d", "second file template");
    is($calls[2][3], "1500:9", "second file row");
};

# ============================================================================
# TEST: cycle 1 — auto multi-DS creation
# ============================================================================

subtest "compatible fields share one multi-DS RRD" => sub {
    my $worker = make_worker();

    my @config = cpu_config({ when => $t1, idle => 10, user => 20, rx => 1000, steal => 5 });
    push @config, cpu_config({ when => $t2, idle => 11, user => 21, rx => 1500, steal => 6 });
    my $rate_ptr;
    my $last = $worker->uw_handle_config("cpu", $t1, \@config, 0, \$rate_ptr);

    is($last, $t2, "fetch part returned the latest fetch timestamp");

    # ds_rrd mapping layout
    my ($file, $field) = get_rrd_map("cpu", "idle");
    is($file, "testhost-cpu.rrd", "GAUGE field 1 lives in the service RRD");
    is($field, "idle-g", "idle DS name");
    ($file, $field) = get_rrd_map("cpu", "user");
    is($file, "testhost-cpu.rrd", "GAUGE field 2 lives in the service RRD");
    is($field, "user-g", "user DS name");
    ($file, $field) = get_rrd_map("cpu", "rx");
    is($file, "testhost-cpu.rrd", "DERIVE field shares the service RRD");
    is($field, "rx-d", "rx DS name");
    ($file, $field) = get_rrd_map("cpu", "steal");
    is($file, "testhost-cpu-steal-g.rrd", "incompatible field falls back to a per-field RRD");
    is($field, "steal-g", "steal DS name");

    # Multi-DS file layout
    ok(-f $multi_file, "service RRD file created");
    my ($info, $ds_types) = rrd_ds_info($multi_file);
    is_deeply([sort keys %$ds_types], ["idle-g", "rx-d", "user-g"],
              "multi-DS file holds all compatible DS");
    is($ds_types->{"rx-d"}, "DERIVE", "per-DS type preserved in the shared file");
    is($info->{step}, 300, "step from update_rate");
    is($info->{"ds[idle-g].minimal_heartbeat"}, 600, "heartbeat = 2x step");
    ok(!defined $info->{"ds[idle-g].min"}, "per-DS min U preserved");
    is($info->{"ds[rx-d].min"}, 0, "per-DS min preserved");
    is($info->{"ds[rx-d].max"}, 100000, "per-DS max preserved");

    # Incompatible field: separate file with its own RRAs
    ok(-f $steal_file, "per-field RRD file created");
    my ($sinfo, $sds) = rrd_ds_info($steal_file);
    is_deeply([sort keys %$sds], ["steal-g"], "per-field file holds only its DS");
    is($sinfo->{"rra[0].cf"}, "AVERAGE", "huge resolution keeps AVERAGE RRA");
    is($sinfo->{"rra[0].pdp_per_row"}, 1, "huge resolution: 5-minute RRA kept");
    is($sinfo->{"rra[0].rows"}, 115200, "huge resolution: 400 days of 5-minute rows");

    # The fetch batch landed in the right DS of the right file
    is(last_ds($multi_file, "idle-g"), 11, "idle value in shared file");
    is(last_ds($multi_file, "user-g"), 21, "user value in shared file");
    is(last_ds($multi_file, "rx-d"), 1500, "rx value in shared file");
    is(last_ds($steal_file, "steal-g"), 6, "steal value in own file");
};

# ============================================================================
# TEST: cycle 2 — late field falls back to a per-field RRD
# ============================================================================

subtest "late field falls back to a per-field RRD" => sub {
    my $worker = make_worker();    # fresh worker: __SEEN_PLUGINS__ guard

    my @config = cpu_config({ when => $t3, idle => 12, user => 22, rx => 1600, steal => 7, nice => 3 });
    $worker->uw_handle_config("cpu", $t3, \@config, 0, \my $rate_ptr);

    # Established fields keep their mappings (stateful)
    my ($file) = get_rrd_map("cpu", "idle");
    is($file, "testhost-cpu.rrd", "idle keeps the multi-DS file");
    ($file) = get_rrd_map("cpu", "user");
    is($file, "testhost-cpu.rrd", "user keeps the multi-DS file");

    # RRDtool cannot add a DS to an existing file -> per-field fallback
    my ($nfile, $nfield) = get_rrd_map("cpu", "nice");
    is($nfile, "testhost-cpu-nice-g.rrd", "late field gets its own file");
    is($nfield, "nice-g", "late field DS name");

    # Every field still updates
    is(last_ds($multi_file, "idle-g"), 12, "shared file updated again");
    is(last_ds($nice_file, "nice-g"), 3, "late field file updated");
};

# ============================================================================
# TEST: cycle 3 — mapping stable across cycles (no regrouping)
# ============================================================================

subtest "mappings are stable across cycles" => sub {
    my $worker = make_worker();

    my @config = cpu_config({ when => $t4, idle => 13, user => 23, rx => 1700, steal => 8, nice => 4 });
    $worker->uw_handle_config("cpu", $t4, \@config, 0, \my $rate_ptr);

    my ($file) = get_rrd_map("cpu", "nice");
    is($file, "testhost-cpu-nice-g.rrd",
       "late field still on its own file (not regrouped into the multi-DS file)");
    ($file) = get_rrd_map("cpu", "idle");
    is($file, "testhost-cpu.rrd", "idle still on the multi-DS file");

    is(last_ds($multi_file, "idle-g"), 13, "shared file updated");
    is(last_ds($nice_file, "nice-g"), 4, "late field file updated");
};

# ============================================================================
# TEST: cycle 4 — deleted field: just stop updating
# ============================================================================

subtest "deleted field: mapping kept, updates stop" => sub {
    my $worker = make_worker();

    # nice disappears from the plugin config
    my @config = cpu_config({ when => $t5, idle => 14, user => 24, rx => 1800, steal => 9 });
    $worker->uw_handle_config("cpu", $t5, \@config, 0, \my $rate_ptr);

    is(get_ds_deleted("cpu", "nice"), 1, "field is soft-deleted");
    is(get_ds_deleted("cpu", "idle"), 0, "live field not deleted");

    my ($nfile, $nfield) = get_rrd_map("cpu", "nice");
    is($nfile, "testhost-cpu-nice-g.rrd", "deleted field keeps its RRD mapping");
    is($nfield, "nice-g", "deleted field keeps its DS name");
    ok(-f $nice_file, "deleted field's RRD file untouched");

    # Its DS simply stops being updated...
    is(last_ds($nice_file, "nice-g"), 4, "no new value written for the deleted field");
    # ...while the live fields of the service keep flowing
    is(last_ds($multi_file, "idle-g"), 14, "live fields still updated");
    is(last_ds($steal_file, "steal-g"), 9, "live per-field file still updated");
};

# ============================================================================
# TEST: cycle 5 — reappearing field resurrects with history
# ============================================================================

subtest "reappearing field resurrects with continuous history" => sub {
    my $worker = make_worker();

    my @config = cpu_config({ when => $t6, idle => 15, user => 25, rx => 1900, steal => 10, nice => 5 });
    $worker->uw_handle_config("cpu", $t6, \@config, 0, \my $rate_ptr);

    is(get_ds_deleted("cpu", "nice"), 0, "field resurrected");
    my ($nfile) = get_rrd_map("cpu", "nice");
    is($nfile, "testhost-cpu-nice-g.rrd", "mapping unchanged across delete/resurrect");
    is(last_ds($nice_file, "nice-g"), 5, "updates resume on the same RRD file");
};

# ============================================================================
# TEST: established per-field layout is left alone
# ============================================================================

subtest "established per-field layout is untouched" => sub {
    # Simulate a legacy install: ds already carries an old-style mapping
    # (one file per field, DS name "42")
    my $legacy_file = "$temp_dir/testhost-disk-used-g.rrd";
    RRDs::create($legacy_file, "--start", $t6 - 600, "-s", 300,
                 "DS:42:GAUGE:600:U:U", "RRA:AVERAGE:0.5:1:10");
    $dbh->do("INSERT INTO service (node_id, name) VALUES (1, 'disk')");
    my ($svc_id) = $dbh->selectrow_array(
        "SELECT id FROM service WHERE node_id = 1 AND name = 'disk'");
    $dbh->do("INSERT INTO ds (service_id, name) VALUES (?, 'used')", undef, $svc_id);
    my ($ds_id) = $dbh->selectrow_array(
        "SELECT id FROM ds WHERE service_id = ? AND name = 'used'", undef, $svc_id);
    $dbh->do("INSERT INTO ds_rrd (ds_id, file, field) VALUES (?, 'testhost-disk-used-g.rrd', '42')",
             undef, $ds_id);

    my $worker = make_worker();
    my @config = (
        "graph_title Disk",
        "update_rate 5m",
        "used.label Used",
        "used.value $t6:42",
    );
    $worker->uw_handle_config("disk", $t6, \@config, 0, \my $rate_ptr);

    my ($file, $field) = get_rrd_map("disk", "used");
    is($file, "testhost-disk-used-g.rrd", "legacy mapping kept");
    is($field, "42", "legacy DS name kept");
    ok(!-e "$temp_dir/testhost-disk.rrd", "no multi-DS file created for an established layout");

    # Legacy single-DS file still updates through the template path
    is(last_ds($legacy_file, "42"), 42, "legacy file updated via template");
};

done_testing();

1;
