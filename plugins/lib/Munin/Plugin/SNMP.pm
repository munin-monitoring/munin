# -*- cperl -*-
#
# Copyright (C) 2004-2009 Dagfinn Ilmari Mannsaaker, Nicolai Langfeldt,
# Linpro AS
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; version 2 dated June,
# 1991.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA
# 02110-1301 USA.


# This Module is user documented inline, interspersed with code with
# perlpod.  The documentation for the session() function is the
# pattern.  Please maintain it in the same way.


# $Id: SNMP.pm 3558 2010-05-05 17:02:43Z ligne $

=head1 NAME

Munin::Plugin::SNMP - Net::SNMP subclass for Munin plugins

=head1 SYNOPSIS

The Munin::Plugin::SNMP module extends L<Net::SNMP> with methods useful for
Munin plugins.

=head1 SNMP CONFIGURATION

SNMP plugins (that use this module) share a common configuration
interface implemented in the function session().  Please see the
documentation for that function for complete instructions and examples
on how to configure SNMP.  The documentation is located there to
ensure that it is up to date and matches the code.

=head1 DEBUGGING

Additional debugging messages can be enabled by setting
C<$Munin::Plugin::SNMP::DEBUG>, C<$Munin::Plugin::DEBUG>, or by exporting
the C<MUNIN_DEBUG> environment variable before running the plugin (by
passing the C<--pidebug> option to C<munin-run>, for instance).

=cut

package Munin::Plugin::SNMP;

use strict;
use warnings;

use Net::SNMP;
use Munin::Plugin;

our (@ISA, $DEBUG);

@ISA = qw(Net::SNMP);
  
# Alias $Munin::Plugin::SNMP::DEBUG to $Munin::Plugin::DEBUG, so SNMP
# plugins don't need to import the latter module to get debug output.
*DEBUG = \$Munin::Plugin::DEBUG;


=head1 METHODS

=cut

sub config_session {

=head2 config_session() - Decode environment to get the needed plugin configuration parameters

  ($host, $port, $version, $tail) = Munin::Plugin::SNMP->config_session();

This is a convenience function for the "config" part of the plugin -
it decodes the environment/plugin name to retrieve the information
needed in the configuration phase.  It returns a 4 tuple consisting of:

=over

=item 1) the host name

=item 2) the udp port to use

=item 3) the SNMP version to use (3 for version 3, 2 for version 1 or 2c)

=item 4) the tail of the plugin name: whatever is left of the plugin
name after "snmp_<host>_".

=back

The tail can be interesting for the "fetch" part of the plugin as
well.

=cut

    my ($host, $port, $version, $tail);

    # Decode plugin/symlink name and extract meaning from it - if possible.
    if ($0 =~ /^(?:.*\/)?snmp(v3)?_([^_]+)_(.*)/) {
	$version = '3' if $1;
	$host = $2;
	$tail = $3;
	if ($host =~ /^([^:]+):(\d+)$/) {
	    $host = $1;
	    $port = $2;
	}
    }

    # The environment overrides the symlink.  The other way around is
    # not useful.
    $host    = $ENV{host}    || $host    || die "Could not find hostname";
    $version = $ENV{version} || $version || '2';
    $port    = $ENV{port}    || $port    || 161;

    return ($host, $port, $version, $tail);
}


