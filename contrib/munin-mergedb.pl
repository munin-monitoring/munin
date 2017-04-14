#!/usr/bin/perl
#
# Merge munin db (datafile{,.storable} / limits) for multi-update masters
# environment
#
# (c) GPL - Adrien "ze" Urban

use warnings;
use strict;

use Storable;
use Munin::Master::Utils;

# Example of config (munin-merge.conf):
#   # what to merge ?
#   merge_datafile yes
#   merge_limits yes
#   # destination is the directory having this file
#   
#   # source directories to merge from (option should be used multiple times)
#   merge_source_dbdir /nfs/munin/db/updatehost1
#   merge_source_dbdir /nfs/munin/db/updatehost2
#   merge_source_dbdir /nfs/munin/db/updatehost3
#   merge_source_dbdir /nfs/munin/db/updatehost4

my $configfile_name = 'munin-merge.conf';
my $config_type = {
	'merge_source_dbdir' => 'ARRAY',
	'merge_datafile' => 'BOOL',
	'merge_limits' => 'BOOL',
};
my $config = {
	'merge_dbdir' => undef,
	'merge_source_dbdir' => [],
	'merge_datafile' => 0,
	'merge_limits' => 0,
};

sub usage()
{
	print STDERR <<EOF;
Usage:
	$0 merge_dbdir

merge_dbdir should include a config file named $configfile_name.
This is also a security to avoid accidentally breaking everything.
EOF
	exit 1;
}

sub load_config()
{
	my $dbdir = $config->{'merge_dbdir'};
	my $file = $dbdir . "/" . $configfile_name;
	open FILE, "<", $file or die "open: $!\n";
	while (<FILE>) {
		chomp;
		next if (/^[[:space:]]*#/); # comment
		next if (/^[[:space:]]*$/); # empty line
		unless (/^[[:space:]]*([^[:space:]]+)[[:space:]]+([^[:space:]]+)[[:space:]]*$/) {
			die "$.: Unrecognized line format\n";
		}
		my ($key, $value) = ($1, $2);
		if (not defined $config_type->{$key}) {
			die "$.: $key: unrecognized option\n";
		}
		if ('ARRAY' eq $config_type->{$key}) {
			push @{$config->{$key}}, $value;
		} elsif ('BOOL' eq $config_type->{$key}) {
			if ($value =~ /(yes|y|1|true)/i) {
				$config->{$key} = 1;
			} elsif ($value =~ /(no?|0|false)/i) {
				$config->{$key} = 0;
			} else {
				die "$.: unrecognized boolean: $value\n";
			}
		} else {
			die "INTERNAL ERROR: $config_type->{$key}: " .
				"type not implemented\n";
		}
	}
	close FILE;
}
sub check_sources()
{
	if (0 == scalar(@{$config->{'merge_source_dbdir'}})) {
		die "No source dbdir. " . 
			"Should I produce a result from thin air?\n";
	}
	# no datafile, means it's not really a munin dbdir
	for my $srcdir (@{$config->{'merge_source_dbdir'}}) {
		unless (-f "$srcdir/datafile") {
			die "$srcdir: datafile not found";
		}
	}
}
sub merge_plaintext($)
{
	my $name = shift;
	my $data = [];
	my $version = undef;
	for my $srcdir (@{$config->{'merge_source_dbdir'}}) {
		my $srcfile = "$srcdir/$name";
		unless (-f $srcfile) {
			die "$srcdir: $name not found";
		}
		open FILE, "<", $srcfile or
			die "open: $srcfile: $!\n";
		my $ver = <FILE>;
		if (defined $version) {
			die "$srcfile: versions differs: $version vs $ver\n"
				if ($ver ne $version);
		} else {
			$version = $ver;
		}
		push @$data, <FILE>;
		close FILE;
		#print $name, " ", scalar(@$data), " ", $srcdir, "\n";
	}
	my $dstfile = $config->{'merge_dbdir'} . "/" . $name;
	my $dsttmp = $dstfile . ".tmp.$$";
	open FILE, ">", $dsttmp or
		die "open: $dsttmp: $!\n";
	print FILE $version, @$data;
	close FILE;
	rename $dsttmp, $dstfile or
		die "mv $dsttmp $dstfile: $!\n";
}
sub merge_datafile_storable()
{
	my $name = 'datafile.storable';
	
	my $data = undef;
	for my $srcdir (@{$config->{'merge_source_dbdir'}}) {
		my $srcfile = "$srcdir/$name";
		unless (-f $srcfile) {
			die "$srcdir: $name not found";
		}
		my $info = retrieve($srcfile);
		if (defined $data) {
	        	$data = munin_overwrite($data, $info);
		} else {
			$data = $info;
		}
	}
	my $dstfile = $config->{'merge_dbdir'} . "/" . $name;
	my $dsttmp = $dstfile . ".tmp.$$";
	Storable::nstore($data, $dsttmp);
	rename $dsttmp, $dstfile or
		die "mv $dsttmp $dstfile: $!\n";
}
sub merge_datafile()
{
	merge_plaintext('datafile');
	merge_datafile_storable();
}
sub merge_limits()
{
	merge_plaintext('limits');
}

usage unless (1 == scalar(@ARGV));
$config->{'merge_dbdir'} = shift @ARGV;

load_config;
check_sources;
merge_datafile if ($config->{'merge_datafile'});
merge_limits if ($config->{'merge_limits'});

exit 0;
