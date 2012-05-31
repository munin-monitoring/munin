package Munin::Node::SpoolReader;

# $Id$

use strict;
use warnings;

use Carp;
use IO::File;

use Munin::Common::Defaults;
use Munin::Node::Logger;

use Munin::Node::Config;
my $config = Munin::Node::Config->instance;


use constant TIME => 86_400;  # put 1 day of results into a spool file

sub _snap_to_epoch_boundary { return $_[0] - ($_[0] % TIME) }


sub new
{
    my ($class, %args) = @_;

    $args{spooldir} or croak "no spooldir provided";

    opendir $args{spooldirhandle}, $args{spooldir}
        or croak "Could not open spooldir '$args{spooldir}': $!";

    # TODO: paranoia check?  except dir doesn't (currently) have to be
    # root-owned.

    return bless \%args, $class;
}


# returns all output for all services since $timestamp.
sub fetch
{
    my ($self, $timestamp) = @_;

    my $return_str = '';

    my @plugins = $self->_get_spooled_plugins();
    logger("timestamp:$timestamp, plugins:@plugins") if $config->{DEBUG};
    foreach my $plugin (@plugins) {
        $return_str .= $self->_cat_multigraph_file($plugin, $timestamp);
    }

    return $return_str;
}


sub list
{
	my ($self) = @_;

	my @plugins = $self->_get_spooled_plugins();
	return join(" ", sort @plugins) . "\n";
}


sub _cat_multigraph_file
{
    my ($self, $service, $timestamp) = @_;

    my $fmtTimestamp = _snap_to_epoch_boundary($timestamp);

    my $data = "";

    rewinddir $self->{spooldirhandle}
        or die "Unable to reset the spool directory handle: $!";

    foreach my $file (readdir $self->{spooldirhandle}) {
        next unless $file =~ m/^munin-daemon\.$service.(\d+)$/;
        next unless $1 >= $fmtTimestamp;

        open my $fh, '<', "$self->{spooldir}/$file"
            or die "Unable to open spool file: $!";

        my $epoch;

        # wind through to the start of the first results after $timestamp
        while (<$fh>) {
            ($epoch) = m/^timestamp (\d+)/ or next;
            logger("Timestamp: $epoch") if $config->{DEBUG};
            last if ($epoch > $timestamp);
        }

        if (eof $fh) {
            logger("Epoch $timestamp not found in spool file for '$service'")
                if $config->{DEBUG};
            next;
        }

        # The timestamp isn't part of the multigraph protocol,
        # just part of spoolfetch, so we have to filter it out,
        # and replace each value line with its current value
        while (<$fh>) {
            chomp;
            if (m/^timestamp (\d+)/) {
                # epoch is updated
                $epoch = $1;
                next;
            }

            if (m/^(\w+)\.value\s+(?:N:)?([0-9.]+|U)$/) {
                $_ = "$1.value $epoch:$2";
            }

            $data .= $_ . "\n";
        }
    }

    return $data;
}


sub _get_spooled_plugins
{
    my ($self) = @_;

    rewinddir $self->{spooldirhandle}
        or die "Unable to reset the spool directory handle: $!";

    my %seen;
    return map { m/^munin-daemon\.(\w+)\.\d+$/ && ! $seen{$1}++ ? $1 : () }
        readdir $self->{spooldirhandle};
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

=item B<new($args)>

Constructor.  'spooldir' should be the directory L<Munin::Node::SpoolWriter> is
writing to.

=item B<fetch($timestamp)>

Fetches all the plugin results that have been recorded since C<$timestamp>,
in a form suitable to be sent straight over the wire.

=item B<list()>

Lists all the plugin that have been recorded in the spool, in a form suitable
to be sent straight over the wire.

=back

=cut

# vim: sw=4 : ts=4 : et
