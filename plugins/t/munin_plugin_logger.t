# -*- perl -*-

use strict;
use warnings;

use Test::More 'no_plan';

BEGIN { use_ok('Munin::Plugin::Logger') }

subtest 'class loader' => sub {
    my $log = Munin::Plugin::Logger->new();
    isa_ok( $log, 'Munin::Plugin::Logger' );
};

subtest 'log something' => sub {
    my $log = Munin::Plugin::Logger->new;
    is( $log->debug('A test message from Munin::Plugin::Logger'),
        '', 'Log something' );
};
