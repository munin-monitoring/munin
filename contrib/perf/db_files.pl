#! /usr/bin/perl
# Compare timings with BDB vs files

use strict;
use warnings;

use DB_File;
use Munin::Common::DictFile;

my $nb_files = (shift || 1000);
my $nb_cmp = (shift || -10);

print "using db_$$\n";
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

sub fh_update {
	my ($filename, $hash) = @_;	

	my $last_filename = "$filename.last";
	my $tmp_filename = "$last_filename.tmp";

	open (FILE, "> $tmp_filename");
	foreach my $key (keys %$hash) {
		print FILE $key . "\t" . $hash->{$key} . "\n";
	}
	close (FILE);

	rename ($tmp_filename, $last_filename);
}

use Benchmark qw(:all);
use Storable;
use SDBM_File;

STDOUT->autoflush(1);
cmpthese($nb_cmp, {
		'fl_update' => sub { 
			print "Starting fl_update: "; 
			for (my $i = 0; $i < $nb_files; $i ++) { fl_update("test$i.rrd", $i, rand($i)); }
			print "done.\n"; 
		},
		'fh_update' => sub { 
			print "Starting fh_update: "; 
			my %hash;
			for (my $i = 0; $i < $nb_files; $i ++) { db_update_conn("test$i.rrd", $i, rand(), \%hash); } 
			fh_update("update.txt", \%hash);
			print "done.\n"; 
		},
		'db_upda_c' => sub { 
			print "Starting db_upda_c: "; 
			my %hash; tie %hash, 'DB_File', "update_c.db", O_CREAT|O_RDWR, 0666, $DB_HASH;
			for (my $i = 0; $i < $nb_files; $i ++) { db_update_conn("test$i.rrd", $i, rand(), \%hash); } 
			untie %hash;
			print "done.\n"; 
		},
		'sdbm' => sub { 
			print "Starting sdbm: "; 
			my %hash; tie %hash, 'SDBM_File', "update_sdbm.db", O_CREAT|O_RDWR, 0666;
			for (my $i = 0; $i < $nb_files; $i ++) { db_update_conn("test$i.rrd", $i, rand(), \%hash); } 
			untie %hash;
			print "done.\n"; 
		},
		'dictfile' => sub { 
			print "Starting dictfile: "; 
			my %hash; tie %hash, 'Munin::Common::DictFile', "update_munin_dict.txt", O_CREAT|O_RDWR, 0666;
			for (my $i = 0; $i < $nb_files; $i ++) { db_update_conn("test$i.rrd", $i, rand(), \%hash); } 
			untie %hash;
			%hash = ();
			print "done.\n"; 
		},
		'storable' => sub { 
			print "Starting storable: "; 
			my $hash = ( -e "update.storable" ) ? Storable::retrieve("update.storable") : {};
			for (my $i = 0; $i < $nb_files; $i ++) { db_update_conn("test$i.rrd", $i, rand(), $hash); } 
			Storable::nstore($hash, "update.storable.$$");
			rename("update.storable.$$", "update.storable");
			print "done.\n"; 
		},
	});


