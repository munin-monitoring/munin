use warnings;
use strict;

use FindBin;
use lib "$FindBin::Bin/../lib";

use Test::More tests => 5;
use English qw(-no_match_vars);

use_ok('Munin::OS');

### get_uid

my $uname = getpwuid $UID;

is(Munin::OS->get_uid($uname), $UID, 'Lookup by user name');
is(Munin::OS->get_uid($UID),   $UID, 'Lookup by user ID');


### get_gid

my $gid   = (split / /, $GID)[0];
my $gname = getgrgid $gid;

is(Munin::OS->get_gid($gname), $gid, 'Lookup by group name');
is(Munin::OS->get_gid($gid),   $gid, 'Lookup by group ID');


