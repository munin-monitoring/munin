package Munin::Node::SpoolWriter;


use strict;
use warnings;

use Carp;
use IO::File;

use Fcntl qw(:DEFAULT :flock);

use Munin::Common::Defaults;
use Munin::Common::SyncDictFile;
use Munin::Common::Logger;
use Munin::Common::Utils qw( is_valid_hostname );

use Params::Validate qw( :all );
use List::Util qw( first );

use constant DEFAULT_TIME => 86_400;      # put 1 day of results into a spool file
use constant MAXIMUM_AGE  => 7;           # remove spool files more than a week old
use constant DEFAULT_HOSTNAME => 'munin.example.com';

sub _snap_to_epoch_boundary { my $self = shift; return $_[0] - ($_[0] % $self->{interval_size}) }

sub new {
    my $class = shift;
    my $validated = validate(
        @_, {
            spooldir => {
                type => SCALAR,
                default => $Munin::Common::Defaults::MUNIN_SPOOLDIR,
            },
            interval_size => { type => SCALAR, optional => 1 },
            interval_keep => { type => SCALAR, optional => 1 },
            hostname      => { type => SCALAR, optional => 1 },
        }
    );
    my $self = bless {}, $class;

    $self->{spooldir} = $validated->{spooldir};

    my $spooldirhandle;
    opendir $spooldirhandle, $self->{spooldir}
      or croak "Could not open spooldir '$self->{spooldir}': $!";
    $self->{spooldirhandle} = $spooldirhandle;

    $self->{metadata} = _init_metadata($self->{spooldir});

    $self->{interval_size} = first { defined($_) and $_ > 0 } (
        $validated->{interval_size},
        $self->{metadata}->{interval_size},
        DEFAULT_TIME
    );

    $self->{interval_keep} = first { defined($_) and $_ > 0 } (
        $validated->{interval_keep},
        $self->{metadata}->{interval_keep},
        MAXIMUM_AGE,
    );

    $self->{hostname} = first { defined($_) and is_valid_hostname($_) } (
        $validated->{hostname},
        $self->{metadata}->{hostname},
        DEFAULT_HOSTNAME,
    );

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


# writes the results of a plugin run to the appropriate spool-file
# need to remove any lines containing only a '.'
sub write
{
    my ($self, $timestamp, $service, $data) = @_;

    # squash the $service name with the same rules as the munin-update when using plain TCP
    # Closes D:710529
    $service =~ s/[^_A-Za-z0-9]/_/g;

    my $fmtTimestamp = $self->_snap_to_epoch_boundary($timestamp);

    open my $fh , '>>', "$self->{spooldir}/munin-daemon.$service.$fmtTimestamp." . $self->{interval_size}
        or die "Unable to open spool file: $!";
    flock($fh, LOCK_EX);

    print {$fh} "timestamp $timestamp\n";

    print {$fh} "multigraph $service\n" unless $data->[0] =~ m{^multigraph};

    foreach my $line (@$data) {
        # Ignore blank lines and "."-ones.
        next if (!defined($line) || $line eq '' || $line eq '.');

        print {$fh} $line, "\n" or ERROR("Error writing results: $!");
    }

    # Synchronously write the timestamp for that plugin
    $self->set_metadata("last-timestamp.$service", $timestamp);

    return;
}


# removes files from the spooldir older than MAXIMUM_AGE
sub cleanup
{
    my ($self) = @_;

    my $maxage = $self->{interval_size} * $self->{interval_keep};

    opendir my $dir, $self->{spooldir} or die $!;

    foreach my $file (readdir $dir) {
        next unless $file =~ m{munin-daemon\.\w+\.\d+\.\d+$};

        my $filename = "$self->{spooldir}/$file";
        my $mtime = (stat $filename)[9];
        next unless (time - $mtime) > $maxage;

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
