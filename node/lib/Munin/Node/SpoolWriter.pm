package Munin::Node::SpoolWriter;

# $Id$

use strict;
use warnings;

use Carp;
use IO::File;

use Munin::Common::Defaults;
use Munin::Node::Logger;


use constant TIME        => 86_400;      # put 1 day of results into a spool file
use constant MAXIMUM_AGE => TIME * 7;    # remove spool files more than a week old

sub _snap_to_epoch_boundary { return $_[0] - ($_[0] % TIME) }


sub new
{
    my ($class, %args) = @_;

    $args{spooldir} or croak "no spooldir provided";

    opendir $args{spooldirhandle}, $args{spooldir}
        or croak "Could not open spooldir '$args{spooldir}': $!";

    # TODO: paranoia check?  except dir doesn't (currently) have to be
    # root-owned.

    # TODO: set umask

    return bless \%args, $class;
}


# writes the results of a plugin run to the appropriate spool-file
# need to remove any lines containing only a '.'
sub write
{
    my ($self, $timestamp, $service, $data) = @_;

    my $fmtTimestamp = _snap_to_epoch_boundary($timestamp);

    open my $fh , '>>', "$self->{spooldir}/munin-daemon.$service.$fmtTimestamp"
        or die "Unable to open spool file: $!";

    print {$fh} "timestamp $timestamp\n";
    print {$fh} "multigraph $service\n" unless $data->[0] =~ m{^multigraph};

    foreach my $line (@$data) {
        # Ignore blank lines and "."-ones.
        next if (!defined($line) || $line eq '' || $line eq '.');

        print {$fh} $line, "\n" or logger("Error writing results: $!");
    }

    return;
}


# removes files from the spooldir older than MAXIMUM_AGE
sub cleanup
{
    my ($self) = @_;

    opendir my $dir, $self->{spooldir} or die $!;

    foreach my $file (readdir $dir) {
        my $timestamp;
        next unless ($timestamp) = ($file =~ m{munin-daemon\.\w+\.(\d+)$})
                and (time - $timestamp) > MAXIMUM_AGE;

        my $filename = "$self->{spooldir}/$file";

        unlink $filename or die "Unable to unlink '$filename': $!\n";
    }

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

=item B<new(%args)>

Constructor.  'spooldir' key should be the directory
L<Munin::Node::SpoolReader> is reading from.

=item B<write($timestamp, $service, \@results)>

Takes a timestamp, service name, and the results of running config and fetch on
it.  Writes it to the spool directory for L<Munin::Node::SpoolReader> to read.

=item B<cleanup($timestamp)>

Removes any items in the spool directory older than $timestamp.

=back

=cut

# vim: sw=4 : ts=4 : et
