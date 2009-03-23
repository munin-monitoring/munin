use warnings;
use strict;

use FindBin;
use lib "$FindBin::Bin/../lib";

use Test::More tests => 11;
use English qw(-no_match_vars);

use_ok('Munin::Node::OS');

my $os = 'Munin::Node::OS';

my $uname      = getpwuid $UID;
my $gid        = (split / /, $GID)[0];
my $gname      = getgrgid $gid;

### get_uid

is($os->get_uid($uname), $UID, 'Lookup by user name');
is($os->get_uid($UID),   $UID, 'Lookup by user ID');

is($os->get_uid('%%SSKK¤¤'), undef, 'Nonexistent user name');
is($os->get_uid(999999999), undef, 'Nonexistent user ID');


### get_gid

is($os->get_gid($gname), $gid, 'Lookup by group name');
is($os->get_gid($gid),   $gid, 'Lookup by group ID');

is($os->get_gid('%%SSKK¤¤'), undef, 'Nonexistent group name');
is($os->get_gid(999999999), undef, 'Nonexistent group ID');


### _set_xid

my $root_uid = 0;

SKIP: {
    skip "Need to be run with sudo", 1 if $REAL_USER_ID != $root_uid;

    my $login = getpwnam $ENV{SUDO_USER};
    die "Test assumes that the user logged in on the controlling terminal is not root" if $login == 0;

    $os->set_effective_user_id($login);
    is($EFFECTIVE_USER_ID, $login, "Changed effective uid");

    eval {
        $os->set_effective_user_id(1);
    };
    like($@, qr{Operation not permitted});
}
