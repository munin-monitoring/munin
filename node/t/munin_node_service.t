use warnings;
use strict;

use Test::More tests => 35;
use Test::Differences;

use Data::Dumper;
use Carp;
use File::Temp qw( tempdir );

use Munin::Node::Service;

use English qw(-no_match_vars);

my $uname = getpwuid $UID;
my $gid   = (split / /, $GID)[0];
my $gname = getgrgid $gid;


our $dir;

sub touch
{
    open my $f, '>', "$dir/$_[0]" or croak $!;
    set_perms(0700, $_[0]);
}
sub set_perms { chmod((shift), "$dir/".(shift)) or croak $! }
sub make_symlink { symlink "$dir/".(shift), "$dir/".(shift) or croak $! }


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
        gid   => { group => [ 0      ] },
        gname => { group => [ 'root' ] },
        bad_gname => { group => [ '%%SSKK¤¤' ] },
        bad_gid   => { group => [ 999999999  ] },

        # testing optional group resolution
        opt_gid       => { group => [ '(0)'         ] },
        opt_gname     => { group => [ '(root)'      ] },
        opt_bad_gname => { group => [ '(%%SSKK¤¤)'  ] },
        opt_bad_gid   => { group => [ '(999999999)' ] },

        several_groups => { group => [ 0, "($gname)" ,0 ] },
        several_groups_required => { group => [ 0, $gname, 0 ] },
        several_groups_mixture => { group => [ '(%%SSKK¤¤)', 0 ] },
    },
    ignores => [
        '\.bak$',
    ],
});


### new
{
    new_ok('Munin::Node::Service' => [ servicedir => '/service/directory' ]);

    my $services = Munin::Node::Service->new();
    ok(exists $services->{servicedir}, 'servicedir key gets a default');
}


### is_a_runnable_service
{
    local $dir = tempdir(CLEANUP => 1);

    my $services = Munin::Node::Service->new(servicedir => $dir);

    ok(! $services->is_a_runnable_service('good'), 'file does not exist');

    {
        my $name = 'good';
        touch $name;
        ok($services->is_a_runnable_service($name), 'Valid if executable');
    }
    {
        my $name = 'notexec';
        touch $name;
        set_perms 0600, $name;
        ok(! $services->is_a_runnable_service($name), 'Not valid if not executable');
    }
    {
        my $name = '.hidden';
        touch $name;
        ok(! $services->is_a_runnable_service($name), 'Ignored if a dot-file');
    }
    {
        my $name = 'configfile.conf';
        touch $name;
        ok(! $services->is_a_runnable_service($name), 'Ignored if a config file');
    }
    {
        my $name = 'directory';
        mkdir "$dir/$name";
        ok(! $services->is_a_runnable_service($name), 'Ignored if a directory');
    }
    {
        my $name = 'linky';
        make_symlink 'good', $name;
        ok($services->is_a_runnable_service($name), 'Symlinks are ok');
    }
    {
        my $name = 'broken';
        make_symlink 'missingfile', $name;
        ok(! $services->is_a_runnable_service($name), 'But symlinks are not ok if they are broken');
    }
    {
        my $name = 'blar g';
        touch $name;
        ok(! $services->is_a_runnable_service($name), 'Not valid if it contains dodgy characters');
    }
    {
        my $name = 'blort.bak';
        touch $name;
        ok(! $services->is_a_runnable_service($name), 'Ignored files are ignored');
    }
}


### list
{
    local $dir = tempdir(CLEANUP => 1);

    my $services = Munin::Node::Service->new(servicedir => $dir);

    touch 'one';
    touch 'two';
    touch 'boo';
    touch '.notvisible';

    eq_or_diff([ sort $services->list ], [ sort qw( one two boo )], 'listed all the valid services, no more, no less');
}


### prepare_plugin_environment


# FIXME: required to avoid errors when calling export_service_environment().
# would normally be exported by prepare_plugin_environment
$ENV{MUNIN_MASTER_IP} = '';

### export_service_environment
{
  my $services = Munin::Node::Service->new(defuser => $UID);

  $services->export_service_environment('test');
  is($ENV{test_environment_variable}, 'fnord', 'Service-specific environment is exported');
}


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

    eq_or_diff([ $services->_resolve_gids('gid')   ], [ 0, "0 0" ], 'different group by gid');
    eq_or_diff([ $services->_resolve_gids('gname') ], [ 0, "0 0" ], 'different group by name');

    eval { $services->_resolve_gids('bad_gid') };
    like($@, qr/'999999999'/, 'Exception thrown if an additional group could not be resolved');

    eval { $services->_resolve_gids('bad_gname') };
    like($@, qr/'%%SSKK¤¤'/, 'Exception thrown if an additional group could not be resolved');

    eq_or_diff([ $services->_resolve_gids('opt_gname')     ], [ 0, "0 0" ], 'optional group by name');
    eq_or_diff([ $services->_resolve_gids('opt_bad_gname') ], [ $gid, "$gid $gid" ],   'unresolvable groups are ignored');

    eq_or_diff([ $services->_resolve_gids('opt_gid')         ], [ 0, "0 0" ], 'optional group by gid');
    eq_or_diff([ $services->_resolve_gids('opt_bad_gid') ], [ $gid, "$gid $gid" ],   'unresolvable gids are ignored');

    eq_or_diff(
        [$services->_resolve_gids('several_groups') ],
        [0, "0 0 $gid 0"],
        'several extra groups'
    );
    eq_or_diff(
        [$services->_resolve_gids('several_groups_required')],
        [0, "0 0 $gid 0"],
        'several groups, less whitespace'
    );
    eq_or_diff(
        [$services->_resolve_gids('several_groups_mixture')],
        [0, "0 0"],
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
