package Munin::Node::Service;


use warnings;
use strict;

use English qw(-no_match_vars);
use Carp;

use Munin::Node::Config;
use Munin::Node::OS;
use Munin::Common::Logger;

use Munin::Common::Defaults;

my $config = Munin::Node::Config->instance();


sub new
{
    my ($class, %args) = @_;

    # Set defaults
    $args{servicedir} ||= "$Munin::Common::Defaults::MUNIN_CONFDIR/plugins";

    $args{defuser}  ||= getpwnam $Munin::Common::Defaults::MUNIN_PLUGINUSER;
    $args{defgroup} ||= getgrnam $Munin::Common::Defaults::MUNIN_GROUP;

    $args{timeout}  ||= 60; # Default transaction timeout : 1 min
    $args{pidebug}  ||= 0;

    die "Fatal error. Bailing out.\n"
        unless (Munin::Node::OS->check_perms_if_paranoid($args{servicedir}));

    return bless \%args, $class;
}


sub is_a_runnable_service
{
    my ($self, $file) = @_;

    return unless -f "$self->{servicedir}/$file" && -x _;

    # FIX isn't it enough to check that the file is executable and not
    # in 'ignores'? Can hidden files and config files be
    # unintentionally executable? What does config files do in the
    # service directory? Shouldn't we complain if there is junk in the
    # service directory?
    return if $file =~ m/^\./;      # Hidden files
    return if $file =~ m/\.conf$/;  # Config files

    return if $file !~ m/^[-\w.:]+$/;  # Skip if any weird chars

    foreach my $regex (@{$config->{ignores}}) {
        return if $file =~ /$regex/;
    }

    return 1;
}


sub list
{
    my ($self) = @_;
    opendir my $dir, $self->{servicedir}
        or die "Unable to open $self->{servicedir}: $!";
    return grep { $self->is_a_runnable_service($_) } readdir $dir;
}


# FIXME: unexpected things are likely to happen if this isn't called before
# running plugins.  it should be done automatically the first time a service is
# run.
sub prepare_plugin_environment
{
    my ($self, @plugins) = @_;

    Munin::Common::Defaults->export_to_environment();

    $config->{fqdn} ||= Munin::Node::OS->get_fq_hostname();

    # Export some variables plugins might be interested in
    $ENV{MUNIN_DEBUG} = $self->{pidebug};
    $ENV{FQDN}        = $config->{fqdn};

    # munin-node will override this with the IP of the connecting master
    $ENV{MUNIN_MASTER_IP} = '';

    # Tell plugins about supported capabilities
    $ENV{MUNIN_CAP_MULTIGRAPH} = 1;

    # Some locales use "," as decimal separator. This can mess up a lot
    # of plugins.
    $ENV{LC_ALL} = 'C';

    # LC_ALL should be enough, but some plugins don't follow specs (#1014)
    $ENV{LANG} = 'C';

    # PATH should be *very* sane by default. Can be overridden via 
    # config file if needed (Closes #863 and #1128).
    $ENV{PATH} = '/usr/sbin:/usr/bin:/sbin:/bin';

    if ($config->{sconffile}) {
        # only used by munin-run
        $config->parse_plugin_config_file($config->{sconffile});
    }
    else {
        $config->process_plugin_configuration_files();
    }
    $config->apply_wildcards(@plugins);

    return;
}


sub export_service_environment {
    my ($self, $service) = @_;
    print STDERR "# Setting up environment\n" if $config->{DEBUG};

    # We append the USER to the MUNIN_PLUGSTATE, to avoid CVE-2012-3512
    my $uid = $self->_resolve_uid($service);
    my $user = getpwuid($uid);
    $ENV{MUNIN_PLUGSTATE} = "$Munin::Common::Defaults::MUNIN_PLUGSTATE/$user";

    # Provide a consistent default state-file.
    $ENV{MUNIN_STATEFILE} = "$ENV{MUNIN_PLUGSTATE}/$service-$ENV{MUNIN_MASTER_IP}";

    my $env = $config->{sconf}{$service}{env} or return;

    while (my ($k, $v) = each %$env) {
        print STDERR "# Environment $k = $v\n" if $config->{DEBUG};
        $ENV{$k} = $v;
    }
}


