package Munin::Node::SNMPConfig;

# $Id$

use strict;
use warnings;

use Net::SNMP;
use Socket;

use Data::Dumper;

use Exporter ();
our @ISA = qw/Exporter/;
our @EXPORT = qw/expand_hosts snmp_probe_host/;

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

	my @ret;

	# This won't work with a netmask of 0.  then again, no-one wants to
	# SNMP-scan the whole internet, even if they think they do.
	$mask ||= 32;

	die "Invalid netmask: $mask\n"
		unless ($mask =~ /^\d+$/ and $mask <= 32);

	my $net = unpack('N', $addr);  # ntohl()

	# Evil maths courtesy of nmap's TargetGroup.cc
	my $low  = $net & (0 - (1 << (32 - $mask)));
	my $high = $net | ((1 << (32 - $mask)) - 1);

	# turns out the .. operator can't handle unsigned integers
	for (my $ip = $low; $ip <= $high; $ip++) {
		push @ret, inet_ntoa(pack 'N', $ip);
	}
	return @ret;
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
    DEBUG(sprintf "Resolved %s to %s", $host, inet_ntoa($addrs[0]));

	return $addrs[0];
}


# converts a list of hostnames, IPs or CIDR ranges to the corresponding IPs.
sub expand_hosts
{
	my (@unexpanded) = @_;
	my @hosts;

	foreach my $item (@unexpanded) {
        DEBUG("Processing $item");
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

    DEBUG("SNMP-probing $host");
	my ($session, $error) = Net::SNMP->session(
		-hostname  => $host,
		-community => $config->{snmp_community},
		-port      => $config->{snmp_port},
		-version   => $config->{snmp_version},
		# Disable munging of responses into "human readable" form
		-translate => 0,
	);
	unless ($session) {
        DEBUG("Dropping host '$host': $error");
		return 0;
	}

	foreach my $plugin ($plugins->list) {
        DEBUG("Running autoconf on $plugin->{name} for $host");
		if (my @suggestions = _snmp_autoconf_plugin($plugin, $session)) {
			$plugin->{default} = 'yes';
            $plugin->add_suggestions(@suggestions);
		}
		else {
            DEBUG("Host '$host' doesn't support $plugin->{name}");
		}
	}

    DEBUG("Finished probing $host");
	$session->close;

	return 1;
}


# If the SNMP agent supports the plugin, returns a list of arrayrefs, each of
# which represents a valid plugin instance.
sub _snmp_autoconf_plugin
{
	my ($plugin, $session) = @_;

	my (@indexes, @valid_indexes);

	# First round of requirements
	if ($plugin->{require_oid}) {
        DEBUG("Checking required OIDs");
		foreach my $req (@{$plugin->{require_oid}}) {
			my ($oid, $filter) = @$req;
			unless (_snmp_check_require($session, $oid, $filter)) {
                DEBUG("Missing requirement.");
				return;
			}
		}
	}

	# Fetch the list of indices
	if ($plugin->{number}) {
		my $num = _snmp_get_single($session, $plugin->{number});
		return unless $num;
		@indexes = (1 .. $num);
	}
	elsif ($plugin->{index}) {
		my $result = $session->get_entries(-columns => [ $plugin->{index} ]);
		unless ($result) {
            DEBUG("Failed to fetch index.");
			return;
		}
		@indexes = values %$result;
	}
    DEBUG(sprintf "Got indexes: %s", join(', ', @indexes));

	# Second round of requirements (now that we have the indexes)
	if ($plugin->{required_root}) {
        DEBUG("Removing invalid indices");
		foreach my $req (@{$plugin->{required_root}}) {
			my ($oid, $filter) = @$req;
			foreach my $index (@indexes) {
				if (_snmp_check_require($session, $oid . $index, $filter)) {
					push @valid_indexes, $index;
				}
				else {
                    DEBUG("No. Removing $index from possible solutions.");
				}
			}
		}

		unless (scalar @valid_indexes) {
            DEBUG("No indices left.  Dropping plugin.");
			return;
		}
	}
	else {
		# No further filters means they're all good by default
		@valid_indexes = @indexes;
	}

	# return list of arrayrefs, one for each good suggestion
	my $hostname = $session->hostname;
	return $plugin->is_wildcard ? map { [ $hostname, $_ ] } @valid_indexes
	                            : [ $hostname ];
}


# Returns true if the SNMP agent supports the 'require', false otherwise.
sub _snmp_check_require
{
	my ($session, $oid, $filter) = @_;

	my $value = _snmp_get_single($session, $oid);
	return !(!defined $value or ($filter and $value !~ /$filter/));
}


# Retrieves the value for the given OID from the session
sub _snmp_get_single
{
	my ($session, $oid) = @_;

	my $response = $session->get_request($oid);

	unless (defined $response and $session->error_status == 0) {
        DEBUG("Request failed for oid '$oid'");
		return;
	}

    DEBUG("Fetched $oid -> '$response->{$oid}'");
	return $response->{$oid};
}


# Prints out a debugging message
sub DEBUG { print '# ', @_, "\n" if $config->{DEBUG}; }


1;


__END__

=head1 NAME

Munin::Node::SNMPConfig - Subroutines providing munin-node-configure's SNMP
scanning capabilities.


=head1 SYNOPSIS

  @hosts = ('switch1', 'host1/24,10.0.0.60/30');

  foreach my $host (expand_hosts(@hosts)) {
    snmp_probe_host($host, $plugins);
  }


=head1 SUBROUTINES

=over

=item B<expand_hosts>

  @expanded = expand_hosts(@list);

Takes a list of hosts, and returns the corresponding IPs in dotted-quad form.

Items can be specified as a hostname or dotted-quad IP, either with or
without a netmask, or as a comma-separated list of the above.

Currently only IPv4 addresses are supported.


=item B<snmp_probe_host>

  snmp_probe_host($host, $plugins);

Works out what plugins $host supports, based on whether the OIDs required by
the plugin are supported by the device.


=back

=cut
# vim: ts=4 : sw=4 : expandtab
