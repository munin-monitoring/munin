use warnings;
use strict;

use Test::More tests => 15;

use Socket;

use_ok('Munin::Node::SNMPConfig');

# use the 192.0.2.0/24 block, since that's what the 
my @slash_24 = map { "192.168.2.$_" } 0 .. 255;

### resolve
{
	my @tests = (
		[ 'munin.projects.linpro.no', 'Resolve IPv4 hostname' ],
		[ '127.0.0.1',                'Resolve IPv4 numeric address' ],
#		[ 'ipv6.google.com',          'Resolve IPv6 hostname' ],
#		[ '::1',                      'Resolve IPv6 numeric address' ],
	);

	while (my $test = shift @tests) {
		my ($from, $msg) = @$test;

		my $ip = eval {	Munin::Node::SNMPConfig::_resolve($from) };
		ok(!$@, "$msg - no exception");
		ok($ip, "$msg - got a value");
	}
}


### hosts_in_net
{
	my $hosts_in_net = \&Munin::Node::SNMPConfig::_hosts_in_net;
	my (@ips, @expected);

	my $_192_168_2_123 = inet_aton('192.168.2.123');
	my $_192_168_2_1   = inet_aton('192.168.2.1');

	@ips = $hosts_in_net->($_192_168_2_123, 24);
	is_deeply(\@ips, \@slash_24, 'Class C is expanded correctly');

	@ips = $hosts_in_net->($_192_168_2_123, 32);
	@expected = ('192.168.2.123');
	is_deeply(\@ips, \@expected, 'Single IP');

	@ips = $hosts_in_net->($_192_168_2_123);
	@expected = ('192.168.2.123');
	is_deeply(\@ips, \@expected, 'No netmask');
}


# emulate its behaviour for selected, known-good values
sub _resolve
{
	my $name = shift;

	my @valid = (
		[ '192.168.2.123', 'test'    ],
		[ '192.168.2.1',   'gateway' ],
	);

	foreach my $host (@valid) {
		my ($ip, $hostname, $resolved) = @$host;

		return inet_aton($ip) if $name eq $ip
		                      or $name eq $hostname
		                      or $name eq "$hostname.example.com";
	}

	die "Unable to resolve $name: invalid test value!";
}

no warnings;
*Munin::Node::SNMPConfig::_resolve = \&_resolve;
use warnings;

### expand_hosts
{
	my @tests = (
		[ [ '192.168.2.123'                  ], [ '192.168.2.123'          ], 'Single IP',                 ],
		[ [ '192.168.2.123/24'               ], [ @slash_24,               ], 'IP-based CIDR range',       ],
		[ [ 'test'                           ], [ '192.168.2.123'          ], 'Single hostname',           ],
		[ [ 'test/24'                        ], [ @slash_24,               ], 'Hostname-based CIDR range', ],
		[ [ 'test.example.com'               ], [ '192.168.2.123'          ], 'Single FQDN',               ],
		[ [ 'test.example.com/24'            ], [ @slash_24,               ], 'FQDN-based CIDR range',     ],
		[ [ 'test.example.com/24', 'gateway' ], [ @slash_24, '192.168.2.1' ], 'Multiple specifications',   ],
	);
	
	while (my $test = shift @tests) {
		my ($hosts, $expected, $msg) = @$test;
		
		@$hosts = Munin::Node::SNMPConfig::expand_hosts(@$hosts);
		is_deeply($hosts, $expected, $msg);
	}
}


