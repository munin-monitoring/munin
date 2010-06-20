package Munin::Node::ProxySpooler;

# $Id$

use strict;
use warnings;

use Net::Server::Daemonize qw( safe_fork daemonize );
use Carp;

use Munin::Common::Defaults;
use Munin::Node::Logger;
use Munin::Node::SpoolWriter;


sub run
{
    my ($self, %args) = @_;

    # check arguments before forking, so it's easier to see what's gone wrong
    my $spoolwriter = Munin::Node::SpoolWriter->new(spooldir => $args{spooldir});

    # don't want the child to be running as root unless absolutely necessary.
    # but only root can change user
    #
    # FIXME: these will need changing to root/root as and when it starts
    # running plugins
    my $user  = $< || $Munin::Common::Defaults::MUNIN_PLUGINUSER;
    my $group = $( || $Munin::Common::Defaults::MUNIN_GROUP;

    my $pidfile = "$Munin::Common::Defaults::MUNIN_STATEDIR/munin-sched.pid";

    logger("Running spooler as uid = $user, gid = $group");

    if (my $child_pid = safe_fork()) {
        # Parent.  just return control to caller
        logger("Forked off spooler daemon as pid $child_pid\n");
        return;
    }

    # Child daemonzises, and runs for cover.
    daemonize($user, $group, $pidfile);

    open STDERR, '>>', "$Munin::Common::Defaults::MUNIN_LOGDIR/munin-sched.log";
    # FIXME: STDERR should autoflush
    # FIXME: reopen logfile on SIGHUP

    $0 .= ' [scheduler]';  # set a more appropriate process name, for ps

    # FIXME: should get the host and port from munin-node.conf
    @args{qw( host port )} = ('localhost', '4949');

    # ready to actually do stuff!

    sleep;

    logger('Spooler shutting down');
    exit 0;
}


1;

__END__

=head1 NAME

Munin::Node::ProxySpooler - Daemon to gather spool information by querying a
munin-node instance.

=head1 SYNOPSIS

  Munin::Node::ProxySpooler->run(%args);

=head1 METHODS

=over 4

=head2 B<run(%args)>

Forks off a spooler daemon, and returns control to the caller.  'spooldir' key
should be the directory to write to.

=back

=cut

# vim: sw=4 : ts=4 : et
