# -*- perl -*-

use strict;
use warnings;

use Test::More 'no_plan';

BEGIN { use_ok('Munin::Master::Logger') }

subtest 'class loader' => sub {
    my $log = Munin::Master::Logger->new();
    isa_ok( $log, 'Munin::Master::Logger' );
};

subtest 'log something' => sub {
    my $log = Munin::Master::Logger->new;
    is( $log->debug('A test message from Munin::Master::Logger'),
        '', 'Log something' );
};
