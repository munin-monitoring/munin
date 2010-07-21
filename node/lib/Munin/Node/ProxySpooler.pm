package Munin::Node::ProxySpooler;

# $Id$

use strict;
use warnings;

use Net::Server::Daemonize qw( daemonize safe_fork );
use IO::Socket;
use List::MoreUtils qw( any );
use Time::HiRes qw( usleep ualarm gettimeofday );
use Carp;

use Munin::Common::Defaults;
use Munin::Node::Logger;
use Munin::Node::SpoolWriter;

use Munin::Node::Config;
my $config = Munin::Node::Config->instance;


sub new
{
    my ($class, %args) = @_;

    $args{spooldir} ||= $Munin::Common::Defaults::MUNIN_SPOOLDIR;

    $args{spool} = Munin::Node::SpoolWriter->new(spooldir => $args{spooldir});

    # don't want to run as root unless absolutely necessary.  but only root
    # can change user
    #
    # FIXME: these will need changing to root/root as and when it starts
    # running plugins
    $args{user}  = $< || $Munin::Common::Defaults::MUNIN_PLUGINUSER;
    $args{group} = $( || $Munin::Common::Defaults::MUNIN_GROUP;

    $args{host} ||= 'localhost';
    $args{port} ||= '4949';

    return bless \%args, $class;
}


sub run
{
    my ($class, %args) = @_;

    my $self = __PACKAGE__->new(%args);

    # Daemonzises, and runs for cover.
    daemonize($self->{user}, $self->{group}, $self->{pid_file});

    open STDERR, '>>', "$Munin::Common::Defaults::MUNIN_LOGDIR/munin-sched.log";
    STDERR->autoflush(1);
    # FIXME: reopen logfile on SIGHUP

    logger('Spooler starting up');

    # ready to actually do stuff!
    my $intervals = $self->_get_intervals();
    my $pollers   = $self->_launch_pollers($intervals);

    # Indiscriminately kill every process in the group with SIGTERM when asked
    # to quit.  this is just the list the Perl Cookbook suggests trapping.
    #
    # FIXME: might be better if this was implemented with sigtrap pragma.
    #
    # FIXME: bit of a race condition here, but the pollers shouldn't have nasty
    # things lying about in their %SIG.
    $SIG{INT} = $SIG{TERM} = $SIG{HUP} = sub {
        logger("Spooler caught SIG$_[0].  Shutting down");
        kill -15, $$;
        exit 0;
    };

    logger('Spooler going to sleep');

    # Reap any dead pollers
    while (my $deceased = wait) {
        if ($deceased < 0) {
            last if $!{ECHILD};  # all the children are dead!
            logger("wait() error: $!");
        }

        my $service = delete $pollers->{$deceased};

        my $exit   = ($? >> 8);
        my $signal = ($? & 127);
        logger("Poller $deceased ($service) exited with $exit/$signal");

        # Respawn the poller
        logger("Respawning poller for '$service'");
        my $new_pid = $self->_launch_single_poller($service, $intervals->{$service});
        $pollers->{$new_pid} = $service;
    }

    logger('Spooler shutting down');
    exit 0;
}


### SETUP ######################################################################

# queries the node for a list of services, and works out how often each one
# should be checked
sub _get_intervals
{
    my ($self) = @_;

    my %intervals;

    $self->_open_node_connection;

    my @nodes    = $self->_get_node_list            or die "No nodes\n";
    my @services = $self->_get_service_list(@nodes) or die "No services\n";

    foreach my $service (@services) {
        if (my $interval = $config->{sconf}{$service}{update_rate}) {
            logger("Setting interval for service '$service' from config")
                if $config->{DEBUG};
            $intervals{$service} = $interval;
            next;
        }
        else {
            logger("Fetching interval for service '$service' from node")
                if $config->{DEBUG};
            $intervals{$service} = $self->_service_interval(
                $self->_talk_to_node("config $service")
            );
        }
        logger("Interval is $intervals{$service} seconds") if $config->{DEBUG};
    }

    $self->_close_node_connection;

    return \%intervals;
}


# gets a list of all the nodes served by that node
sub _get_node_list { return (shift)->_talk_to_node('nodes'); }


# gets a list of every service on every node
sub _get_service_list
{
    my ($self, @nodes) = @_;
    my @services;

    foreach my $node (@nodes) {
        logger("Fetching services for node $node") if $config->{DEBUG};
        my $service_list = $self->_talk_to_node("list $node");

        if ($service_list) {
            logger("Got services $service_list") if $config->{DEBUG};
            push @services, split / /, $service_list;
        }
        else {
            logger("No services for $node") if $config->{DEBUG};
        }
    }

    return @services;
}


# takes the config response for the service, and returns the correct interval
sub _service_interval { /^update_rate (\d+)/ && return $1 foreach @_; return 300; }


#### GATHER DATA ###############################################################

# forks off a child for each process on the node, and sets them to work.
sub _launch_pollers
{
    my ($self, $intervals) = @_;

    my %pollers;

    while (my ($service, $interval) = each %$intervals) {
        my $poller_pid = $self->_launch_single_poller($service, $interval);
        $pollers{$poller_pid} = $service;
    }

    return \%pollers;
}


sub _launch_single_poller
{
    my ($self, $service, $interval) = @_;

    logger("Launching poller for '$service' with an interval of ${interval}s")
        if $config->{DEBUG};

    if (my $poller_pid = safe_fork()) {
        # report back to parent
        logger("Poller for '$service' running with pid $poller_pid")
            if $config->{DEBUG};
        return $poller_pid;
    }

    $0 .= " [$service]";

    # Fetch data
    _poller_loop($interval, sub {
        logger(sprintf "%s: %d %d", $service, gettimeofday);  # FIXME: for testing timing accuracy

        my @result = $self->_fetch_service($service);
        logger("Read " . scalar @result . " lines from $service")
            if $config->{DEBUG};

        $self->{spool}->write(time, $service, \@result);
    });

    exit 0;
}


# calls coderef $code every $interval seconds.
sub _poller_loop
{
    my ($interval, $code) = @_;

    $interval *= 1e6;  # it uses microseconds.

    # sleep a random amount.  should help spread the load up a bit.
    # then run $code every $interval seconds.
    #
    # FIXME: this will interact really really badly with any code that uses
    # sleep().
    $SIG{ALRM} = $code;
    ualarm(rand($interval), $interval);

    while (1) { sleep; }

    ualarm(0);

    return;
}


# connect to the node, fetch data, write it out to the spooldir.
sub _fetch_service
{
    my ($self, $service) = @_;

    $self->_open_node_connection;

    my @config = $self->_talk_to_node("config $service");
    push @config, $self->_talk_to_node("fetch $service")
        unless any {/\.value /} @config;

    $self->_close_node_connection;

    if (any { m{# (?:Timed out|Unknown service|Bad exit)} } @config) {
        return ();
    }

    return @config;
}


### NODE INTERACTION ###########################################################

# returns an open IO::Socket to the node, ready for reading.
sub _open_node_connection
{
    my ($self) = @_;

    logger("Opening connection to $self->{host}:$self->{port}")
        if $config->{DEBUG};

    $self->{socket} = IO::Socket::INET->new(
        PeerAddr => $self->{host},
        PeerPort => $self->{port},
        Proto    => 'tcp',
    ) or die "Failed to connect to node: $!\n";

    my $line = $self->_read_line or die "Failed to read banner\n";

    die "Service is not a Munin node (responded with '$line')\n"
        unless ($line =~ /^# munin node at /);

    # report capabilities to unlock all the special services
    $line = $self->_talk_to_node('cap multigraph dirtyconfig')
        or die "Failed to read node capabilities\n";

    return;
}


# closes the socket, and deletes it from the instance hash.
sub _close_node_connection { (delete $_[0]->{socket})->close; }


# prints $command to the node on $socket, and returns the response.
sub _talk_to_node
{
    my ($self, $command) = @_;

    my $multiline = ($command =~ m{^(?:nodes|config|fetch)});

    croak "multiline means scalar context" if $multiline and not wantarray;

    my $socket = $self->{socket};

    $self->_write_line($command);
    my @response = ($multiline) ? $self->_read_multiline() : $self->_read_line();

    return wantarray ? @response : shift @response;
}


# write a single line to the node
sub _write_line
{
    my ($self, $command) = @_;

    logger("DEBUG: > $command") if $config->{DEBUG};
    $self->{socket}->print($command, "\n") or die "Write error to socket: $!\n";

    return;
}


# read a single line from the node
sub _read_line
{
    my ($self) = @_;

    my $line = $self->{socket}->getline;
    defined($line) or die "Read error from socket: $!\n";
    chomp $line;
    logger("DEBUG: < $line") if $config->{DEBUG};

    return $line;
}


# read a multiline response from the node  (ie. up to but not including the
# '.' line at the end.
sub _read_multiline
{
    my ($self) = @_;
    my ($line, @response);

    push @response, $line until ($line = $self->_read_line) eq '.';

    return @response;
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

=item B<run(%args)>

Forks off a spooler daemon, and returns control to the caller.  'spooldir' key
should be the directory to write to.

=back

=cut

# vim: sw=4 : ts=4 : et
