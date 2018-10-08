use warnings;
use strict;

use Test::More tests => 25;

use_ok('Munin::Plugin::SNMP');


### config_session
{
	my @tests = (
		[
			'/usr/share/munin/plugins/snmp_prentice_mchoan',
			[ 'prentice', 161, 2, 'mchoan' ],
			'Full path'
		],
		[
			'snmp_kenneth_mchoan',
			[ 'kenneth', 161, 2, 'mchoan' ],
			'Relative path',
		],
		[
			'snmp_fiona_urvill_3',
			[ 'fiona', 161, 2, 'urvill_3' ],
			'Different tail'
		],
		[
			'snmpv3_ash_watt',
			[ 'ash', 161, 3, 'watt' ],
			'SNMPv3'
		],
		[
			'snmp_hamish:162_mchoan',
			[ 'hamish', 162, 2, 'mchoan' ],
			'Port specified'
		],
	 	[
			'snmp_verity.walker_mchoan',
			[ 'verity.walker', 161, 2, 'mchoan' ],
			'FQDN host'
		],
	);
	while (my $test = shift @tests) {
		my ($zero, $expected, $message) = @$test;
		local $0 = $zero;
		my @got = Munin::Plugin::SNMP->config_session();
		is_deeply(\@got, $expected, $message);
	}

	# unable to get hostname
	{
		local $0 = 'fergus_urvill';
		undef $@;
		eval { Munin::Plugin::SNMP->config_session() };
		ok(defined($@),"threw an error when hostname couldn't be found")
			or diag($@);
	}

	# overriding from the environment
	{
		local $ENV{host} = 'araucaria';
		local $0 = 'snmp_john_graham',
		is_deeply(
			[ Munin::Plugin::SNMP->config_session() ],
			[ 'araucaria', 161, 2, 'graham' ],
			'host set in environment'
		);
	}
	{
		local $ENV{port} = '162';
		local $0 = 'snmp_john_graham',
		is_deeply(
			[ Munin::Plugin::SNMP->config_session() ],
			[ 'john', 162, 2, 'graham' ],
			'port set in environment'
		);
	}
	{
		local $ENV{version} = '3';
		local $0 = 'snmp_john_graham',
		is_deeply(
			[ Munin::Plugin::SNMP->config_session() ],
			[ 'john', 161, 3, 'graham' ],
			'version set in v2 plugin environment'
		);
	}
	{
		local $ENV{version} = '2';
		local $0 = 'snmpv3_john_graham',
		is_deeply(
			[ Munin::Plugin::SNMP->config_session() ],
			[ 'john', 161, 2, 'graham' ],
			'version 2 set in v3 plugin environment'
		);
	}
}


