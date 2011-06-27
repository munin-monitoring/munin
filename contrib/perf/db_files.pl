#! /usr/bin/perl
# Compare timings with BDB vs files

use strict;
use warnings;

use DB_File;
use DB_File::Lock;

my $nb_files = (shift || 1000);
my $nb_cmp = (shift || -10);

mkdir "db_$$";
chdir "db_$$";

sub db_update {
	my ($filename, $epoch, $value, $db_type) = @_;	

	my %hash;
	tie %hash, 'DB_File', "update.db", O_CREAT|O_RDWR, 0666, $db_type;
	db_update_conn($filename, $epoch, $value, \%hash);
	untie %hash;
}

sub db_update_conn {
	my ($filename, $epoch, $value, $h) = @_;

	$h->{$filename} = "$epoch:$value";
}

sub fl_update {
	my ($filename, $epoch, $value) = @_;	

	my $last_filename = "$filename.last";
	my $tmp_filename = "$last_filename.tmp";

	open (FILE, "> $tmp_filename");
	print FILE "$epoch:$value\n";
	close (FILE);

	rename ($tmp_filename, $last_filename);
}

use Benchmark qw(:all);
use Storable;

cmpthese($nb_cmp, {
		'fl_update' => sub { for (my $i = 0; $i < $nb_files; $i ++) { fl_update("test$i.rrd", $i, sin($i)); } },
		'db_update' => sub { for (my $i = 0; $i < $nb_files; $i ++) { db_update("test$i.rrd", $i, sin($i), $DB_HASH); } },
		'db_upda_c' => sub { 
			my %hash; tie %hash, 'DB_File', "update_c.db", O_CREAT|O_RDWR, 0666, $DB_HASH;
			for (my $i = 0; $i < $nb_files; $i ++) { db_update_conn("test$i.rrd", $i, sin($i), \%hash); } 
			untie %hash;
		},
		'storable' => sub { 
			my %hash;
			for (my $i = 0; $i < $nb_files; $i ++) { db_update_conn("test$i.rrd", $i, sin($i), \%hash); } 
			Storable::nstore(\%hash, "update.storable");
		},
	});


