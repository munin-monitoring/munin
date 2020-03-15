package Munin::Node::SNMPConfig;

use strict;
use warnings;

use Net::SNMP;
use Munin::Node::Configure::HostEnumeration;
use Munin::Node::Configure::Debug;


### SNMP Probing ###############################################################

sub new
{
    my ($class, %opts) = @_;

    my %sec_args;

    my $hosts    = $opts{hosts};
    die "No host list specified\n" unless scalar @$hosts;

    my $version  = $opts{version} || '2c';
    my $port     = $opts{port}    || 161;
    my $domain   = $opts{domain}  || 'udp';

    if ($version eq '3') {
        # Privacy
        my $privpw    = $opts{privpassword};
        my $privproto = $opts{privprotocol} || 'des';

        if ($privpw) {
            $sec_args{-privpassword} = $privpw;
            $sec_args{-privprotocol} = $privproto;
            DEBUG('Enabled SNMPv3 privacy');
        }

        # Authentication
        my $authpw    = $opts{authpassword} || $privpw;
        my $authproto = $opts{authprotocol} || 'md5';

        if ($authpw) {
            $sec_args{-authpassword} = $authpw;
            $sec_args{-authprotocol} = $authproto;
            DEBUG('Enabled SNMPv3 authentication');
        }

        # Username
        $sec_args{-username} = $opts{username};
    }
    else {
        # version 1 or 2c
        $sec_args{-community} = $opts{community} || 'public';
    }


    my %snmp = (
        hosts     => $hosts,
        port      => $port,
        version   => $version,
        domain    => $domain,
        sec_args  => \%sec_args,
    );

    return bless \%snmp, $class;
}


sub run_probes
{
    my ($self, $plugins) = @_;

    foreach my $host (expand_hosts(@{$self->{hosts}})) {
        $self->_probe_single_host($host, $plugins);
    }

    return;
}


# Checks each plugin in turn against the host, and make a note of
# those that are supported.
sub _probe_single_host
{
    my ($self, $host, $plugins) = @_;

    DEBUG("SNMP-probing $host");
	my ($session, $error) = Net::SNMP->session(
		-hostname  => $host,
        -port      => $self->{port},
        -version   => $self->{version},
        -domain    => $self->{domain},

        %{$self->{sec_args}},

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
            # TODO: Check whether there was a timeout?  that would indicate a
            # bad community string, or no SNMP support (either no daemon, or
            # unsupported protocol version) -- any downsides?  are there
            # devices that timeout rather than return noSuchObject?  compromise
            # would be to have a --ignore-snmp-timeouts cmdline flag.
            #
            # TODO, redux: capture and handle SNMPv3 errors.
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

    my $hostname = $session->hostname;
    my @valid_indexes;

    # First round of requirements -- check for specific OIDs.
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

    # Second round of requirements -- check for valid rows in a table.
    if ($plugin->{table}) {
        my @columns = map { $_->[0] } @{$plugin->{table}};

        DEBUG('Fetching columns: ' . join ', ', @columns);
        my $result = $session->get_entries(-columns => \@columns);
        unless ($result) {
            DEBUG('Failed to get required columns');
            return;
        }

        # sort into rows
        my $subtabs = join '|', map { quotemeta } @columns;
        my $re = qr/^($subtabs)\.(.*)/;
        my %table;

        while (my ($oid, $value) = each %$result) {
            my ($column, $index) = $oid =~ /$re/;
            DEBUG("Row '$index', column '$column', value '$value'");
            $table{$index}->{$column} = $value;
        }

        DEBUG('Checking for valid rows');

        # work out what rows are invalid
        # can shortcut unless it's a double-wildcard plugin
        while (my ($index, $row) = each %table) {
            if (_snmp_check_row($index, $row, @{$plugin->{table}})) {
                if ($plugin->is_wildcard) {
                    DEBUG(qq{Adding row '$index' to the list of valid indexes});
                    push @valid_indexes, $row->{$plugin->{index}};
                }
                else {
                    DEBUG('Table contains at least one valid row.');
                    return [ $hostname ];
                }
            }
        }

        # if we got here, there were no matching rows.
        unless ($plugin->is_wildcard and @valid_indexes) {
            DEBUG('No valid rows found');
            return;
        }
    }

    # return list of arrayrefs, one for each good suggestion
    return $plugin->is_wildcard ? map { [ $hostname, $_ ] } @valid_indexes
                                : [ $hostname ];
}


# returns true if the row in a table fulfils all the requirements, false
# otherwise.
sub _snmp_check_row
{
    my ($index, $row, @requirements) = @_;

    foreach my $req (@requirements) {
        my ($oid, $regex) = @$req;

        unless (defined $row->{$oid}) {
            DEBUG(qq{Row '$index' doesn't have an entry for column '$oid'});
            return 0;
        }

        if ($regex and $row->{$oid} !~ /$regex/) {
            DEBUG(qq{Row '$index', column '$oid'.  Value '$row->{$oid}' doesn't match '$regex'});
            return 0;
        }
    }

    DEBUG(qq{Row '$index' is valid});
    return 1;
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

=item B<new(%arguments)>

Constructor.  Valid arguments are:

=over 4

=item hosts

The list of hosts to scan, in a format understood by
L<Munin::Node::Configure::HostEnumeration>.  Required.

=item port

Port to connect to.  Default is 161.

=item version

The SNMP version to use.  Default is '2c'.

=item community

The community string to use for SNMP version 1 or 2c.  Default is 'public'.

=item domain

The Transport Domain to use for exchanging SNMP messages. The default
is UDP/IPv4. Possible values: 'udp', 'udp4', 'udp/ipv4'; 'udp6',
'udp/ipv6'; 'tcp', 'tcp4', 'tcp/ipv4'; 'tcp6', 'tcp/ipv6'.

=item username

The SNMPv3 username to use.

=item authpassword

SNMPv3 Authentication password.  Optional when encryption is also enabled, in
which case defaults to the privacy password (C<privpassword>).  The
password is sent encrypted (one way hash) over the network.

=item authprotocol

SNMPv3 Authentication protocol.  One of 'md5' or 'sha' (HMAC-MD5-96, RFC1321
and SHA-1/HMAC-SHA-96, NIST FIPS PIB 180, RFC2264).  The default is 'md5'.

=item privpassword

SNMPv3 Privacy password to enable encryption.  An empty ('') password is
considered as no password and will not enable encryption.

Privacy requires a v3privprotocol as well as a v3authprotocol and a
v3authpassword, but all of these are defaulted (to 'des', 'md5', and the
v3privpassword value, respectively) and may therefore be left unspecified.

=item privprotocol

If the v3privpassword is set this setting controls what kind of encryption is
used to achieve privacy in the session.  Only the very weak 'des' encryption
method is supported officially.  The default is 'des'.

The implementing perl module (L<Net::SNMP>) also supports '3des' (CBC-3DES-EDE
aka Triple-DES, NIST FIPS 46-3) as specified in IETF
draft-reeder-snmpv3-usm-3desede.  Whether or not this works with any particular
device, we do not know.

=back

=item B<run_probes($plugins)>

Connects to each host in turn, and checks which plugins it supports, based on
the OIDs they reported during snmpconf.  If all the requirements are
fulfilled, it will added to the corresponding plugin's suggestions list.

$plugins should be a Munin::Node::Configure::PluginList object.

=back

=cut
# vim: ts=4 : sw=4 : expandtab
