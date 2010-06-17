package Munin::Node::SpoolWriter;

# $Id$

use strict;
use warnings;

use Munin::Common::Defaults;
use Munin::Node::Logger;


sub new
{
    my ($class, %args) = @_;

    $args{spooldir} or die "no spooldir provided";

    opendir my $spooldirhandle, $args{spooldir}
        or die "Could not open spooldir '$args{spooldir}': $!";

    $args{spooldirhandle} = $spooldirhandle;

    # TODO: paranoia check?  except dir doesn't (currently) have to be
    # root-owned.

    # TODO: should get the host and port from munin-node.conf
    @args{qw( host port )} = ('localhost', 4949);

    # TODO: set umask

    return bless \%args, $class;
}


# writes the results of a plugin run to the appropriate spool-file
# need to remove any lines containing only a '.'
sub write
{
    my ($self, $timestamp, $service, $data) = @_;
    return;
}


# removes content from the spooldir older than $timestamp
sub cleanup
{
    my ($self, $timestamp) = @_;
    return;
}


1;

__END__

=head1 NAME

Munin::Node::SpoolWriter - Writing side of the spool functionality

=head1 SYNOPSIS

  my $spool = Munin::Node::SpoolWriter->new(spooldir => $spooldir);
  $spool->write(1234567890, 'cpu', \@results);

=head1 METHODS

=over 4

=head2 B<new(%args)>

Constructor.  'spooldir' key should be the directory
L<Munin::Node::SpoolReader> is reading from.


=head2 B<write($timestamp, $service, \@results)>

Takes a timestamp, service name, and the results of running config and fetch on
it.  Writes it to the spool directory for L<Munin::Node::SpoolReader> to read.


=head2 B<cleanup($timestamp)>

Removes any items in the spool directory older than $timestamp.


=back

=cut

# vim: sw=4 : ts=4 : et
