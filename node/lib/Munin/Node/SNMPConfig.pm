package Munin::Node::SNMPConfig;

use strict;
use warnings;

use Net::SNMP;
use Socket;

use Data::Dumper;

use Exporter ();
our @ISA = qw/Exporter/;
our @EXPORT = qw/expand_hosts snmp_probe_host/;


use Munin::Common::Defaults;
use Munin::Node::Config;

my $config = Munin::Node::Config->instance();


### Network address manipulation ###############################################

# converts an IP address (char* in network byte order, as returned by 
# gethostbyname, et al) and optional netmask into the corresponding
# range of IPs.
#
# If you haven't guessed, this is IPv4 only.
sub _hosts_in_net
{
	my ($addr, $mask) = @_;

	# This won't work with a netmask of 0.  then again, no-one wants to
	# SNMP-scan the whole internet, even if they think they do.
	$mask ||= 32;

	die "Invalid netmask: $mask\n"
		unless ($mask =~ /^\d+$/ and $mask <= 32);

	my $net = unpack('N', $addr);  # ntohl()

	# Evil maths cribbed from nmap
	my $low  = $net & (0 - (1 << (32 - $mask)));
	my $high = $net | ((1 << (32 - $mask)) - 1);

	return map { inet_ntoa(pack 'N', $_) } $low .. $high;
}


# Resolves a hostname or IP, and returns the address as a bitstring in
# network byte order.
sub _resolve
{
	my ($host) = @_;

	my ($name, $aliases, $addrtype, $length, @addrs)
		= gethostbyname($host);

	die "Unable to resolve $host\n" unless $name;

	if (scalar @addrs > 1) {
		warn sprintf "Hostname %s resolves to %u IPs.  Using %s\n",
		                   $host,
		                   scalar(@addrs),
		                   inet_ntoa($addrs[0]);
	}
	warn sprintf "# Resolved %s to %s\n", $host, inet_ntoa($addrs[0])
		if $config->{DEBUG};

	return $addrs[0];
}


# converts a list of hostnames, IPs or CIDR ranges to the 
# corresponding IPs.
sub expand_hosts
{
	my (@unexpanded) = @_;
	my @hosts;

	foreach my $item (@unexpanded) {
		warn "Processing $item\n" if $config->{DEBUG};

		my ($host, $mask) = split '/', $item, 2;
		$host = _resolve($host);
		push @hosts, _hosts_in_net($host, $mask);
	}
	return @hosts;
}


### SNMP Probing ###############################################################

sub snmp_probe_host
{
	my ($host, $plugins) = @_;

	print "# SNMP-probing $host\n" if $config->{DEBUG};

	my ($session, $error) = Net::SNMP->session(
			-hostname  => $host,
			-community => $config->{snmp_community},
			-port      => $config->{snmp_port},
			-version   => $config->{snmp_version},
	);

	unless ($session) {
		print "# Dropping host '$host': $error\n";
		return 0;
	}

	# Disable ASN1 translation.  FIXME: is this required?  why?
	$session->translate(0);

	foreach my $plugin (values %$plugins) {
		print "# Running autoconf on $plugin->{name} for $host...\n"
			if $config->{DEBUG};

		my $auto = _snmp_autoconf_plugin($plugin, $session);

		unless ($auto) {
			print "# Host '$host' doesn't support $plugin->{name}\n"
				if $config->{DEBUG};
			next;
		}

		# FIXME: this should be done back in munin-node-configure itself
		# though will require more flexibility since some SNMP plugins have
		# two wildcard parameters
		if ($plugin->{wild}) {
			# adds a link for each id in @$auto
		}
		else {
			# adds a regular link
		}
	}

	print "# Finished probing $host\n" if $config->{DEBUG};

	$session->close;
	return 1;
}


sub _snmp_autoconf_plugin
{
	my ($plugin, $session) = @_;

	my $num = 1;  # Number of items to autoconf
	my $indexes;  # Index base

	# First round of requirements
	if ($plugin->{req}) {
		print "# Checking requirements...\n" if $config->{DEBUG};
		foreach my $req (@{$plugin->{req}}) {
			if ($req->[0] =~ /\.$/) {
				print "# Delaying testing of $req->[0], as we need the indexes first.\n"
					if $config->{DEBUG};
				next;
			}

			my $snmp_val = _snmp_get_single($session, $req->[0]);

			if (!defined $snmp_val or $snmp_val !~ /$req->[1]/) {
				print "# Nope. Duh.\n" if $config->{DEBUG};
				return;
			}
		}
	}

	# We need the number of "things" to autoconf
	if ($plugin->{num}) {
		$num = _snmp_get_single($session, $plugin->{num});
		return unless $num;
	}
	print "# $num items to autoconf\n" if $config->{DEBUG};

	# Then the index base
	if ($plugin->{ind}) {
		$indexes = _snmp_get_index($session, $plugin->{ind}, $num);
		return unless $indexes;
	}
	else {
		$indexes->{0} = 1;
	}
	print "# Got indexes: ", join (',', keys (%{$indexes})), "\n" if $config->{DEBUG};

	return unless scalar keys %{$indexes};

	# Second round of requirements (now that we have the indexes)
	if (defined $plugin->{req}) {
		print "# Checking requirements...\n" if $config->{DEBUG};
		foreach my $req (@{$plugin->{req}}) {
			if ($req->[0] !~ /\.$/) {
				print "# Already tested of $req->[0], before we got hold of the indexes.\n" if $config->{DEBUG};
				next;
			}

			foreach my $key (keys %$indexes) {
				my $snmp_val = _snmp_get_single($session, $req->[0] . $key);
				if (!defined $snmp_val or $snmp_val !~ /$req->[1]/) {
					print "# Nope. Deleting $key from possible solutions.\n" if $config->{DEBUG};
					delete $indexes->{$key}; # Disable
				}
			}
		}
	}

	my @tmparr = sort keys %$indexes;
	return \@tmparr;
}


