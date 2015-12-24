use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/lib";

use Munin::Master::ProcessManager::Tests;

Test::Class->runtests;
