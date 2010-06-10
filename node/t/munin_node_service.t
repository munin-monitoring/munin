use warnings;
use strict;

use Test::More tests => 24;
use Test::Differences;

use Munin::Node::Service;

use English qw(-no_match_vars);

my $config = Munin::Node::Config->instance();

$config->reinitialize({
	timeout => 10,
	servicedir => '/service/directory',
	sconf => {
		test => {
			env => {
				test_environment_variable => 'fnord'
			}
		}
	}
});


### new
{
    new_ok('Munin::Node::Service' => [ servicedir => '/service/directory' ]);

    my $services = Munin::Node::Service->new();
    ok(exists $services->{servicedir}, 'servicedir key gets a default');
}


# FIXME: required to avoid errors when calling export_service_environment().
# would normally be exported by prepare_plugin_environment
$ENV{MUNIN_MASTER_IP} = '';

### export_service_environment
{
	Munin::Node::Service->export_service_environment('test');
	is($ENV{test_environment_variable}, 'fnord', 'Service-specific environment is exported');
}


### is_a_runnable_service


### _resolve_uid
{
    my $uname = getpwuid $UID;

    is(Munin::Node::Service::_resolve_uid(undef, $uname, 'fnord'), $UID, 'Lookup by service-specific username');
    is(Munin::Node::Service::_resolve_uid(undef, $UID,   'fnord'), $UID, 'Lookup by service-specific username');

    is(Munin::Node::Service::_resolve_uid($UID, 0, 'fnord'), 0, 'Default user is ignored if specific user is set');

    is(Munin::Node::Service::_resolve_uid(0, undef, 'fnord'), 0, 'Default user is used if specific user is not provided');

    eval { Munin::Node::Service::_resolve_uid(undef, '%%SSKK¤¤', 'fnord') };
    like($@, qr/'%%SSKK¤¤'/, 'Exception thrown when resolving non-existant username');

    eval { Munin::Node::Service::_resolve_uid(undef, 999999999, 'fnord') };
    like($@, qr/'999999999'/, 'Exception thrown when resolving non-existant uid');
}


### _resolve_gids
{
    my $gid   = (split / /, $GID)[0];
    my $gname = getgrgid $gid;

    eq_or_diff([ Munin::Node::Service::_resolve_gids('fnord', $gid)   ], [ $gid, "$gid $gid" ], 'default group by gid');
    
    eq_or_diff([ Munin::Node::Service::_resolve_gids('fnord', $gid, [0])      ], [ $gid, "$gid $gid 0" ], 'extra group by gid');
    eq_or_diff([ Munin::Node::Service::_resolve_gids('fnord', $gid, ['root']) ], [ $gid, "$gid $gid 0" ], 'extra group by name'); 

    eval { Munin::Node::Service::_resolve_gids('fnord', $gid, [999999999]) };
    like($@, qr/'999999999'/, 'Exception thrown if an additional group could not be resolved');


    eq_or_diff([ Munin::Node::Service::_resolve_gids('fnord', $gid, ['(root)'])     ], [ $gid, "$gid $gid 0" ], 'extra optional group by name');
    eq_or_diff([ Munin::Node::Service::_resolve_gids('fnord', $gid, ['(%%SSKK¤¤)']) ], [ $gid, "$gid $gid" ],   'unresolvable extra groups are ignored');


    eq_or_diff([ Munin::Node::Service::_resolve_gids('fnord', $gid, ['(0)'])         ], [ $gid, "$gid $gid 0" ], 'extra optional group by gid');
    eq_or_diff([ Munin::Node::Service::_resolve_gids('fnord', $gid, ['(999999999)']) ], [ $gid, "$gid $gid" ],   'unresolvable extra gids are ignored');


    eq_or_diff(
        [Munin::Node::Service::_resolve_gids('fnord', $gid, [0, "($gname)"])],
        [$gid, "$gid $gid 0 $gid"],
        'several extra groups'
    );
    eq_or_diff(
        [Munin::Node::Service::_resolve_gids('fnord', $gid, [0, $gname])],
        [$gid, "$gid $gid 0 $gid"],
        'several groups, less whitespace'
    );
    eq_or_diff(
        [Munin::Node::Service::_resolve_gids('fnord', $gid, ['(%%SSKK¤¤)', 0])],
        [$gid, "$gid $gid 0"],
        'resolvable and unresolvable extra groups'
    );

}


### change_real_and_effective_user_and_group


### exec_service


### _service_command
{
	my $dir      = '/service/directory';
	my $plugin   = 'test';
	my $argument = 'config';

	$config->{sconf}{test}{command} = undef;
	is_deeply(
		[ Munin::Node::Service::_service_command($dir, $plugin, $argument) ],
		[ "/service/directory/$plugin", $argument ],
		'No custom service command.'
	);

	$config->{sconf}{test}{command} = [ qw/a b c d/ ];
	is_deeply(
		[ Munin::Node::Service::_service_command($dir, $plugin, $argument) ],
		[ qw/a b c d/ ],
		'Custom service command without substitution.'
	);

	$config->{sconf}{test}{command} = [ qw/a b %c d/ ];
	is_deeply(
		[ Munin::Node::Service::_service_command($dir, $plugin, $argument) ],
		[ 'a', 'b', "/service/directory/$plugin", $argument, 'd' ],
		'Custom service command with substitution.'
	);
}


### fork_service
{
	my $ret = Munin::Node::Service->fork_service('/fnord', 'foo');
	is($ret->{retval} >> 8, 42, 'Attempted to run non-existant service');
}


# vim: sw=4 : ts=4 : et
