use strict;
use warnings;

use lib qw(t/lib);


use Test::More;
use Test::Differences;

require_ok( 'Munin::Master::Graph' );
done_testing();

1;
