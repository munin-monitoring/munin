use strict;
use warnings;

use lib qw(t/lib);


use Test::More;

require_ok( 'Munin::Master::Update' );
require_ok( 'Munin::Master::Config' );

my $globconfig = Munin::Master::Config->instance();
my $config = $globconfig->{'config'};

ok($config->parse_config_from_file("t/config/munin.conf"));

done_testing();

1;