sub session {
    my $class = shift;
    my (@userargs) = @_;

=head2 session([optional Net::SNMP options]) - create new Munin::Plugin::SNMP object

  $session = Munin::Plugin::SNMP->session();

This method overrides the Net::SNMP constructor to get the connection
information from the plugin name and/or environment.  Please note that
no error string is returned.  The function handles errors internaly -
giving a error message and calling die.  Calling die is the right
thing to do.

The host name is taken from the plugin symlink, which must be on the
form C<snmp[v3]_E<lt>hostnameE<gt>_E<lt>plugin_nameE<gt>[_args]>.

The "v3" form is taken to mean that SNMPv3 is to be used.  It is also
a name trick providing a separate "namespace" for devices that use
SNMPv3 so it can be configured separately in munin/plugin-conf.d/
files.  E.g.:

  [snmp_*]
     env.version 2
     env.community public

  [snmpv3_*]
     env.v3username snmpoperator
     env.v3authpassword s3cr1tpa55w0rd

See below for how to configure for each different case.  The first
case above shows Munin's default configuration.

NOTE: munin-node-configure does not yet utilize the "v3" thing.

The following environment variables are consulted:

=over

=item env.host

If the plugin name (symlink) does not contain the host name this is
used as the host name to connect to.

The host name must be specified, but is usually specified in the
plugin name.  If the hostname somehow does not resolve in DNS (or the
hosts file) it is possible to do this:

  [snmp_*]
     env.version 2c
     env.community floppa

  [snmp_switch1.langfeldt.net]
     env.host 192.168.2.45

  [snmp_switch2.langfeldt.net]
     env.host 192.168.2.46

=item env.port

The port to connect to.  Default 161.

=item env.timeout

The timeout in seconds to use. Default 5.

=item env.version

The SNMP version to use for the connection. One of 1, 2, 3, snmpv1,
snmpv2c or snmpv3.  SNMP v2 is better as it supports bulk operations.
Therefore 2 is the default in Munin::Plugin::SNMP.  If your device
supports v3 that may be even better as it supports proper security -
but the encryption may slow things down.

Security is handled differently for versions 1/2c and 3.  See below.

=cut

    my ($host, $port, $version, $tail) = config_session();

    # Common options.
    my @options = (-hostname    => $host,
	           -port	=> $port,
                   -version     => $version,
    );

    
    # User defined options
    if (defined($userargs[0])) {
	push(@options,@userargs);
    }
    
    # Timeout 
    if (defined($ENV{timeout})) {
	push(@options, (-timeout => $ENV{timeout}));
    }
    
    if ($version eq '1' or $version eq 'snmpv1' or
	$version eq '2' or $version eq 'snmpv2c') {

=item env.community

The community name for version 1 and 2c agents. The default is
'public'.  If this works your device is probably very insecure and
needs a security checkup.

=cut

	# FIXME: die if $ENV{community} isn't set?
	my $community = $ENV{community} || 'public';

	push(@options,(-community => $community));

	my $object;
	my $error;

	print STDERR "Setting up a SNMPv$version session\n" if $DEBUG;

	($object, $error) = $class->SUPER::session(@options);

	unless ($object) {
	    die "Could not set up SNMP $version session to $host: $error\n";
	}

	return $object;

    } elsif ($version eq '3' or $version eq 'snmpv3') {

=item SNMP 3 authentication

SNMP v3 has three security levels: "noAuthNoPriv".  If a username
and password is given it goes up to "authNoPriv".

If privpassword is given the security level becomes "authPriv" - the
connection is authenticated and encrypted.

Note: Encryption can slow down slow or heavily loaded network devices.
For most uses authNoPriv will be secure enough --- in SNMP v3 the
password is sent over the network encrypted in any case.

Munin::Plugin::SNMP does not support ContextEngineIDs and such for
authentication/privacy.  If you see the need and know how it should be
done please send patches!

For further reading on SNMP v3 security models please consult RFC3414
and the documentation for Net::SNMP.

If version is set to 3 or snmpv3 these variables are used to define
authentication:

=over

=item env.v3username

SNMPv3 username.  There is no default. Empty username ('') is allowed.

=item env.v3authpassword

SNMPv3 authentication password.  Optional when encryption is also
enabled, in which case defaults to the privacy password.
Authentication requires a v3authprotocol, but this defaults to "md5"
and may therefore be left unspecified.

The password is sent encrypted (one way hash) over the network.

=item env.v3authprotocol

SNMPv3 authentication protocol.  One of 'md5' or 'sha' (HMAC-MD5-96,
RFC1321 and SHA-1/HMAC-SHA-96, NIST FIPS PIB 180, RFC2264).  The
default is 'md5'.

=item env.v3privpassword

SNMPv3 privacy password to enable encryption.  An empty ('') password
is considered as no password and will not enable encryption.

Privacy requires a v3privprotocol as well as a v3authprotocol and a
v3authpassword, but all of these are defaulted (to 'des', 'md5', and
the v3privpassword value, respectively) and may therefore be left
unspecified.

=item env.v3privprotocol

If the v3privpassword is set this setting controls what kind of
encryption is used to achive privacy in the session.  Only the very
weak 'des' encryption method is supported officially.  The default is
'des'.

The implementing perl module (Net::SNMP) also supports '3des'
(CBC-3DES-EDE aka Triple-DES, NIST FIPS 46-3) as specified in IETF
draft-reeder-snmpv3-usm-3desede.  Whether or not this works with any
particular device, we do not know.

=back

=cut
	
	my $privpw    = $ENV{'v3privpassword'} || '';
	my $privproto = $ENV{'v3privprotocol'} || 'des';

	my $authpw    = $ENV{'v3authpassword'} || '';
	my $authproto = $ENV{'v3authprotocol'} || 'md5';
	my $username  = $ENV{'v3username'};

	if (defined($username)) {
            # FIXME: isn't it an error if no username was specified?
	    push( @options, (-username => $username));
	}

	if ($privpw) {
	    # Privacy is a stronger demand and should be checked first.
	    push( @options, ( -privpassword => $privpw,
			      -privprotocol => $privproto,
			      -authpassword => ($authpw || $privpw),
			      -authprotocol => $authproto ));

	    # Note how Net::SNMP demands authentication options when
	    # privacy is invoked.
	} elsif ($authpw) {
	    # Authenticated only.
	    push( @options,
		  ( -authpassword => $authpw,
		    -authprotocol => $authproto ));
	}

	my ($object, $error) = $class->SUPER::session(@options);

	if (!defined($object)) {
	    die "Could not set up SNMPv3 session to $host: $error\n";
	}

	return $object;

    } else {
	die "Unknown SNMP version: '$version'.";
    }
}

