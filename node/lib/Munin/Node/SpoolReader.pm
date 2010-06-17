package Munin::Node::SpoolReader;

# $Id$

use strict;
use warnings;

use Munin::Common::Defaults;


sub new
{
    my ($class, %args) = @_;

    $args{spooldir} or die "no spooldir provided";

    opendir my $spooldirhandle, $args{spooldir}
        or die "Could not open spooldir '$args{spooldir}': $!";

    $args{spooldirhandle} = $spooldirhandle;

    # TODO: paranoia check?  except dir doesn't (currently) have to be
    # root-owned.

    return bless \%args, $class;
}


# returns all output for all services since $timestamp.
sub fetch
{
    my ($self, $timestamp) = @_;
    return;
}


1;

__END__

=head1 NAME

Munin::Node::SpoolReader - Reading side of the spool functionality

=head1 SYNOPSIS

  my $spool = Munin::Node::SpoolReader->new(spooldir => $spooldir);
  print $spool->fetch(1234567890);

=head1 METHODS

=over 4

=head2 B<new($args)>

Constructor.  'spooldir' should be the directory L<Munin::Node::SpoolWriter> is
writing to.


=head2 B<fetch($timestamp)>

Fetches all the plugin results that have been recorded since C<$timestamp>,
in a form suitable to be sent straight over the wire.

=back

=cut

# vim: sw=4 : ts=4 : et
