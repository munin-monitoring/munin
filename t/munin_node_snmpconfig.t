use strict;
use warnings;

use Test::More tests => 9;

use_ok 'Munin::Node::SNMPConfig';


### sub new
{
	my @hosts = qw(
		localhost
		10.0.0.1
		router
	);

	# defaults
	is_deeply(
		Munin::Node::SNMPConfig->new(
			hosts      => \@hosts,
		),
		{
			hosts     => \@hosts,
			port      => '161',
			version   => '2c',
			domain    => 'udp',
			sec_args  => {
				-community => 'public',
			},
		},
		'Defaults are correct',
	);

	# version 1
	is_deeply(
		Munin::Node::SNMPConfig->new(
			hosts      => \@hosts,
			version    => '1',
			port       => '162',
			domain     => 'udp',
			community  => 'fnord',
		),
		{
			hosts     => \@hosts,
			port      => '162',
			domain    => 'udp',
			version   => '1',
			sec_args  => {
				-community => 'fnord',
			},
		},
		'SNMP v1',
	);

	# version 2
	is_deeply(
		Munin::Node::SNMPConfig->new(
			hosts      => \@hosts,
			version    => '2c',
			port       => '161',
			domain     => 'udp',
			community  => 'fnord',
		),
		{
			hosts     => \@hosts,
			port      => '161',
			domain    => 'udp',
			version   => '2c',
			sec_args  => {
				-community => 'fnord',
			},
		},
		'SNMP v2',
	);

	# version 3 (noAuthNoPriv)
	is_deeply(
		Munin::Node::SNMPConfig->new(
			hosts      => \@hosts,
			version    => '3',
			port       => '162',
			domain     => 'udp',
			username   => 'jeff',
		),
		{
			hosts     => \@hosts,
			port      => '162',
			domain    => 'udp',
			version   => '3',
			sec_args  => {
				-username => 'jeff',
			},
		},
		'SNMP v3, noAuthNoPriv',
	);

	# version 3 (authNoPriv)
	is_deeply(
		Munin::Node::SNMPConfig->new(
			hosts      => \@hosts,
			version    => '3',
			port       => '162',
			domain     => 'udp',
			username   => 'jeff',
			authpassword => 'swordfish',
		),
		{
			hosts     => \@hosts,
			port      => '162',
			domain    => 'udp',
			version   => '3',
			sec_args  => {
				-username => 'jeff',
				-authpassword => 'swordfish',
				-authprotocol => 'md5',
			},
		},
		'SNMP v3, authNoPriv, protocol defaults to MD5',
	);
	is_deeply(
		Munin::Node::SNMPConfig->new(
			hosts      => \@hosts,
			version    => '3',
			port       => '162',
			domain     => 'udp',
			username   => 'jeff',
			authpassword => 'swordfish',
			authprotocol => 'sha',
		),
		{
			hosts     => \@hosts,
			port      => '162',
			domain    => 'udp',
			version   => '3',
			sec_args  => {
				-username => 'jeff',
				-authpassword => 'swordfish',
				-authprotocol => 'sha',
			},
		},
		'SNMP v3, authNoPriv, set protocol to SHA1',
	);

	# version 3 (authPriv, same auth and priv keys)
	is_deeply(
		Munin::Node::SNMPConfig->new(
			hosts      => \@hosts,
			version    => '3',
			port       => '162',
			domain     => 'udp',
			username   => 'jeff',
			privpassword => 'swordfish',
		),
		{
			hosts     => \@hosts,
			port      => '162',
			domain    => 'udp',
			version   => '3',
			sec_args  => {
				-username => 'jeff',
				-authpassword => 'swordfish',
				-authprotocol => 'md5',
				-privpassword => 'swordfish',
				-privprotocol => 'des',
			},
		},
		'version 3 (authPriv, same auth and priv keys)',
	);

	# version 3 (authPriv, different auth and priv keys)
	is_deeply(
		Munin::Node::SNMPConfig->new(
			hosts      => \@hosts,
			version    => '3',
			port       => '162',
			domain     => 'udp',
			username   => 'jeff',
			authpassword => 'swordfish',
			privpassword => 'hedgerows',
			privprotocol => 'aes',
		),
		{
			hosts     => \@hosts,
			port      => '162',
			domain    => 'udp',
			version   => '3',
			sec_args  => {
				-username => 'jeff',
				-authpassword => 'swordfish',
				-authprotocol => 'md5',
				-privpassword => 'hedgerows',
				-privprotocol => 'aes',
			},
		},
		'version 3 (authPriv, different auth and priv keys)',
	);
}


### sub _probe_single_host


### sub _snmp_autoconf_plugin


### sub _snmp_check_row


### sub _snmp_check_require


### sub _snmp_get_single



