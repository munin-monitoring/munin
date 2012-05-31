use warnings;
use strict;

use Test::More tests => 24;
use Test::Differences;

use Munin::Node::Service;

use English qw(-no_match_vars);

my $uname = getpwuid $UID;
my $gid   = (split / /, $GID)[0];
my $gname = getgrgid $gid;


my $config = Munin::Node::Config->instance();

$config->reinitialize({
	timeout => 10,
	servicedir => '/service/directory',
	sconf => {
        # testing environment
		test => { env => { test_environment_variable => 'fnord' } },

        # testing user resolution
        uname => { user => $uname },
        uid   => { user => $UID   },
        bad_uname => { user => '%%SSKK¤¤' },
        bad_uid   => { user => 999999999  },

        # testing group resolution
        gid   => { groups => [ 0      ] },
        gname => { groups => [ 'root' ] },
        bad_gname => { groups => [ '%%SSKK¤¤' ] },
        bad_gid   => { groups => [ 999999999  ] },

        # testing optional group resolution
        opt_gid       => { groups => [ '(0)'         ] },
        opt_gname     => { groups => [ '(root)'      ] },
        opt_bad_gname => { groups => [ '(%%SSKK¤¤)'  ] },
        opt_bad_gid   => { groups => [ '(999999999)' ] },

        several_groups => { groups => [ 0, "($gname)" ] },
        several_groups_required => { groups => [ 0, $gname ] },
        several_groups_mixture => { groups => [ '(%%SSKK¤¤)', 0 ] },

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
    my $services = Munin::Node::Service->new(defuser => $UID);

    is($services->_resolve_uid('uname'), $UID, 'Lookup by service-specific username');
    is($services->_resolve_uid('uid'),   $UID, 'Lookup by service-specific username');

    $services->{defuser} = 0;

    is($services->_resolve_uid('no_user'), 0, 'Default user is used if specific user is not provided');

    eval { $services->_resolve_uid('bad_uname') };
    like($@, qr/'%%SSKK¤¤'/, 'Exception thrown when resolving non-existant username');

    eval { $services->_resolve_uid('bad_uid') };
    like($@, qr/'999999999'/, 'Exception thrown when resolving non-existant uid');
}

### _resolve_gids
{
    my $services = Munin::Node::Service->new(defgroup => $gid);

    eq_or_diff([ $services->_resolve_gids('no_groups')   ], [ $gid, "$gid $gid" ], 'default group by gid');

    eq_or_diff([ $services->_resolve_gids('gid')   ], [ $gid, "$gid $gid 0" ], 'extra group by gid');
    eq_or_diff([ $services->_resolve_gids('gname') ], [ $gid, "$gid $gid 0" ], 'extra group by name');

    eval { $services->_resolve_gids('bad_gid') };
    like($@, qr/'999999999'/, 'Exception thrown if an additional group could not be resolved');

    eval { $services->_resolve_gids('bad_gname') };
    like($@, qr/'%%SSKK¤¤'/, 'Exception thrown if an additional group could not be resolved');

    eq_or_diff([ $services->_resolve_gids('opt_gname')     ], [ $gid, "$gid $gid 0" ], 'extra optional group by name');
    eq_or_diff([ $services->_resolve_gids('opt_bad_gname') ], [ $gid, "$gid $gid" ],   'unresolvable extra groups are ignored');

    eq_or_diff([ $services->_resolve_gids('opt_gid')         ], [ $gid, "$gid $gid 0" ], 'extra optional group by gid');
    eq_or_diff([ $services->_resolve_gids('opt_bad_gid') ], [ $gid, "$gid $gid" ],   'unresolvable extra gids are ignored');

    eq_or_diff(
        [$services->_resolve_gids('several_groups') ],
        [$gid, "$gid $gid 0 $gid"],
        'several extra groups'
    );
    eq_or_diff(
        [$services->_resolve_gids('several_groups_required')],
        [$gid, "$gid $gid 0 $gid"],
        'several groups, less whitespace'
    );
    eq_or_diff(
        [$services->_resolve_gids('several_groups_mixture')],
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
		'Custom service command with substitution (service with argument).'
	);
}


### fork_service
{
    my $services = Munin::Node::Service->new(servicedir => '/fnord');
	my $ret = $services->fork_service('foo');
	is($ret->{retval} >> 8, 42, 'Attempted to run non-existant service');
}


# vim: sw=4 : ts=4 : et
