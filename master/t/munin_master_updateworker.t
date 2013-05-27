use warnings;
use strict;

use Test::More tests => 1;
use Test::MockObject;

# Faking RRDs.pm, as we don't really need it
my $mock = Test::MockObject->new();
$mock->fake_module( 'RRDs',
	'create' => sub { },
	'error' => sub { },
);

use_ok('Munin::Master::UpdateWorker');
