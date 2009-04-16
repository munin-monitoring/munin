package Munin::Node::Service;

use warnings;
use strict;

use English qw(-no_match_vars);
use Carp;

use Munin::Node::Config;
use Munin::Node::OS;
use Munin::Node::Logger;

use Munin::Common::Defaults;

my $config = Munin::Node::Config->instance();


sub is_a_runnable_service {
    my ($class, $file) = @_;
    
    my $path = "$config->{servicedir}/$file";

    return unless -f $path && -x _;

    # FIX isn't it enough to check that the file is executable and not
    # in 'ignores'? Can hidden files and config files be
    # unintantionally executable? What does config files do in the
    # service directory? Shouldn't we complain if there is junk in the
    # service directory?
    return if $file =~ m/^\./;               # Hidden files
    return if $file =~ m/.conf$/;            # Config files

    return if $file !~ m/^([-\w.]+)$/;       # Skip if any weird chars
    $file = $1;                              # Not tainted anymore.

    foreach my $regex (@{$config->{ignores}}) {
        return if $file =~ /$regex/;
    }
    
    return 1;
}


sub export_service_environment {
    my ($class, $service) = @_;
    print STDERR "# Setting up environment\n" if $config->{DEBUG};

    my $env = $config->{sconf}{$service}{env};

    return unless defined $env;
    while (my ($k, $v) = each %$env) {
        print STDERR "# Environment $k = $v\n" if $config->{DEBUG};
        $ENV{$k} = $v;
    }
}


sub change_real_and_effective_user_and_group
{
    my ($class, $service) = @_;

    my $root_uid = 0;
    my $root_gid = 0;

    if ($REAL_USER_ID == $root_uid) {
        # Need to test for defined here since a user might be
        # specified with UID = 0
        my $uid = defined $config->{sconf}{$service}{user} 
                    ? $config->{sconf}{$service}{user}
                    : $config->{defuser};
        
        # Resolve unresolved UID now - as it is may not have been resolved
        # when the config was read.
        my $u = Munin::Node::OS->get_uid($uid);
        croak "User '$uid' is nonexistent." unless defined $u;
        my $dg  = $config->{defgroup};

        my $g = '';
        my $gid;

        if ( defined($gid = $config->{sconf}{$service}{group}) ) {
            $g = Munin::Node::OS->get_gid($gid);
            croak "Group '$gid' is nonexistent." unless $g ne '';
        }

        # Specify the default group twice: once for setegid(2), and once
        # for setgroups(2).  See perlvar for the gory details.
        my $gs = "$dg $dg $g";

        eval {
            if ($Munin::Common::Defaults::MUNIN_HASSETR) {
                Munin::Node::OS->set_real_group_id($dg) 
                      unless $dg == $root_gid;
                Munin::Node::OS->set_real_user_id($u)
                      unless $u == $root_uid;
            }

            Munin::Node::OS->set_effective_group_id($gs) 
                  unless $dg == $root_gid;
            Munin::Node::OS->set_effective_user_id($u)
                  unless $u == $root_uid;
        };

        if ($EVAL_ERROR) {
            logger("Plugin \"$service\" Can't drop privileges: $EVAL_ERROR. "
                       . "Bailing out.\n");
            exit 1;
        }
    }
}


sub exec_service {
    my ($class, $service, $command) = @_;

    my %sconf = %{$config->{sconf}};

    POSIX::setsid();

    $class->change_real_and_effective_user_and_group($service);

    unless (Munin::Node::OS->check_perms("$config->{servicedir}/$service")) {
        logger ("Error: unsafe permissions on $service. Bailing out.");
        exit 2;
    }

    $class->export_service_environment($service);

    if (exists $sconf{$service}{command} && defined $sconf{$service}{command}) {
        my @run = ();
        for my $t (@{$sconf{$service}{command}}) {
            if ($t =~ /^%c$/) {
                push (@run, "$config->{servicedir}/$service", $command);
            } else {
                push (@run, $t);
            }
        }
        print STDERR "# About to run \"", join (' ', @run), "\"\n" if $config->{DEBUG};
        exec (@run) if @run;
    } else {
        exec "$config->{servicedir}/$service", $command;
    }
}


1;

__END__


=head1 NAME

Munin::Node::Service - Methods related to handling of Munin services


=head1 SYNOPSIS


 my $bool = Munin::Node::Service->is_a_runnable_service($file_name);


=head1 METHODS

=over

=item B<is_a_runnable_service>

 my $bool = Munin::Node::Service->is_a_runnable_service($file_name);

Runs miscellaneous tests on $file_name. These tests are intended to
verify that $file_name is a runnable service.

=item B<export_service_environment>

 Munin::Node::Service->export_service_enviromnent($service);

Exports all the environment variables specific to service $service.

=item B<change_real_and_effective_user_and_group>

 Munin::Node::Service->change_real_and_effective_user_and_group($service);

Changes the current process' effective group and user IDs to those specified
in the configuration, or the default user or group otherwise.  Also changes 
the real group and user IDs if the operating system supports it.

On failure, causes the process to exit.

=back

=cut

# vim:syntax=perl : ts=4 : expandtab
