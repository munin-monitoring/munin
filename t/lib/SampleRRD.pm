#!/usr/bin/perl
# Generate sample RRD files for the current architecture.
# Replaces committed binary RRDs that break cross-architecture.

package SampleRRD;

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
        { name => "in",      type => "GAUGE",   min => "0", max => "" },
        { name => "out",     type => "GAUGE",   min => "0", max => "" },
        { name => "value1",  type => "GAUGE",   min => "0", max => "100" },
        { name => "value2",  type => "GAUGE",   min => "0", max => "100" },
        { name => "value3",  type => "GAUGE",   min => "0", max => "100" },
        { name => "value4",  type => "COUNTER", min => "0", max => "100" },
        { name => "value5",  type => "GAUGE",   min => "0", max => "100" },
    );

    # Services that use multi-DS RRDs (new style)
    my %multi_ds_services = map { $_ => 1 } qw(cpu memory network);
    # Hosts that use old-style single-DS RRDs
    my %old_style_hosts = map { $_ => 1 } qw(aesir asynjur svartalfar);

    my $now = time();
    my $start = $now - (3600 * 24 * 30); # 30 days of data
    my $step = 300; # 5 minutes
    my $ds_id_counter = 0;

    for my $host (@hosts) {
        my $path = ($host eq "localhost") ? "acme.com/$host" : $host;
        for my $svc (@services) {
            for my $ds (@ds_defs) {
                my $heartbeat = $step * 2;
                my $min = $ds->{min} || 'U';
                my $max = $ds->{max} || 'U';
                # Determine DS name and RRD structure based on host/service
                my $is_old_style = $old_style_hosts{$host};
                my $ds_name;
                my @rrd_ds_defs;
                my $is_multi_ds = $multi_ds_services{$svc} && !$is_old_style;

                if ($is_old_style) {
                    # Old style: single-DS RRD with DS name "42"
                    $ds_name = "42";
                    @rrd_ds_defs = (sprintf("DS:42:%s:%s:%s:%s",
                        $ds->{type}, $heartbeat, $min, $max));
                } elsif ($is_multi_ds) {
                    # Multi-DS: skip individual fields, create once per service
                    next if $ds->{name} ne $ds_defs[0]->{name};
                    $ds_name = "g";
                    # Build one DS for each field in this service
                    for my $d (@ds_defs) {
                        my $tc = lc(substr($d->{type}, 0, 1));
                        my $dmin = $d->{min} || 'U';
                        my $dmax = $d->{max} || 'U';
                        push @rrd_ds_defs, sprintf("DS:%s-%s:%s:%s:%s:%s",
                            $d->{name}, $tc, $d->{type}, $heartbeat, $dmin, $dmax);
                    }
                } else {
                    # Non-multi service: single-DS with field name
                    my $type_code = lc(substr($ds->{type}, 0, 1));
                    $ds_name = "$ds->{name}-$type_code";
                    @rrd_ds_defs = (sprintf("DS:%s:%s:%s:%s:%s",
                        $ds_name, $ds->{type}, $heartbeat, $min, $max));
                }

                # Set filepath based on RRD style
                my $filepath;
                if ($is_old_style) {
                    $filepath = "$dbdir/$path/$svc-$ds->{name}-" . lc(substr($ds->{type}, 0, 1)) . ".rrd";
                } elsif ($is_multi_ds) {
                    $filepath = "$dbdir/$path/$svc.rrd";
                } else {
                    my $type_code = lc(substr($ds->{type}, 0, 1));
                    $filepath = "$dbdir/$path/$svc-$ds->{name}-$type_code.rrd";
                }
                make_path("$dbdir/$path", { mode => 0755 });
                next if -f $filepath;

                RRDs::create($filepath,
                    "--start", ($start - $step),
                    "-s", $step,
                    @rrd_ds_defs,
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

                # Populate with deterministic data
                my $seed = 42 + $ds_id_counter++;
                my @updates;
                for (my $t = $start; $t < $now; $t += $step) {
                    my $val;
                    if ($ds->{type} eq "DERIVE") {
                        $val = $seed % 1000;
                    } else {
                        $val = $seed % 100;
                    }
                    $seed = ($seed * 1103515245 + 12345) & 0x7fffffff;  # LCG

                    if ($is_multi_ds) {
                        # Multi-DS update: values for all DS in one update
                        my @vals;
                        my $s = $seed;
                        for my $d (@ds_defs) {
                            my $v;
                            if ($d->{type} eq "DERIVE") {
                                $v = $s % 1000;
                            } else {
                                $v = $s % 100;
                            }
                            $s = ($s * 1103515245 + 12345) & 0x7fffffff;
                            push @vals, $v;
                        }
                        push @updates, "$t:" . join(":", @vals);
                    } else {
                        push @updates, "$t:$val";
                    }
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
