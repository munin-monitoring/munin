#! /usr/bin/perl
# RRD update perf testing
#
# Copyright (c) 2011 Steve Schnepp <steve.schnepp@pwkf.org>
#
# License: GPL

use strict;
use warnings;

use RRDs;
use Time::HiRes;

use Getopt::Long;

my $graph_interval;
my $graph_ratio = 100;
my $verbose;

GetOptions(
	"g=i" => \$graph_interval,
	"r=i" => \$graph_ratio,
	"verbose" => \$verbose,
) or die "invalid options";

my $nb_rrd = (shift || 100);
my $nb_rrd_per_dir = (shift || 100);
my $step = (shift || 300);
my $heartbeat = $step * 2;

my $rrd_dir = "rrds-$$";
mkdir $rrd_dir;
my @rrds;

# create all the rrds
print "creating rrds in $rrd_dir\n";
for (my $rrd_number=0; $rrd_number < $nb_rrd; $rrd_number ++) {
	my $rrd_dir_num = int ($rrd_number / $nb_rrd_per_dir);
	my $rrdfilename = "$rrd_dir/$rrd_dir_num/$rrd_number.rrd";
	mkdir "$rrd_dir/$rrd_dir_num";
	print STDERR "creating RRD $rrdfilename\n";
	RRDs::create(
		$rrdfilename,
		#"--start", "-10y",
		"-s", "$step",
		"DS:42:GAUGE:$heartbeat:U:U",
              "RRA:AVERAGE:0.5:1:576",   # resolution 5 minutes
              "RRA:MIN:0.5:1:576",
              "RRA:MAX:0.5:1:576",
              "RRA:AVERAGE:0.5:6:432",   # 9 days, resolution 30 minutes
              "RRA:MIN:0.5:6:432",
              "RRA:MAX:0.5:6:432",
              "RRA:AVERAGE:0.5:24:540",  # 45 days, resolution 2 hours
              "RRA:MIN:0.5:24:540",
              "RRA:MAX:0.5:24:540",
              "RRA:AVERAGE:0.5:288:450", # 450 days, resolution 1 day
              "RRA:MIN:0.5:288:450",
              "RRA:MAX:0.5:288:450",
	);
	push @rrds, $rrdfilename;
}

# Simulating munin's graphing in a sub process
if ($graph_interval && ! fork()) {
	while(1) {
		my $offset = int rand($nb_rrd);

		for (my $i = 0; $i < $nb_rrd * $graph_ratio / 100;  $i++) {
			my $rrdfilename = $rrds[($offset + $i) % $nb_rrd];
			print STDERR "graphing RRD $rrdfilename\n";
			RRDs::graph(
				'/dev/null',
				"DEF:a=$rrdfilename:42:AVERAGE",
				"LINE1:a",
			);
		}
	} continue {
		sleep 1 / $graph_interval;
	}
	exit;
}

# Simulate a munin's update workload
while (1) {
	my $epoch = time;
	for my $rrdfilename (@rrds) {
		my $value = 100 * sin($epoch) + rand();
		print STDERR "updating RRD $rrdfilename\n";
		RRDs::update(
			$rrdfilename,
			"$epoch:$value",
		);
	}

	sleep($step);
}


sub get_rrd_filename
{
	my $rrd_number = shift;
}
