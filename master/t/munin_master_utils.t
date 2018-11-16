use warnings;
use strict;
use English '-no_match_vars';

use Scalar::Util "weaken";

use Test::More tests => 11;

use_ok('Munin::Master::Utils');

# munin_mkdir_p
{
	ok(munin_mkdir_p("./mkdirt", oct(444)), "Creating valid dir");
	SKIP: {
		skip "Directory permission cannot be tested by root", 1 if $REAL_USER_ID == 0;
		ok(!munin_mkdir_p("./mkdirt/bad", oct(444)), "Creating invalid dir");
	}
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

	my $h = {
		"a" => {
			"upper1" => "1-a",
			"upper2" => "2-a",
			"aa" => {
				"field1" => "1-aa",
				"field2" => "2-aa",
			},
			"ab" => {
				"field1" => "1-aa",
				"field2" => "2-ab",
				"field3" => "3-ab",
			},
			"ac" => {
				"field1" => "1-ac",
				"field2" => "2-ac",
			},
		},
		"b" => {
			"ba" => {
				"field1" => "1-ba",
			},
		},
	};
	$h->{a}{aa}{'#%#parent'} = $h->{a}; weaken($h->{a}{aa}{'#%#parent'});
	$h->{a}{ab}{'#%#parent'} = $h->{a}; weaken($h->{a}{ab}{'#%#parent'});
	$h->{a}{ac}{'#%#parent'} = $h->{a}; weaken($h->{a}{ac}{'#%#parent'});
	$h->{b}{ba}{'#%#parent'} = $h->{b}; weaken($h->{b}{ba}{'#%#parent'});
        is(munin_get($h, "a", $sentinel), $sentinel, "munin_get returns default on hash field");
        is(munin_get($h->{a}->{aa}, "field1", $sentinel), $h->{a}->{aa}->{field1}, "munin_get recovers field value");
        is(munin_get($h->{a}->{aa}, "upper2", $sentinel), $h->{a}->{upper2}, "munin_get recovers field value, from above");
        is(munin_get($h->{a}->{ba}, "upper2", $sentinel), $sentinel, "munin_get recovers default, no value from above");
}
