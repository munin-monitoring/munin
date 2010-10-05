package Munin::Node::SNMPConfig;

# $Id: SNMPConfig.pm 2619 2009-10-20 17:02:35Z ligne $

use strict;
use warnings;

use Net::SNMP;
use Munin::Node::Configure::HostEnumeration;
use Munin::Node::Configure::Debug;


### SNMP Probing ###############################################################

sub new
{
    my ($class, %opts) = @_;

    my $snmpver  = delete $opts{version}   || '2c';
    my $snmpcomm = delete $opts{community} || 'public';
    my $snmpport = delete $opts{port}      || 161;

    my %snmp = (
        community => $snmpcomm,
        port      => $snmpport,
        version   => $snmpver,

        %opts,
    );

    return bless \%snmp, $class;
}


sub run_probes
{
    my ($self, $plugins) = @_;

    # FIXME: should preserve hostnames as much as possible.
    foreach my $host (expand_hosts(@{$self->{hosts}})) {
        $self->_probe_single_host($host, $plugins);
    }

    return;
}


sub _probe_single_host
{
    my ($self, $host, $plugins) = @_;

    DEBUG("SNMP-probing $host");
	my ($session, $error) = Net::SNMP->session(
		-hostname  => $host,
        -community => $self->{community},
        -port      => $self->{port},
        -version   => $self->{version},
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


1;


__END__

=head1 NAME

Munin::Node::SNMPConfig - Subroutines providing munin-node-configure's SNMP
scanning capabilities.


=head1 SYNOPSIS

  my $snmp = Munin::Node::SNMPConfig->new(
        community => 'secret',
        version   => 1,
  );
  $snmp->probe_hosts(\%plugins);

=head1 SUBROUTINES

=over

=item B<new>

Constructor.

Valid arguments are 'community', 'port', 'version' and 'hosts'.  All are
optional, and default to 'public', 161, '2c' and an empty host-list (though
obviously not providing any hosts is somewhat pointless).

The host list should be in a format understood by
Munin::Node::Configure::HostEnumeration


=item B<run_probes($plugins)>

Connects to each host in turn, and checks which plugins it supports, based on
the OIDs they reported during snmpconf.  If all the requirements are
fulfilled, it will added to the corresponding plugin's suggestions list.

$plugins should be a Munin::Node::Configure::PluginList object.

=back

=cut
# vim: ts=4 : sw=4 : expandtab
