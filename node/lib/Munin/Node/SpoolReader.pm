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

    # FIXME: shortcut by checking mtime of file?

    open my $fh, '<', "$self->{spooldir}/munin-daemon.$service.0"
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
        return '';
    }

    # FIXME: shouldn't need to add the epoch line back in manually
    local $/;  # slurp the rest of the file
    return "timestamp $epoch\n" . <$fh>;
}


sub _get_spooled_plugins
{
    my ($self) = @_;

    rewinddir $self->{spooldirhandle}
        or die "Unable to reset the spool directory handle: $!";

    return map { m/^munin-daemon\.(\w+).0$/ ? $1 : () }
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
