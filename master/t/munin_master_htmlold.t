use warnings;
use strict;
use English '-no_match_vars';

use Test::More tests => 4;

use_ok('Munin::Master::HTMLOld');

my $test_path = [ {'path' => "../../index.html" } ];

#munin_get_root
{
    
   is(Munin::Master::HTMLOld::get_root_path($test_path), "../..");

   $test_path = [ {'path' => "../index.html" } ];

   is(Munin::Master::HTMLOld::get_root_path($test_path), "..");

   is(Munin::Master::HTMLOld::get_root_path(), "");
    
}
