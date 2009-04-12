use warnings;
use strict;

use English qw(-no_match_vars);
use Test::More tests => 4;

use_ok('Munin::Common::Timeout');


ok(do_with_timeout(1, sub {1}), "No timeout");


ok(!do_with_timeout(1, sub {system "sleep 2" }), "Timeout");


eval {
    do_with_timeout(1, sub {die "Test"});
};
like($EVAL_ERROR, qr/^Test/, "Exception")
