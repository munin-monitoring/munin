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



# returns all output for all services since $timestamp.
sub fetch
{
    my ($self, $timestamp) = @_;

    my $return_str = '';

    my @plugins = $self->_get_spooled_plugins();
    DEBUG("timestamp:$timestamp, plugins:@plugins") if $config->{DEBUG};
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
    my ($self, $service, $timestamp, $max_samples_per_service) = @_;

    # Default $max_samples_per_service is 5, in order to have a 5x time
    # increase in catchup.  This enables to not overwhelm the munin-update when
    # there is big backlog to handle. Use "0" to send an infinite number of
    # samples
    $max_samples_per_service = 5 if (! defined $max_samples_per_service);

    my $data = "";

    rewinddir $self->{spooldirhandle}
        or die "Unable to reset the spool directory handle: $!";

    my $nb_samples_sent = 0;
    foreach my $file (readdir $self->{spooldirhandle}) {
        next unless $file =~ m/^munin-daemon\.$service\.(\d+)\.(\d+)$/;
        next unless $1+$2 >= $timestamp;

        open my $fh, '<', "$self->{spooldir}/$file"
            or die "Unable to open spool file: $!";
        flock($fh, LOCK_SH);

        my $epoch;

        # wind through to the start of the first results after $timestamp
        while (<$fh>) {
            ($epoch) = m/^timestamp (\d+)/ or next;
            DEBUG("Timestamp: $epoch") if $config->{DEBUG};
            last if ($epoch > $timestamp);
        }

        if (eof $fh) {
            DEBUG("Epoch $timestamp not found in spool file for '$service'")
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
