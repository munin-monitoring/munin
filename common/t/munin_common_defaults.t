use warnings;
use strict;

use FindBin;
use lib "$FindBin::Bin/../lib";

use Test::More tests => 1;

use_ok('Munin::Common::Defaults');
