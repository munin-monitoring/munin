package Munin::Node::Configure::History;

use strict;
use warnings;

use POSIX ();
use Munin::Node::Configure::Debug;


sub new
{
    my ($class, %opts) = @_;

    my $newer        = delete $opts{newer};
    my $history_file = delete $opts{history_file} or die;

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
    my $uname = lc((POSIX::uname())[0]);

    while (my $line = <$HIST>) {
        # FIXME: use Munin::Common::Config
        $line =~ s/#.*//g;
        $line =~ s/^\s+//g;
        $line =~ s/\s+$//g;
        next unless $line =~ /\S/;

        if ($line =~ /^\[([^\]]+)\]$/) {
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
        elsif ($line =~ /^([^\/]+)\/(.+)$/) {
            if ($uname eq $1) {
                $self->{valid_plugins}{$2} = 1;
                DEBUG("\tAdding plugin '$2' to version tree ($ver)");
            }
        }
        elsif ($line =~ /^(.+)$/) {
            $self->{valid_plugins}{$1} = 1;
            DEBUG("\tAdding plugin '$1' to version tree ($ver)");
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
# vim: sw=4 : ts=4 : expandtab