=back

=head2 get_hash() - retrieve a table as a hash of hashes

  $result = $session->get_hash(
                         [-callback        => sub {},]     # non-blocking
                         [-delay           => $seconds,]   # non-blocking
                         [-contextengineid => $engine_id,] # v3
                         [-contextname     => $name,]      # v3
                         -baseoid          => $oid,
			 -cols             => \%columns
		     );

This method transforms the -baseoid and -cols to a array of -columns
and calls C<get_entries()> with all the other arguments.  It then
transforms the data into a hash of hashes in the following manner:

The keys of the main hash are the last element(s) of the OIDs, after
C<$oid> and the matching keys from C<%columns> are removed. The values
are hashes with keys corresponding to the values of C<%columns> hash and
values from the subtables corresonding to the keys of C<%columns>.

For this to work, all the keys of C<-cols> must have the same number
of elements.  Also, don't try to specify a next-to-next-to-leaf-node
baseoid, the principle it breaks both C<get_entries> and the logic in
C<get_hash>.

If (all) the OIDs are unavailable a defined but empty hashref is
returned.

Example:

  $session->get_hash(
               -baseoid => '1.3.6.1.2.1.2.2.1', # IF-MIB
               -cols    => {
                            1 => 'index',
                            2 => 'descr',
                            4 => 'mtu',
                           }
            );

given the following SNMP table:

  IF-MIB::ifIndex.1 = INTEGER: 1
  IF-MIB::ifIndex.2 = INTEGER: 2
  IF-MIB::ifDescr.1 = STRING: lo0
  IF-MIB::ifDescr.2 = STRING: lna0
  IF-MIB::ifType.1 = INTEGER: softwareLoopback(24)
  IF-MIB::ifType.2 = INTEGER: ethernetCsmacd(6)
  IF-MIB::ifMtu.1 = INTEGER: 32768
  IF-MIB::ifMtu.2 = INTEGER: 1500
  ...