# Resolves the uid the service should be run as.  If it cannot be resolved, an
# exception will be thrown.
sub _resolve_uid
{
    my ($self, $service) = @_;

    my $user = $config->{sconf}{$service}{user};

    # Need to test for defined, since a user might be specified with UID = 0
    my $service_user = defined $user ? $user : $self->{defuser};

    my $u = Munin::Node::OS->get_uid($service_user);
    croak "User '$service_user' required for '$service' does not exist."
        unless defined $u;

    return $u;
}


# resolves the GIDs (real and effective) the service should be run as.
# http://munin-monitoring.org/wiki/plugin-conf.d
sub _resolve_gids
{
    my ($self, $service) = @_;

    my $group_list = $config->{sconf}{$service}{group};

    my $default_gid = $self->{defgroup};

    my @groups;

    foreach my $group (@{$group_list||[]}) {
        my $is_optional = ($group =~ m{\A \( ([^)]+) \) \z}xms);
        $group = $1 if $is_optional;

        my $gid = Munin::Node::OS->get_gid($group);

        croak "Group '$group' required for '$service' does not exist"
            unless defined $gid || $is_optional;

        if (!defined $gid && $is_optional) {
            carp "DEBUG: Skipping OPTIONAL nonexisting group '$group'"
                if $config->{DEBUG};
            next;
        }
        push @groups, $gid;
    }

    # Support running with more than one group in effect. See documentation on
    # $EFFECTIVE_GROUP_ID in the perlvar(1) manual page.  Need to specify the
    # primary group twice: once for setegid(2), and once for setgroups(2).
    if (scalar(@groups) != 0) {
        return ($groups[0], join ' ', $groups[0], @groups);
    }
    return ($default_gid, join ' ', ($default_gid) x 2);
}


sub change_real_and_effective_user_and_group
{
    my ($self, $service) = @_;

    my $root_uid = 0;
    my $root_gid = 0;

    my $sconf = $config->{sconf}{$service};

    if ($REAL_USER_ID == $root_uid) {
        # Resolve UIDs now, as they are not resolved when the config was read.
        my $uid = $self->_resolve_uid($service);

        # Ditto for groups
        my ($rgid, $egids) = $self->_resolve_gids($service);

        eval {
            if ($Munin::Common::Defaults::MUNIN_HASSETR) {
                print STDERR "# Setting /rgid/ruid/ to /$rgid/$uid/\n"
                    if $config->{DEBUG};
                Munin::Node::OS->set_real_group_id($rgid) unless $rgid == $root_gid;
                Munin::Node::OS->set_real_user_id($uid)   unless $uid  == $root_uid;
            }

            print STDERR "# Setting /egid/euid/ to /$egids/$uid/\n"
                if $config->{DEBUG};
            Munin::Node::OS->set_effective_group_id($egids) unless $rgid == $root_gid;
            Munin::Node::OS->set_effective_user_id($uid)    unless $uid  == $root_uid;
        };

        if ($EVAL_ERROR) {
            CRITICAL("# FATAL: Plugin '$service' Can't drop privileges: $EVAL_ERROR.");
            exit 1;
        }
    }
    elsif (defined $sconf->{user} or defined $sconf->{groups}) {
        print "# Warning: Root privileges are required to change user/group.  "
            . "The plugin may not behave as expected.\n";
    }

    return;
}


sub exec_service
{
    my ($self, $service, $arg) = @_;

    # XXX - Create the statedir for the user
    my $uid = $self->_resolve_uid($service);
    Munin::Node::OS->mkdir_subdir("$Munin::Common::Defaults::MUNIN_PLUGSTATE", $uid);

    $self->change_real_and_effective_user_and_group($service);

    unless (Munin::Node::OS->check_perms_if_paranoid("$self->{servicedir}/$service")) {
        ERROR("Error: unsafe permissions on $service. Bailing out.");
        exit 2;
    }

    $self->export_service_environment($service);

    Munin::Node::OS::set_umask();

    my @command = grep defined, _service_command($self->{servicedir}, $service, $arg);
    print STDERR "# About to run '", join (' ', @command), "'\n"
        if $config->{DEBUG};

    exec @command;
}


