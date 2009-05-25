use warnings;
use strict;

use Test::More tests => 19;
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
    skip "Need to be run with sudo", 2 if $REAL_USER_ID != $root_uid;

    my $login = getpwnam $ENV{SUDO_USER};
    die "Test assumes that the user logged in on the controlling terminal is not root" if $login == 0;

    $os->set_effective_user_id($login);
    is($EFFECTIVE_USER_ID, $login, "Changed effective uid");

    eval {
        $os->set_effective_user_id(1);
    };
    like($@, qr{Operation not permitted});
}


### run_as_child
{
	my $io_child = sub {
		print STDERR "this is STDERR\n";
		print STDOUT "this is STDOUT\n";
		exit 12;
	};
	my $res = $os->run_as_child(10, $io_child);

	is($res->{stdout}[0], "this is STDOUT", 'Child STDOUT is captured');
	is($res->{stderr}[0], "this is STDERR", 'Child STDERR is captured');

	is($res->{retval} >> 8, 12, 'Exit value is captured');

	my $pid_child = sub {
		my $PPID = getppid;
		my $PGRP = getpgrp;

		my %info = (
			pid  => $PID,
			ppid => $PPID,
			pgrp => $PGRP,
		);

		local $OFS = "\n";
		print %info;
	};
	$res = $os->run_as_child(10, $pid_child);

	my %stdout = @{ $res->{stdout} };

	isnt($stdout{pid}, $PID, 'Function is run in its own process');
	is($stdout{ppid}, $PID, 'Child is ours');
	isnt($stdout{pgrp}, $PID, 'Child is not in our process group');
	is($stdout{pgrp}, $stdout{pid}, 'Child is process group leader');


	my $verbose_child = sub { print STDERR 'x' x 1_000_000 };
	$res = $os->run_as_child(5, $verbose_child);

	ok($res->{timed_out}, 'Child blocking on I/O times out');

}

