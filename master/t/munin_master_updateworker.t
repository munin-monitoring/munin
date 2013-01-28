use warnings;
use strict;

use Test::More tests => 1;
use Test::MockModule;

# Faking RRDs.pm, as we don't really need it
package RRDs;
our $version = "1.4-mock";
package main;

use_ok('Munin::Master::UpdateWorker');

