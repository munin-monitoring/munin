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
    my ($self, $plugin, $timestamp) = @_;

    logger("_cat_multigraph_file($plugin, $timestamp)") if $config->{DEBUG};

    my $return_str = '';

    my $fh_data = IO::File->new($self->{spooldir} . "/munin-daemon.$plugin.data");

    my ($last_epoch, $epoch) = (0, 0);
    while (my $line = <$fh_data>) {
        chomp $line;
        logger("_cat_multigraph_file:line:$line") if $config->{DEBUG};
        # Ignore blank lines
        next if ($line =~ m/^\s+$/);

        # Parse the line for the current epoch
        if ($line =~ m/\w+ (\d+):/) {
            $epoch = $1;
        }
        logger("_cat_multigraph_file:epoch:$epoch,timestamp:$timestamp") if $config->{DEBUG};

        # Only continue if the line epoch is later than the asked one
        next unless ($epoch > $timestamp);

        # emit multigraph line on epoch changes
        if ($epoch != $last_epoch) {
            $last_epoch = $epoch;

            # Emit multigraph header ...
            $return_str .= "multigraph $plugin\n";
            # ... and its config
            $return_str .= _cat_file($self->{spooldir} . "/munin-daemon.$plugin.config");
        }

        # Sending value
        $return_str .= $line . "\n";
    }

    return $return_str;
}


sub _get_spooled_plugins
{
    my ($self) = @_;

    rewinddir $self->{spooldirhandle}
        or die "Unable to reset the spool directory handle: $!";

    return map { m/^munin-daemon\.(\w+)\.data$/ ? $1 : () }
        readdir $self->{spooldirhandle};
}


sub _cat_file
{
	my $filename = shift;
    logger("_cat_file($filename)") if $config->{DEBUG};

	my $fh = IO::File->new($filename);

	my $return_str = '';
	while (my $line = <$fh>) {
		chomp($line);
		# Remove any "." or empty line
		next if ($line eq '' || $line eq '.');
		$return_str .= $line . "\n";
	}

	return $return_str;
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
