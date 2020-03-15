package Munin::Node::Configure::History;

use strict;
use warnings;

use base 'Munin::Common::Config';

use POSIX ();
use Munin::Node::Configure::Debug;


sub new
{
    my ($class, %opts) = @_;

    my $newer        = delete $opts{newer};
    my $history_file = delete $opts{history_file} or die "A history file must be specified\n";

    my %history = (
        newer        => $newer,
        history_file => $history_file,
    );

    return bless \%history, $class;
}


sub load
{
    my ($self) = @_;

    my $reached_version = 0;
    my $ver = "0.0.0";

    return unless $self->{newer};

    DEBUG("Loading plugin history from '$self->{history_file}'");

    open(my $HIST, '<', $self->{history_file})
        or die "# ERROR: Could not open '$self->{history_file}': $!\n";

    # $^O or $Config{osname} are based on the platform perl was built on,
    # not where it's currently running.  This should always be correct
    my $uname = lc((POSIX::uname)[0]);

    while (my $line = <$HIST>) {
        $self->_strip_comment($line);
        $self->_trim($line);
        next unless length $line;

        if ($line =~ /^ \[ ([^\]]+) \] $/x) {
            $ver = $1;
            DEBUG("Setting version to '$ver'.");
            if ($ver eq $self->{newer}) {
                $reached_version = 1;
            } elsif ($reached_version) {
                $reached_version++;
            }
        }
        elsif ($reached_version < 2) {
            next;
        }
        elsif ($line =~ m{^ ([^/]+) / (.+) }x) {
            if ($uname eq $1) {
                $self->{valid_plugins}{$2} = 1;
                DEBUG("\tAdding plugin '$2' to version tree.");
            }
            else {
                DEBUG("\tPlugin '$2' applies to another architecture ($1).");
            }
        }
        else {
            $self->{valid_plugins}{$line} = 1;
            DEBUG("\tAdding plugin '$line' to version tree.");
        }
    }
    close $HIST;

    # FIXME: still not a good error message.  should this be non-fatal?
    die "# FATAL: version '$self->{newer}' was not found in the plugin history file\n"
        unless ($reached_version);

    return;
}


sub too_old
{
    my ($self, $plugin) = @_;

    return 0 unless $self->{newer};
    return 0 unless $plugin->in_family('auto');
    return 0 if $self->{valid_plugins}{$plugin->{name}};
    return 1;
}


1;

__END__

=head1 NAME

Munin::Node::Configure::History - Filtering plugins based on the version of
Munin they were first distributed with.


=head1 SYNOPSIS

  my $plugin = Munin::Node::Configure::History->new(
      newer        => '1.3.3',
      history_file => 'plugins/plugins.history',
  );


=head1 METHODS

=over

=item B<new(%args)>

Constructor.

The 'history_file' argument is required, and should be the path to the plugin
history file.  The 'newer' argument is optional, and should be the version of
the release before which plugins should be ignored.


=item B<load()>

Loads the plugin history from history_file.  Dies if 'newer' didn't match a
valid release, or the file wasn't readable.


=item B<too_old($plugin)>

Takes a Munin::Node::Configure::Plugin object.  Returns false unless the
plugin should be ignored, true otherwise (ie. if 'newer' wasn't set, the plugin
is user-contributed, etc).

=back

=cut
# vim: sw=4 : ts=4 : expandtab
