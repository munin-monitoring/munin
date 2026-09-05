#!/usr/bin/perl
# Generate sample RRD files for the current architecture.
# Replaces committed binary RRDs that break cross-architecture.

use strict;
use warnings;
use RRDs;
use File::Path qw(make_path);
use File::Basename;
use POSIX qw(strftime);

sub generate_sample_rrds {
    my ($dbdir, $num_services) = @_;
    $num_services //= 10;

    my @hosts = ("localhost", "acme.com", "aesir", "asynjur", "svartalfar");
    my @services = ("cpu", "memory", "disk", "network", "load");
    my @ds_defs = (
        { name => "idle",    type => "GAUGE",   min => "0", max => "100" },
        { name => "user",    type => "GAUGE",   min => "0", max => "100" },
        { name => "system",  type => "GAUGE",   min => "0", max => "100" },
        { name => "used",    type => "GAUGE",   min => "0", max => "" },
        { name => "free",    type => "GAUGE",   min => "0", max => "" },
        { name => "cached",  type => "GAUGE",   min => "0", max => "" },
        { name => "rx",      type => "DERIVE",  min => "0", max => "" },
        { name => "tx",      type => "DERIVE",  min => "0", max => "" },
        { name => "in",      type => "DERIVE",  min => "0", max => "" },
        { name => "out",     type => "DERIVE",  min => "0", max => "" },
        { name => "value1",  type => "GAUGE",   min => "0", max => "100" },
        { name => "value2",  type => "GAUGE",   min => "0", max => "100" },
        { name => "value3",  type => "GAUGE",   min => "0", max => "100" },
        { name => "value4",  type => "GAUGE",   min => "0", max => "100" },
        { name => "value5",  type => "GAUGE",   min => "0", max => "100" },
    );

    my $now = time();
    my $start = $now - (3600 * 24 * 30); # 30 days of data
    my $step = 300; # 5 minutes

    for my $host (@hosts) {
        for my $svc (@services) {
            for my $ds (@ds_defs) {
                my $type_id = lc(substr($ds->{type}, 0, 1));
                my $filename = "$host-$svc-$ds->{name}-$type_id.rrd";
                my $filepath = "$dbdir/$host/$filename";

                make_path("$dbdir/$host", { mode => 0755 });

                # Skip if already exists
                next if -f $filepath;

                my $heartbeat = $step * 2;
                my $ds_def = sprintf("DS:42:%s:%s:%s:%s",
                    $ds->{type}, $heartbeat, $ds->{min}, $ds->{max});

                RRDs::create($filepath,
                    "--start", ($start - $step),
                    "-s", $step,
                    $ds_def,
                    "RRA:AVERAGE:0.5:1:576",
                    "RRA:MIN:0.5:1:576",
                    "RRA:MAX:0.5:1:576",
                    "RRA:AVERAGE:0.5:6:432",
                    "RRA:MIN:0.5:6:432",
                    "RRA:MAX:0.5:6:432",
                    "RRA:AVERAGE:0.5:24:540",
                    "RRA:MIN:0.5:24:540",
                    "RRA:MAX:0.5:24:540",
                    "RRA:AVERAGE:0.5:288:450",
                    "RRA:MIN:0.5:288:450",
                    "RRA:MAX:0.5:288:450",
                );

                if (my $err = RRDs::error) {
                    warn "RRD create error for $filepath: $err";
                    next;
                }

                # Populate with sample data
                my @updates;
                for (my $t = $start; $t < $now; $t += $step) {
                    my $val;
                    if ($ds->{type} eq "DERIVE") {
                        $val = int(rand(1000));
                    } else {
                        $val = int(rand(100));
                    }
                    push @updates, "$t:$val";
                }

                RRDs::update($filepath, @updates);
                if (my $err = RRDs::error) {
                    warn "RRD update error for $filepath: $err";
                }
            }
        }
    }
}

1;
