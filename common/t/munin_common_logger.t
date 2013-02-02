# -*- perl -*-

use strict;
use warnings;

use Test::More 'no_plan';

BEGIN { use_ok('Munin::Common::Logger') }

subtest 'class loader' => sub {
    my $log = Munin::Common::Logger->new();
    isa_ok( $log, 'Munin::Common::Logger' );
};

subtest 'log something' => sub {
    my $log = Munin::Common::Logger->new;
    is( $log->debug('A test message from Munin::Common::Logger'),
        '', 'log a message' );
};
