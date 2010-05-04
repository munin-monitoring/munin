use warnings;
use strict;

use Test::More tests => 16;

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
				-port      => 161,
				-version   => 1,
				-community => 'public',
			},
			'version 1 session (no community string)',
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
				-port      => 161,
				-version   => 1,
				-community => 's33kr1t',
			},
			'version 1 session (with community string)',
		);
	}

	# version 2
	{
		Munin::Plugin::SNMP->session();
		is_deeply(
			\%NET_SNMP_ARGUMENTS,
			{
				-hostname  => 'localhost',
				-port      => 161,
				-version   => 2,
				-community => 'public',
			},
			'version 2 session (no community string)',
		);
	}
	{
		local $ENV{community} = 's33kr1t';
		Munin::Plugin::SNMP->session();
		is_deeply(
			\%NET_SNMP_ARGUMENTS,
			{
				-hostname  => 'localhost',
				-port      => 161,
				-version   => 2,
				-community => 's33kr1t',
			},
			'version 2 session (with community string)',
		);
	}

	# version 3 (noAuthNoPriv)

	# version 3 (authNoPriv)

	# version 3 (authPriv, same auth and priv keys)

	# version 3 (authPriv, different auth and priv keys)

	# user-defined options

	# timeout

}

