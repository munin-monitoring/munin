use warnings;
use strict;
use English '-no_match_vars';

use Test::More tests => 7;

use_ok('Munin::Master::Utils');

# munin_mkdir_p
{
	ok(munin_mkdir_p("./mkdirt", oct(444)), "Creating valid dir");
	ok(!munin_mkdir_p("./mkdirt/bad", oct(444)), "Creating invalid dir");
	eval {
		rmdir("./mkdirt")
	};
	ok(!$EVAL_ERROR, "Removing dir (please do manual cleanup on failure)");
}

# munin_get
{
	my $sentinel = 12345;
	is(munin_get(undef, undef, $sentinel), 
	   $sentinel, 
	   "munin_get from undef gives back default");
	
	my $th1 = {"tfield" => 5};
	is(munin_get($th1, "tfield", $sentinel), 
	   5, 
	   "munin_get recovers numeric field");
	
	my $th2 = {"tfield" => {"innerfield" => 5}};
	is(munin_get($th2, "tfield", $sentinel), 
	   $sentinel, 
	   "munin_get returns default on hash field");
}
