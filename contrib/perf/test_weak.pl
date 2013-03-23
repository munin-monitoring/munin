#! /usr/bin/perl

use warnings;
use strict;

use Storable;
use Scalar::Util qw(weaken isweak);

my $number = 1000;
my $a = {};

for my $j (0 .. $number) {
	$a = {};
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
}
