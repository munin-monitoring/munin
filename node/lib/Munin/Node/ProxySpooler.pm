package Munin::Node::ProxySpooler;

# $Id$

use strict;
use warnings;

use Net::Server::Daemonize qw( daemonize );
use IO::Socket;
use Carp;

use Munin::Common::Defaults;
use Munin::Node::Logger;
use Munin::Node::SpoolWriter;


sub new
{
    my ($class, %args) = @_;

    $args{spool} = Munin::Node::SpoolWriter->new(spooldir => $args{spooldir});

    # don't want to run as root unless absolutely necessary.  but only root
    # can change user
    #
    # FIXME: these will need changing to root/root as and when it starts
    # running plugins
    $args{user}  = $< || $Munin::Common::Defaults::MUNIN_PLUGINUSER;
    $args{group} = $( || $Munin::Common::Defaults::MUNIN_GROUP;

    # FIXME: should get the host and port from munin-node.conf
    @args{qw( host port )} = ('localhost', '4949');

    return bless \%args, $class;
}


sub run
{
    my ($class, %args) = @_;

    my $self = __PACKAGE__->new(%args);

    # Daemonzises, and runs for cover.
    daemonize($self->{user}, $self->{group}, $self->{pidfile});

    open STDERR, '>>', "$Munin::Common::Defaults::MUNIN_LOGDIR/munin-sched.log";
    STDERR->autoflush(1);
    # FIXME: reopen logfile on SIGHUP

    logger('Spooler ready');

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
