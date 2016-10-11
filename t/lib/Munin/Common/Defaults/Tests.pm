package Munin::Master::Group::Tests;
use base qw(Test::Class);
use Test::More;

use Munin::Common::Defaults;

sub function__get_defaults : Test {
    ok(Munin::Common::Defaults->get_defaults());
}

sub function__export_to_environment : Test {

    # This function always return a false value
    Munin::Common::Defaults->export_to_environment();

    ok($ENV{MUNIN_VERSION}, 'environment variable set');
}

1;
