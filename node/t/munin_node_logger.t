# -*- perl -*-

use strict;
use warnings;

use Test::More 'no_plan';

BEGIN { use_ok('Munin::Node::Logger') }

subtest 'class loader' => sub {
    my $log = Munin::Node::Logger->new();
    isa_ok( $log, 'Munin::Node::Logger' );
};

subtest 'log something' => sub {
    my $log = Munin::Node::Logger->new;
    is( $log->debug('A test message from Munin::Node::Logger'),
        '', 'Log something' );
};