# Returns the command for the service and (optional) argument, expanding '%c'
# as the original command (see 'command' directive in
# <http://munin-monitoring.org/wiki/plugin-conf.d>).
sub _service_command
{
    my ($dir, $service, $argument) = @_;

    my @run;
    my $sconf = $config->{sconf};

    if ($sconf->{$service}{command}) {
        for my $t (@{ $sconf->{$service}{command} }) {
            # Unfortunately, every occurrence of %c will be expanded,
            # even if we want to pass it unmodified to the target command,
            # because we parse the original string during the config
            # parsing step, at which we do not yet know the
            # replacement value for %c. It is probably a minor inconvenience,
            # though, since who will ever need to pass "%c" in a place
            # like that?
            if ($t =~ s/%c/$dir\/$service/g) {
                push @run, ($t, $argument);
            } else {
                push @run, ($t);
            }
        }
    }
    else {
        @run = ("$dir/$service", $argument);
    }

    return @run;
}


sub fork_service
{
    my ($self, $service, $arg) = @_;

    my $timeout = $config->{sconf}{$service}{timeout}
               || $self->{timeout};

    my $run_service = sub {
        $self->exec_service($service, $arg);
        # shouldn't be reached
        print STDERR "# ERROR: Failed to exec.\n";
        exit 42;
    };

    return Munin::Node::OS->run_as_child($timeout, $run_service);
}


1;

__END__


=head1 NAME

Munin::Node::Service - Methods related to handling of Munin services


=head1 SYNOPSIS

 my $services = Munin::Node::Service->new(timeout => 30);
 $services->prepare_plugin_environment;
 if ($services->is_a_runnable_service($file_name)) {
    $services->fork_service($file_name);
 }

=head1 METHODS

=over

=item B<new>

 my $services = Munin::Node::Service->new(%args);

Constructor.  All arguments are optional.  Valid arguments are:

=over 8

=item C<servicedir>

The directory that will be searched for services.

=item C<defuser>, C<defgroup>

The default uid and gid that services will run as.  Service-specific user and
group directives (as set by the service configuration files) will override
this.

=item C<timeout>

The default timeout for services.  Services taking longer than this to run will
be killed.  Service-specific timeouts will (as set in the service configuration
files) will override this value.

=back

=item B<is_a_runnable_service>

 my $bool = $services->is_a_runnable_service($file_name);

Runs miscellaneous tests on $file_name in the service directory, to try and
establish whether it is a runnable service.

=item B<list>
  
  my @services = $services->list;

Returns a list of all the runnable services in the directory.

=item B<prepare_plugin_environment>

 $services->prepare_plugin_environment(@services);

Carries out various tasks that plugins require before being run, such as
loading service configurations and exporting common environment variables.

=item B<export_service_environment>

 $services->export_service_enviromnent($service);

Exports all the environment variables specific to service $service.

=item B<change_real_and_effective_user_and_group>

 $service->change_real_and_effective_user_and_group($service);

Changes the current process' effective group and user IDs to those specified in
the configuration, or the default user or group otherwise.  Also changes the
real group and user IDs if the operating system supports it.

On failure, causes the process to exit.

=item B<exec_service>

 $service->exec_service($service, [$argument]);

Replaces the current process with an instance of service $service in
$directory, running with the correct environment and privileges.

This function never returns.  The process will exit(2) if the service to be run
failed the paranoia check.

=item B<fork_service>

 $result = $service->fork_service($service, [$argument]);

Identical to exec_service(), except it runs the service in a subprocess.  If
the service takes longer than the timeout, it will be terminated.

Returns a hash reference containing (among other things) the service's output
and exit value.  (See documentation for run_as_child() in
L<Munin::Node::Service> for a comprehensive description.)

=back

=cut
