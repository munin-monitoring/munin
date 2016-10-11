package Munin::Master::Group::Tests;
use base qw(Test::Class);
use Test::More;

use Munin;

sub variables : Test(2) {
    ok($Munin::munin_conf, '$munin_conf present');
    ok($Munin::munin_node_conf, '$munin_node_conf present');
}

1;