### session
{
	# defaults for config_session to return (hostname, port, version, tail)
	my @DEFAULT_CONFIG = qw( localhost 161 2 if_1 );

	# catch the arguments passed to Net::SNMP->session
	our %NET_SNMP_ARGUMENTS;

	no warnings;
	local *Munin::Plugin::SNMP::config_session = sub { return @DEFAULT_CONFIG };
	local *Net::SNMP::session = sub { shift; %NET_SNMP_ARGUMENTS = @_ };
	use warnings;

	### start the tests proper

	# version 1
	{
		local $DEFAULT_CONFIG[2] = 1;
		Munin::Plugin::SNMP->session();
		is_deeply(
			\%NET_SNMP_ARGUMENTS,
			{
				-hostname  => 'localhost',
				-port      => '161',
				-version   => '1',
				-community => 'public',
			},
			'version 1 session (no community string in environment)',
		);
	}
	{
		local $DEFAULT_CONFIG[2] = 1;
		local $ENV{community} = 's33kr1t';
		Munin::Plugin::SNMP->session();
		is_deeply(
			\%NET_SNMP_ARGUMENTS,
			{
				-hostname  => 'localhost',
				-port      => '161',
				-version   => '1',
				-community => 's33kr1t',
			},
			'version 1 session (with community string in environment)',
		);
	}

	# version 2
	{
		Munin::Plugin::SNMP->session();
		is_deeply(
			\%NET_SNMP_ARGUMENTS,
			{
				-hostname  => 'localhost',
				-port      => '161',
				-version   => '2',
				-community => 'public',
			},
			'version 2 session (no community string in environment)',
		);
	}
	{
		local $ENV{community} = 's33kr1t';
		Munin::Plugin::SNMP->session();
		is_deeply(
			\%NET_SNMP_ARGUMENTS,
			{
				-hostname  => 'localhost',
				-port      => '161',
				-version   => '2',
				-community => 's33kr1t',
			},
			'version 2 session (with community string in environment)',
		);
	}

	# version 3 (noAuthNoPriv)
	{
		local $DEFAULT_CONFIG[2] = 3;
		local $ENV{v3username} = 'jeff';
		Munin::Plugin::SNMP->session();
		is_deeply(
			\%NET_SNMP_ARGUMENTS,
			{
				-hostname  => 'localhost',
				-port      => '161',
				-version   => '3',
				-username  => 'jeff',
			},
			'version 3 session, noAuthNoPriv',
		);
	}

	# version 3 (authNoPriv)
	{
		local $DEFAULT_CONFIG[2] = 3;

		local $ENV{v3username}     = 'jeff';
		local $ENV{v3authpassword} = 'swordfish';

		Munin::Plugin::SNMP->session();
		is_deeply(
			\%NET_SNMP_ARGUMENTS,
			{
				-hostname  => 'localhost',
				-port      => '161',
				-version   => '3',
				-username  => 'jeff',
				-authpassword => 'swordfish',
				-authprotocol => 'md5',
			},
			'version 3 session, authNoPriv, protocol defaults to MD5',
		);
	}
	{
		local $DEFAULT_CONFIG[2] = 3;

		local $ENV{v3username}     = 'jeff';
		local $ENV{v3authpassword} = 'swordfish';
		local $ENV{v3authprotocol} = 'sha';

		Munin::Plugin::SNMP->session();
		is_deeply(
			\%NET_SNMP_ARGUMENTS,
			{
				-hostname  => 'localhost',
				-port      => '161',
				-version   => '3',
				-username  => 'jeff',
				-authpassword => 'swordfish',
				-authprotocol => 'sha',
			},
			'version 3 session, authNoPriv, set protocol to SHA1',
		);
	}

	# version 3 (authPriv, same auth and priv keys)
	{
		local $DEFAULT_CONFIG[2] = 3;

		local $ENV{v3username}     = 'jeff';
		local $ENV{v3privpassword} = 'hedgerows';

		Munin::Plugin::SNMP->session();
		is_deeply(
			\%NET_SNMP_ARGUMENTS,
			{
				-hostname  => 'localhost',
				-port      => '161',
				-version   => '3',
				-username  => 'jeff',
				-authpassword => 'hedgerows',
				-authprotocol => 'md5',
				-privpassword => 'hedgerows',
				-privprotocol => 'des',
			},
			'version 3 (authPriv, same auth and priv keys)',
		);
	}

	# version 3 (authPriv, different auth and priv keys)
	{
		local $DEFAULT_CONFIG[2] = 3;

		local $ENV{v3username}     = 'jeff';
		local $ENV{v3authpassword} = 'swordfish';
		local $ENV{v3privpassword} = 'hedgerows';

		Munin::Plugin::SNMP->session();
		is_deeply(
			\%NET_SNMP_ARGUMENTS,
			{
				-hostname  => 'localhost',
				-port      => '161',
				-version   => '3',
				-username  => 'jeff',
				-authpassword => 'swordfish',
				-authprotocol => 'md5',
				-privpassword => 'hedgerows',
				-privprotocol => 'des',
			},
			'version 3 (authPriv, different auth and priv keys)',
		);
	}

	# user-defined options
	{
		Munin::Plugin::SNMP->session(-retries => 10);
		is_deeply(
			\%NET_SNMP_ARGUMENTS,
			{
				-hostname  => 'localhost',
				-port      => '161',
				-version   => '2',
				-community => 'public',
				-retries   => '10'
			},
			'Arguments to session() are propagated to Net::SNMP',
		);
	}

	# timeout
	{
		local $ENV{timeout} = 30;
		Munin::Plugin::SNMP->session();
		is_deeply(
			\%NET_SNMP_ARGUMENTS,
			{
				-hostname  => 'localhost',
				-port      => '161',
				-version   => '2',
				-community => 'public',
				-timeout   => '30'
			},
			'Arguments to session() are propagated to Net::SNMP',
		);
	}

	# unknown SNMP version
	{
		local $DEFAULT_CONFIG[2] = 17;
		eval { Munin::Plugin::SNMP->session(); };
		like($@, qr/./, 'Unknown SNMP version causes an exception.');
	}

	# Unable to create session
	{
		no warnings;
		local *Net::SNMP::session = sub { return (undef, 'fake error') };
		use warnings;
		eval { Munin::Plugin::SNMP->session(); };
		like($@, qr/fake error/, 'Error creating SNMP session causes an exception.');
	}
}

