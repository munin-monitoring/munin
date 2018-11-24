use warnings;
use strict;

use Test::More tests => 28;
use Test::LongString;
use Config;  # for signal numbers and names

use English qw(-no_match_vars);

use Munin::Node::OS;

my $os = 'Munin::Node::OS';

### get_uid
{
	my $uname = getpwuid $UID;

	is($os->get_uid($uname), $UID, 'Lookup by user name');
	is($os->get_uid($UID),   $UID, 'Lookup by user ID');

	is($os->get_uid('%%SSKK¤¤'), undef, 'Nonexistent user name');
	is($os->get_uid(999999999),  undef, 'Nonexistent user ID');
}


### get_gid
{
	my $gid   = (split / /, $GID)[0];
	my $gname = getgrgid $gid;

	is($os->get_gid($gname), $gid, 'Lookup by group name');
	is($os->get_gid($gid),   $gid, 'Lookup by group ID');

	is($os->get_gid('%%SSKK¤¤'), undef, 'Nonexistent group name');
	is($os->get_gid(999999999),  undef, 'Nonexistent group ID');
}

### _get_xid
# tested above


### get_fq_hostname
# probably there is no good way to test it, since we cannot expect a certain host setup
# (e.g. "test for a dot in the FQDN" fails in the Debian reproducibility test environment)


### check_perms_if_paranoid


### run_as_child
{
	my $io_child = sub {
		print STDERR "this is STDERR\n";
		print STDOUT "this is STDOUT\n";
		exit 12;
	};
	my $res = $os->run_as_child(5, $io_child);

	is($res->{stdout}[0], "this is STDOUT", 'Child STDOUT is captured');
	is($res->{stderr}[0], "this is STDERR", 'Child STDERR is captured');
}
{
	my $exit_child = sub { exit 12 };
	my $res = $os->run_as_child(5, $exit_child);

	is($res->{retval} >> 8, 12, 'Exit value is captured');
}
{
	my $signal_child = sub { kill 'PIPE', $PID };
	my $res = $os->run_as_child(5, $signal_child);

	my %signo;
	@signo{split ' ', $Config{sig_name}} = split / /, $Config{sig_num};

	is($res->{retval} & 127, $signo{PIPE}, 'Death signal is captured');
}
{
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
	my $res = $os->run_as_child(5, $pid_child);

	my %stdout = @{ $res->{stdout} };

	isnt($stdout{pid},  $PID,         'Function is run in its own process');
	is(  $stdout{ppid}, $PID,         'Child is ours');
	isnt($stdout{pgrp}, $PID,         'Child is in a different process group');
	is(  $stdout{pgrp}, $stdout{pid}, 'Child is process group leader');
}
{
	my $sleepy_child = sub { sleep 100; exit 1 };
 	my $res = $os->run_as_child(1, $sleepy_child);
	ok($res->{timed_out}, 'Child is timed out if it was taking too long');
}
{
	my $verbose_child = sub { print STDERR 'x' x 1_000_000 };
 	my $res = $os->run_as_child(5, $verbose_child);

	ok(! $res->{timed_out}, q{Child blocking on I/O doesn't time out});
	is_string((shift @{$res->{stderr}}), ('x' x 1_000_000), 'Read all the contents of standard error');
}
{
	my $multiplexing_child = sub {
		foreach (1 .. 10) {
			print STDERR 'x' x 5_000;
			print STDOUT 'y' x 5_000;
		}
	};
	my $res = $os->run_as_child(5, $multiplexing_child);

	is_string((shift @{$res->{stdout}}), ('y' x 50_000), 'Read all the contents of standard out');
	is_string((shift @{$res->{stderr}}), ('x' x 50_000), 'Read all the contents of standard error');
}

### reap_child_group

### possible_to_signal_process
{
	ok(  $os->possible_to_signal_process($$),     'can send a signal to ourselves');
	ok(! $os->possible_to_signal_process(999999), 'cannot signal non-existant process');
}

SKIP: {
	skip "Test assumes that the user is not root", 1 if $REAL_USER_ID == 0;
	ok(! $os->possible_to_signal_process(1), 'cannot signal to init');
}

SKIP: {
	skip "Test assumes that the user is root", 1 if $REAL_USER_ID != 0;
	ok($os->possible_to_signal_process(1), 'can signal to init');
}

### set_effective_user_id
### set_real_user_id
### set_effective_group_id
### set_real_group_id
SKIP: {
    skip "Need to be run with sudo", 2 if $REAL_USER_ID != 0;

    my $login = defined($ENV{SUDO_USER}) ? getpwnam $ENV{SUDO_USER} : 0;
    skip "Test assumes that the user logged in on the controlling terminal is not root", 2 if $login == 0;

    $os->set_effective_user_id($login);
    is($EFFECTIVE_USER_ID, $login, "Changed effective UID");

    eval { $os->set_effective_user_id(1) };
    like($@, qr{Operation not permitted}, 'Not allowed to switch users again');
}


### set_umask
{
	my $old_umask = umask;
	umask(0022) or die "error changing umask for tests: $!";

	$os->set_umask;
	is(umask, 0002, 'umask has been changed');

	umask($old_umask) or warn "unable to change umask back to $old_umask: $!";
}