will return a hash like this:

  '1' => {
          'index' => '1',
          'mtu' => '32768',
          'descr' => 'lo0'
         },
  '2' => {
          'index' => '2',
          'descr' => 'lna0',
          'mtu' => '1500'
         }

=cut

sub get_hash {
    my $self = shift;
    my %args = @_;
    my %ret;

    my $base = delete $args{'-baseoid'};
    my $cols = delete $args{'-cols'} or return;
    my @bases = map { $base.'.'.$_; } keys %{$cols};
    $args{-columns} = \@bases;

    my $table = $self->get_entries(-columns => \@bases)
      or return;

    my $subtabs = join '|', keys %$cols;
    my $re = qr/^\Q$base.\E($subtabs)\.(.*)/;
    for my $key (keys %$table) {
	$key =~ $re;
	next unless defined($1 && $2);
	$ret{$2}{$cols->{$1}} = $table->{$key};
    }
    return \%ret;
}


=head2 get_single() - Retrieve a single value by OID

  $uptime = $session->get_single("1.3.6.1.2.1.1.3.0") || 'U';

If the call fails to get a value the above call sets $uptime to 'U'
which Munin interprets as "Undefined" and handles accordingly.

If you stop to think about it you should probably use C<get_hash()> (it
gets too much, but is good for arrays) or C<get_entries()> - it gets
exactly what you want, so you mus

=cut
# FIXME: how was that last sentence meant to finish?


sub get_single {
        my $handle = shift;
        my $oid    = shift;

        print STDERR "# Getting single $oid...\n" if $DEBUG;

        my $response = $handle->get_request($oid);

        if (!defined $response->{$oid} or $handle->error_status) {
            print STDERR "# Error getting $oid: ",$handle->error(),"\n"
                if $DEBUG;
            return;
        }
	return $response->{$oid};
}

=head2 get_by_regex() - Retrive table of values filtered by regex applied to the value

This example shows the usage for a netstat plugin.

  my $tcpConnState = "1.3.6.1.2.1.6.13.1.1.";
  my $connections = $session->get_by_regex($tcpConnState, "[1-9]");

It gets all OIDs based at $tcpConnState and only returns the ones that
contain a number in the value.

=cut

sub get_by_regex
{
    my ($self, $baseoid, $regex) = @_;
    my %result;

    print "# Starting browse of table at $baseoid\n" if $DEBUG;

    $baseoid =~ s/\.$//;  # no trailing dots
    my $response = $self->get_table(-baseoid => $baseoid);
    unless ($response) {
        print "# Failed to get table at $baseoid\n" if $DEBUG;
        return;
    }

    while (my ($oid, $value) = each %$response) {
        unless ($value =~ /$regex/) {
            print "# '$value' doesn't match /$regex/.  Ignoring\n" if $DEBUG;
            next;
        }
        my ($index) = ($oid =~ m{^\Q$baseoid.\E(.*)})
            or die "$oid doesn't appear to be a descendent of $baseoid";

        $result{$index} = $value;
        print "# Index '$index', value $value\n" if $DEBUG;
    }

    return \%result;
}

1;

=head1 TODO

Lots.

=head1 BUGS

Ilmari wrote: C<get_hash()> doesn't handle tables with sparse indices.

Nicolai Langfeldt: Actually I think it does.

=head1 SEE ALSO

L<Net::SNMP>

=head1 AUTHOR

Dagfinn Ilmari Mannsåker, Nicolai Langfeldt
Rune Nordbøe Skillingstad added timeout support.

=head1 COPYRIGHT/License.

Copyright (c) 2004-2009 Dagfinn Ilmari Mannsåker and Nicolai Langfeldt.

All rights reserved. This program is free software; you can
redistribute it and/or modify it under the terms of the GNU General
Public License as published by the Free Software Foundation; version 2
dated June, 1991.

=cut

1;
