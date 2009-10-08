package Munin::Node::Configure::PluginList;

use strict;
use warnings;

use File::Basename qw(fileparse);

use Munin::Node::Service;
use Munin::Node::Configure::Plugin;

use Munin::Node::Config;
my $config = Munin::Node::Config->instance();


sub new
{
    my ($class, %opts) = @_;

    my $directory  = delete $opts{libdir} or die "Must specify the directory\n";
    my $servicedir = delete $opts{servicedir} or die "Must specify the service directory\n";

    my %plugin = (
        directory    => $directory, 
        servicedir   => $servicedir,

        %opts,
    );

    return bless \%plugin, $class;
}


### Plugin and service enumeration #############################################

sub load
{
    $_[0]->load_available();
    $_[0]->load_installed();
}


sub load_available
{
    my ($self) = @_;

    my %valid_plugins = main::load_plugin_history($config->{newer}) if $config->{newer};

    my %found;

    DEBUG("Searching '$config->{libdir}' for available plugins.");

    opendir (my $LIBDIR, $config->{libdir})
        or die "Fatal: Could not open '$config->{libdir}' for reading: $!\n";

    while (my $plug = readdir $LIBDIR) {
        my $path = "$config->{libdir}/$plug";
        unless (Munin::Node::Service->is_a_runnable_service($plug, $config->{libdir})) {
            DEBUG("Ignoring '$path'.");
            next;
        }

        DEBUG("Considering '$path'");

        # FIXME: should there ever be symlinks in here?  do we even need
        # care unless we're going to try running it?
        while (-l $path) {
            $path = readlink($path);
            $path = ($path =~ /^\//) ? $path : "$config->{libdir}/$path";
        }

        my $plugin = Munin::Node::Configure::Plugin->new(
                    name => $plug,
                    path => $path,
        );

        $plugin->read_magic_markers();

        unless (grep { $plugin->{family} eq $_ } @{ $config->{families} }) {
            DEBUG("\tFamily '$plugin->{family}' is currently ignored.  Skipping.");
            next;
        }

        if (($plugin->{family} eq "auto")
            and $config->{newer}
            and not $valid_plugins{$plug})
        {
            DEBUG("\tPlugin is older than $config->{newer}.  Skipping.");
            next;
        }

        $found{$plug} = $plugin;
    }
    close ($LIBDIR);

    DEBUG(sprintf "%u plugins available.", scalar keys %found);
    $self->{plugins} = \%found;

    return;
}


sub load_installed
{
    my ($plugins) = @_;

    my $service_count = 0;  # the number of services currently installed.

    DEBUG("Searching '$config->{servicedir}' for installed plugins.");

    opendir (my $SERVICEDIR, $config->{servicedir})
        or die "ERROR: Could not open '$config->{servicedir}' for reading: $!\n";

    while (my $service = readdir $SERVICEDIR) {
        my $realfile;
        my $path = "$config->{servicedir}/$service";

        next unless Munin::Node::Service->is_a_runnable_service($service);

        # Ignore non-symlinks, and symlinks that point anywhere other
        # than the plugin library
        next unless -l $path;
        unless ($realfile = readlink($path)) {
            # FIXME: should be a given, since it's tested by is_a_runnable_service()
            DEBUG("Warning: symlink '$config->{servicedir}/$service' is broken.");
            next;
        }
        next unless ($realfile =~ /^$config->{libdir}\//);

        $realfile = fileparse($realfile);

        DEBUG("Found '$service'");

        unless ($plugins->{plugins}{$realfile}) {
            DEBUG("\tCorresponds to an ignored plugin ($realfile).  Skipping.");
            next;
        }

        $plugins->{plugins}{$realfile}->add_instance($service);
        $service_count++;
    }
    close($SERVICEDIR);

    DEBUG("$service_count services currently installed.");
    return;
}


# returns the list of plugins, sorted alphabetically by name
sub list
{
    my ($self) = @_;
    my @plugins;
    foreach my $plug (sort keys %{$self->{plugins}}) {
        push @plugins, $self->{plugins}{$plug};
    }
    return @plugins;
}



sub DEBUG { print '# ', @_, "\n" if $config->{DEBUG}; }


1;
# vim: sw=4 : ts=4 : expandtab
