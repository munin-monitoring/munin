#! /usr/bin/perl

use warnings;
use strict;

use File::Temp;
use Data::Dumper;
use Storable qw(nstore_fd fd_retrieve);
use Scalar::Util qw(weaken isweak);

my $number = shift || 10;
my $a = {};

for my $i (0 .. $number) {
	$a->{$i} = {
		"$i$i" => "$i$i",
		"$i$i" => "$i$i",
	};
}

for my $i (0 .. $number) {
	$a->{$i}{next} = $a->{ ($i + 1) % $number };
	weaken($a->{$i}{next}) if $ENV{WEAKEN};
}

my $temp_storable = File::Temp->new();

nstore_fd($a, $temp_storable);

for my $j (0 .. ($number * $number)) {
	$temp_storable->seek( 0, SEEK_SET );
	$a = fd_retrieve($temp_storable);
}

print Dumper($a);
