package Munin::Node::SpoolReader;


use strict;
use warnings;

use Carp;
use IO::File;

use Fcntl qw(:DEFAULT :flock);

use Munin::Common::Defaults;
use Munin::Common::SyncDictFile;
use Munin::Common::Logger;

use Params::Validate qw(:all);

use Munin::Node::Config;
my $config = Munin::Node::Config->instance;


sub new {
    my $class = shift;
    my $validated = validate (
        @_, {
            spooldir => {
                type    => SCALAR,
                default => $Munin::Common::Defaults::MUNIN_SPOOLDIR
            },
        }
    );
    my $self = bless {}, $class;

    $self->{spooldir} = $validated->{'spooldir'};

    my $spooldirhandle;
    opendir $spooldirhandle, $self->{spooldir}
      or croak "Could not open spooldir '$self->{spooldir}': $!";
    $self->{spooldirhandle} = $spooldirhandle;

    $self->{metadata} = _init_metadata($self->{spooldir});

    return $self;
}


#prepare tied hash for metadata persisted to $spooldir/SPOOL-META
#should we pull these methods into a base class or create a spool manager class?
sub _init_metadata
{

	my $spooldir = shift;
	my %metadata;

	tie %metadata, 'Munin::Common::SyncDictFile', $spooldir . "/SPOOL-META";

	return \%metadata;

}


#retrieve metadata value for key
sub get_metadata
{
	my ($self, $key) = @_;

	return ${ $self->{metadata} }{$key};

}


#set metadata key:value and persist
sub set_metadata
{
	my ($self, $key, $value) = @_;

	${ $self->{metadata} }{$key} = $value;

}



# returns all output for all services since $from_epoch
sub fetch
{
    my ($self, $from_epoch) = @_;

    my $return_str = '';

    my @plugins = $self->_get_spooled_plugins();

    # No need to have more recent than $to_epoch, it will not be complete
    my $to_epoch = $self->_get_to_epoch(\@plugins);

    DEBUG("from_epoch:$from_epoch, to_epoch:$to_epoch, plugins:@plugins") if $config->{DEBUG};
    foreach my $plugin (@plugins) {
        $return_str .= $self->_cat_multigraph_file($plugin, $from_epoch, $to_epoch);
    }

    return $return_str;
}

sub _get_to_epoch
{
	my ($self, $plugins) = @_;

	my $to_epoch = time;

	# Get the earliest timestamp, to avoid hitting in-flight data
	for my $plugin (@$plugins) {
		my $last_timestamp = $self->get_metadata("last-timestamp.$plugin");
		$to_epoch = $last_timestamp if ($last_timestamp < $to_epoch);
	}

	return $to_epoch;
}

sub list
{
	my ($self) = @_;

	my @plugins = $self->_get_spooled_plugins();
	return join(" ", sort @plugins) . "\n";
}


sub _cat_multigraph_file
{
    my ($self, $service, $from_epoch, $to_epoch, $max_samples_per_service) = @_;

    # Default $max_samples_per_service is 5, in order to have a 5x time
    # increase in catchup.  This enables to not overwhelm the munin-update when
    # there is big backlog to handle. Use "0" to send an infinite number of
    # samples
    $max_samples_per_service = 5 if (! defined $max_samples_per_service);

    # If $timestamp is negative, use "since $timestamp" as $timestamp
    $from_epoch = time + $from_epoch if $from_epoch < 0;

    # $to_epoch has the same rules as $from_epoch, but defaults to now()
    $to_epoch = time unless $to_epoch;
    $to_epoch = time + $to_epoch if $to_epoch < 0;

    my $data = "";

    rewinddir $self->{spooldirhandle}
        or die "Unable to reset the spool directory handle: $!";

    my $nb_samples_sent = 0;
    foreach my $file (readdir $self->{spooldirhandle}) {
        next unless $file =~ m/^munin-daemon\.$service\.(\d+)\.(\d+)$/;
        next unless $1+$2 >= $from_epoch;

        open my $fh, '<', "$self->{spooldir}/$file"
            or die "Unable to open spool file: $!";
        flock($fh, LOCK_SH);

        my $epoch;

        # wind through to the start of the first results after $timestamp
        while (<$fh>) {
            ($epoch) = m/^timestamp (\d+)/ or next;
            DEBUG("Timestamp: $epoch") if $config->{DEBUG};
            last if ($epoch > $from_epoch);
        }

        if (eof $fh) {
            DEBUG("Epoch $from_epoch not found in spool file for '$service'")
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

		# timestamp in the future.
		# should fetch next time.
		last if ($epoch > $to_epoch);

                next;
            }

            if (m/^(\w+)\.value\s+(?:N:)?(.+)$/) {
                $_ = "$1.value $epoch:$2";
            }

            $data .= $_ . "\n";
        }

	# We just emitted something
	$nb_samples_sent ++;
	if ($max_samples_per_service && $nb_samples_sent > $max_samples_per_service) {
		logger("Already sent $nb_samples_sent for '$service', ending.") if $config->{DEBUG};
		last;
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
    return map { m/^munin-daemon\.(.*)\.\d+\.\d+$/ && ! $seen{$1}++ ? $1 : () }
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
