use warnings;
use strict;

use English qw(-no_match_vars);
use Test::More tests => 6;

use_ok('Munin::Common::Timeout');

BEGIN { 
	if (Time::HiRes->can('alarm')){ 
		Time::HiRes->import('alarm') ; 
	} 
}

# These test could have been made to run faster by using
# Time::HiRes::alarm. Adding this to the module:
#
#   BEGIN {
#       if (Time::HiRes->can('alarm')){
#           Time::HiRes->import('alarm') ;
#       }
#   }
# 
# However Time::HiRes::alarm is not compatible with nested alarms
# (alarm(0) does not return time remaining)
#
# :(

ok(do_with_timeout(1, sub {1}), "No timeout");


ok(!do_with_timeout(1, sub { for (;;) {}; return 1; }), "Timeout");


eval {
    do_with_timeout(1, sub {die "Test"});
};
like($EVAL_ERROR, qr/^Test/, "Exception gets propagated");


######################################################################


{
    my ($stat1, $stat2);
    $stat1 = do_with_timeout(20, sub {
        $stat2 = do_with_timeout(1, sub {
            for (;;) {}
        });
	return 1;
    });

    ok(!$stat2, "Inner timed out");
    ok($stat1,  "Outer didn't time out during evaluation of inner");
}


######################################################################


