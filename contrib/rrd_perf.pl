#! /usr/bin/perl
# RRD update perf testing
# (c) GPL - Steve Schnepp <steve.schnepp@pwkf.org>

use strict;
use warnings;

use RRDs;

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

# Simulate a munin's workload
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