# Retrieves the value for the given OID from the session
sub _snmp_get_single
{
	my $session = shift;
	my $oid     = shift;

	my $response = $session->get_request($oid);

	unless (defined $response) {
		print "# Request failed for oid '$oid'"
			if $config->{DEBUG};
		return;
	}

	print "# Fetched value \"$response->{$oid}\"\n"
		if $config->{DEBUG};

	return $response->{$oid};
}


# takes an index 
sub _snmp_get_index
{
	my ($session, $oid, $num) = @_;

	my $ret   = $oid . "0";
	my %rhash;

	my $response;

	$num++; # Avaya switch b0rkenness...

	print "# Checking for $ret\n" if $config->{DEBUG};
	$response = $session->get_request($ret);

	foreach my $ii (0 .. $num) {
		if ($ii or !defined $response or $session->error_status) {
			print "# Checking for sibling of $ret\n" if $config->{DEBUG};
			$response = $session->get_next_request($ret);
		}
		if (!$response or $session->error_status) {
			return;
		}
		my @keys = keys %$response;
		$ret = $keys[0];
		last unless ($ret =~ /^$oid\d+$/);

		print "# Index $ii: ", join ('|', @keys), "\n" if $config->{DEBUG};

		$rhash{$response->{$ret}} = 1;
	}
	return \%rhash;
}


1;


__END__


### FIXME: not used?
sub interfaces
{
	my $name = shift;
	my %interfaces = ();
	my $num;
	my $ifNumber     = "1.3.6.1.2.1.2.1.0";
	my $ifEntryIndex = "1.3.6.1.2.1.2.2.1.1"; # dot something
	my $ifEntryType  = "1.3.6.1.2.1.2.2.1.3"; # dot something
	my $ifEntrySpeed = "1.3.6.1.2.1.2.2.1.5"; # dot something

	print "# System name: ", $name, "\n" if $config->{DEBUG};

	if (!defined ($response = $session->get_request($ifNumber)) or
			$session->error_status)
	{
		die "Croaking: " . $session->error();
	}

	$num = $response->{$ifNumber} +1; # Add one because of bogus switch entries
	print "# Number of interfaces: ", $num, "\n" if $config->{DEBUG};

	my $ret = $ifEntryIndex . ".0";

	for (my $i = 0; $i < $num;)
	{
		if ($i == 0)
		{
			$response = $session->get_request($ret);
		}
		if ($i or !defined $response or $session->error_status)
		{
			$response = $session->get_next_request($ret);
		}
		if (!$response or $session->error_status)
		{
			die "Croaking: ", $session->error();
		}
		my @keys = keys %$response;
		$ret = $keys[0];
		last unless ($ret =~ /^$ifEntryIndex\.\d+$/);
		print "# Index $i: ", join ('|', @keys), "\n" if $config->{DEBUG};
		$interfaces{$response->{$ret}} = 1;
		$i++;
	}

	foreach my $key (keys %interfaces)
	{
		$response = $session->get_request($ifEntrySpeed . "." . $key);
		if (!$response or $session->error_status)
		{
			die "Croaking: ", $session->error();
		}
		my @keys = keys %$response;
		print "# Speed $key: ", join ('|', @keys), ": ", $response->{$keys[0]}, "\n" if $config->{DEBUG};
		if ($response->{$keys[0]} == 0)
		{
			delete $interfaces{$key};
		}
	}

	foreach my $key (keys %interfaces)
	{
		$response = $session->get_request($ifEntryType . "." . $key);
		if (!$response or $session->error_status)
		{
			die "Croaking: ", $session->error();
		}
		my @keys = keys %$response;
		print "# Type  $key: ", join ('|', @keys), ": ", $response->{$keys[0]}, "\n" if $config->{DEBUG};
		if ($response->{$keys[0]} != 6)
		{
			delete $interfaces{$key};
		}
	}

	foreach my $key (sort keys %interfaces)
	{
		print "snmp_${name}_if_$key\n";
	}
}


=head1 NAME

Munin::Node::SNMPConfig - FIX


=head1 SYNOPSIS

  @hosts = ('switch1', 'host1/24,10.0.0.60/30');

  foreach my $host (expand_hosts(@hosts)) {
    snmp_probe_host($host, $plugins);
  }


=head1 SUBROUTINES

=over

=item B<expand_hosts>

  @expanded = expand_hosts(@list);

Takes a list 
and returns the IPs (in dotted-quad format).

Items can be specified as a hostname or dotted-quad IP, either with or
without a netmask, or as a comma-separated list of the above.

Currently only IPv4 addresses are supported.


=item B<snmp_probe_host>

  snmp_probe_host($host, $plugins);

Works out what plugins $host supports, based on whether the OIDs required by
the plugin are supported by the device.


=back

=cut

