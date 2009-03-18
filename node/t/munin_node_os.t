use warnings;
use strict;

use FindBin;
use lib "$FindBin::Bin/../lib";

use Test::More tests => 9;
use English qw(-no_match_vars);

use_ok('Munin::Node::OS');

### get_uid

my $uname = getpwuid $UID;

is(Munin::Node::OS->get_uid($uname), $UID, 'Lookup by user name');
is(Munin::Node::OS->get_uid($UID),   $UID, 'Lookup by user ID');

is(Munin::Node::OS->get_uid('%%SSKK¤¤'), undef, 'Nonexistent user name');
is(Munin::Node::OS->get_uid(999999999), undef, 'Nonexistent user ID');



### get_gid

my $gid   = (split / /, $GID)[0];
my $gname = getgrgid $gid;

is(Munin::Node::OS->get_gid($gname), $gid, 'Lookup by group name');
is(Munin::Node::OS->get_gid($gid),   $gid, 'Lookup by group ID');

is(Munin::Node::OS->get_gid('%%SSKK¤¤'), undef, 'Nonexistent group name');
is(Munin::Node::OS->get_gid(999999999), undef, 'Nonexistent group ID');
