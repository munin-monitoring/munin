package Munin::Node::Configure::HostEnumeration;

use strict;
use warnings;

use Socket;

use Munin::Node::Configure::Debug;

use Exporter ();
our @ISA = qw/Exporter/;
our @EXPORT = qw/expand_hosts/;


### Network address manipulation ###############################################

# converts a hostname or IP and an optional netmask into a list of the
# hostnames and/or IPs in that network.
#
# If you haven't guessed, this is IPv4 only.
sub _hosts_in_net
{
    my ($host, $mask) = @_;
    my @ret;

    # avoid losing the hostname that was provided.  makes for more appropriate
    # links in the servicedir.
    #
    # FIXME: this is very limited.  make it work in the case when a netmask is
    # provided (substitute the hostname for the corresponding IP in the list
    # that is returned.
    unless (defined $mask) {
        return $host;
    }

    my $addr = _resolve($host);

    die "Invalid netmask: $mask\n"
        unless ($mask =~ /^\d+$/ and $mask <= 32);

    my $net = unpack('N', $addr);  # ntohl()

    # Evil maths courtesy of nmap's TargetGroup.cc
    my $low  = $net & (0 - (1 << (32 - $mask)));
    my $high = $net | ((1 << (32 - $mask)) - 1);

    # Note that the .. operator uses signed integers.  Hence the loop.
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

    my ($name, $aliases, $addrtype, $length, @addrs) = gethostbyname($host);
    die "Unable to resolve $host\n" unless $name;

    if (scalar @addrs > 1) {
        warn sprintf "# Hostname %s resolves to %u IPs.  Using %s\n",
                           $host,
                           scalar(@addrs),
                           inet_ntoa($addrs[0]);
    }
    DEBUG(sprintf "# Resolved %s to %s", $host, inet_ntoa($addrs[0]));

    return $addrs[0];
}


sub expand_hosts
{
    my (@unexpanded) = @_;
    my @hosts;

    foreach my $item (@unexpanded) {
        DEBUG("Processing $item");
        my ($host, $mask) = split '/', $item, 2;
        push @hosts, _hosts_in_net($host, $mask);
    }
    return @hosts;
}


1;

__END__

=head1 NAME

Munin::Node::Configure::HostEnumeration - Takes a list of hosts, and returns
the corresponding IPs in dotted-quad form.


=head1 SYNOPSIS

  @hosts = ('switch1', 'host1/24', '10.0.0.60/30');
  foreach my $host (expand_hosts(@hosts)) {
      # ...
  }


=head1 SUBROUTINES

=over

=item B<expand_hosts>

  @expanded = expand_hosts(@list);

Takes a list of hosts, and returns the corresponding IPs in dotted-quad form.

Items can be specified as a hostname or dotted-quad IP, either with or
without a netmask.

Currently only IPv4 addresses are supported.

=back

=cut
# vim: ts=4 : sw=4 : expandtab
