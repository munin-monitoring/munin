package Munin::Node::Configure::PluginList;

use strict;
use warnings;

use File::Basename qw(fileparse);

use Munin::Node::Service;
use Munin::Node::Configure::Plugin;
use Munin::Node::Configure::History;
use Munin::Node::Configure::Debug;


sub new
{
    my ($class, %opts) = @_;

    my $libdir     = delete $opts{libdir}     or die "Must specify the directory\n";
    my $servicedir = delete $opts{servicedir} or die "Must specify the service directory\n";

    my $library  = Munin::Node::Service->new(servicedir => $libdir);
    my $services = Munin::Node::Service->new(servicedir => $servicedir);

    my $families = delete $opts{families} or die "Must provide a list of families to load\n";
    my $newer    = delete $opts{newer};

    my %plugin = (
        libdir     => $libdir,
        library    => $library,

        servicedir => $servicedir,
        services   => $services,

        families   => $families,
        newer      => $newer,

        %opts,
    );

    return bless \%plugin, $class;
}


### Plugin and service enumeration #############################################

sub load
{
    my ($self) = @_;
    $self->_load_available();
    $self->_load_installed();
    return;
}


sub _load_available
{
    my ($self) = @_;

    my @families = @{$self->{families}};
    my %found;
    my $plugin_count = 0;

    my $history = Munin::Node::Configure::History->new(
        history_file => "$self->{libdir}/plugins.history",
        newer        => $self->{newer},
    );
    $history->load;

    DEBUG("Searching '$self->{libdir}' for available plugins.");

    foreach my $item (_valid_files($self->{library})) {
        my $path = $item->{path};
        my $plug = $item->{name};

        DEBUG("Considering '$path'");

        my $plugin = Munin::Node::Configure::Plugin->new(name => $plug, path => $path);

        $plugin->read_magic_markers();

        unless ($plugin->in_family(@families)) {
            DEBUG("\tFamily '$plugin->{family}' is currently ignored.  Skipping.");
            next;
        }

        if ($history->too_old($plugin)) {
            DEBUG("\tPlugin is older than $self->{newer}.  Skipping.");
            next;
        }

        $found{$plug} = $plugin;
        $plugin_count++;
    }

    $self->{plugins} = \%found;
    DEBUG("$plugin_count plugins available.");

    return;
}


sub _load_installed
{
    my ($self) = @_;
    my $service_count = 0;  # the number of services currently installed.

    DEBUG("Searching '$self->{servicedir}' for installed services.");

    foreach my $item (_valid_files($self->{services})) {
        my $path    = $item->{path};
        my $service = $item->{name};

        my $realfile;
        # Ignore non-symlinks, and symlinks that point anywhere other
        # than the plugin library
        next unless -l $path;
        unless ($realfile = readlink($path)) {
            # FIXME: should be a given, since it's tested by is_a_runnable_service()
            DEBUG("Warning: symlink '$path' is broken.");
            next;
        }
        next unless ($realfile =~ /^$self->{libdir}\//);

        DEBUG("Found '$service'");

        $realfile = fileparse($realfile);
        unless ($self->{plugins}{$realfile}) {
            DEBUG("\tCorresponds to an ignored plugin ($realfile).  Skipping.");
            next;
        }

        $self->{plugins}{$realfile}->add_instance($service);
        $service_count++;
    }

    DEBUG("$service_count services currently installed.");
    return;
}


sub list
{
    my ($self) = @_;
    my @plugins;
    foreach my $plug (sort keys %{$self->{plugins}}) {
        push @plugins, $self->{plugins}{$plug};
    }
    return @plugins;
}


sub names { return keys %{(shift)->{plugins}} }


sub _valid_files
{
    my ($dir) = @_;
    return map { { path => "$dir->{servicedir}/$_", name => $_ } } $dir->list;
}


1;

__END__

=head1 NAME

Munin::Node::Configure::PluginList - Loading and listing a collection of plugins


=head1 SYNOPSIS

  my $plugins = Munin::Node::Configure::PluginList->new(
        libdir     => '/usr/share/munin/plugins/',
        servicedir => '/etc/munin/plugins/',
  );
  $plugins->load('auto');
  foreach my $plugin ($plugins->list) {
        # do something to each 'auto' plugin in turn
  }


=head1 SUBROUTINES

=over

=item B<new(%args)>

Constructor.

Required arguments are 'libdir' and 'servicedir', which are the plugin library
and service directory, respectively.


=item B<load(@families)>

Finds all the plugins in 'libdir' that are in any of @families, and any
instances of these plugins in 'servicedir'.


=item B<list()>

Returns a list of Munin::Node::Configure::Plugin objects currently loaded,
sorted alphabetically by name.


=item B<names()>

Returns the names of the currently-loaded plugins.

=back

=cut
# vim: sw=4 : ts=4 : expandtab
