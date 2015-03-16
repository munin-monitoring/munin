package Munin::Node::ProxySpooler;


use strict;
use warnings;

use Net::Server::Daemonize qw( daemonize safe_fork unlink_pid_file );
use IO::Socket;
use List::MoreUtils qw( any );
use Time::HiRes qw( ualarm gettimeofday );
use Carp;

use Munin::Common::Defaults;
use Munin::Node::SpoolWriter;

use Munin::Node::Config;
my $config = Munin::Node::Config->instance;


sub new
{
    my ($class, %args) = @_;

    $args{spooldir} ||= $Munin::Common::Defaults::MUNIN_SPOOLDIR;

    $args{spool} = Munin::Node::SpoolWriter->new(spooldir => $args{spooldir});

    # don't want to run as root unless absolutely necessary.  but only root can
    # change user
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

    croak "No pidfile specified" unless $args{pid_file};

    # Daemonzises, and runs for cover.
    daemonize($self->{user}, $self->{group}, $self->{pid_file});
    $self->{have_pid_file}++;

    open STDERR, '>>', "$Munin::Common::Defaults::MUNIN_LOGDIR/munin-sched.log";
    STDERR->autoflush(1);
    # FIXME: reopen logfile on SIGHUP

    INFO('Spooler starting up');

    # Indiscriminately kill every process in the group with SIGTERM when asked
    # to quit.  this is just the list of signals the Perl Cookbook suggests
    # trapping.
    #
    # FIXME: might be better if this was implemented with sigtrap pragma.
    #
    # !!!NOTE!!! this should always be the same list as the one down there in
    # _launch_single_poller()
    $SIG{INT} = $SIG{TERM} = $SIG{HUP} = sub {
        NOTICE("Spooler caught SIG$_[0].  Shutting down");
        kill -15 => $$;

        if ($self->{have_pid_file}) {
            DEBUG('Removing pidfile') if $config->{DEBUG};
            unlink_pid_file($self->{pid_file});
        }

        exit 0;
    };

    $self->_launch_pollers();

    INFO('Spooler going to sleep');

    # Reap any dead pollers
    while (my $deceased = wait) {
        if ($deceased < 0) {
            last if $!{ECHILD};  # all the children are dead!

            ERROR("wait() error: $!");
            next;
        }

        $self->_restart_poller($deceased);
    }

    NOTICE('Spooler shutting down');
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

    my @services = $self->_get_service_list() or die "No services\n";

    foreach my $service (@services) {
        if (my $interval = $config->{sconf}{$service}{update_rate}) {
            DEBUG("Setting interval for service '$service' from config")
                if $config->{DEBUG};
            $intervals{$service} = $interval;
            next;
        }
        else {
            DEBUG("Fetching interval for service '$service' from node")
                if $config->{DEBUG};
            $intervals{$service} = $self->_service_interval(
                $self->_talk_to_node("config $service")
            );
        }
        DEBUG("Interval is $intervals{$service} seconds") if $config->{DEBUG};
    }

    $self->_close_node_connection;

    $self->{intervals} = \%intervals;

    return \%intervals;
}


# gets a list of all the nodes served by that node
sub _get_node_list { return (shift)->_talk_to_node('nodes'); }


# gets a list of every service on every node
sub _get_service_list
{
    my ($self) = @_;
    my @services;

    my @nodes = $self->_get_node_list() or die "No nodes\n";

    foreach my $node (@nodes) {
        DEBUG("Fetching services for node $node") if $config->{DEBUG};
        my $service_list = $self->_talk_to_node("list $node");

        if ($service_list) {
            DEBUG("Got services $service_list") if $config->{DEBUG};
            push @services, split / /, $service_list;
        }
        else {
            DEBUG("No services for $node") if $config->{DEBUG};
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
    my ($self) = @_;

    my %pollers;

    my $intervals = $self->_get_intervals();

    while (my ($service, $interval) = each %$intervals) {
        my $poller_pid = $self->_launch_single_poller($service, $interval);
    }

    return;
}


sub _launch_single_poller
{
    my ($self, $service, $interval) = @_;

    DEBUG("Launching poller for '$service' with an interval of ${interval}s")
        if $config->{DEBUG};

    if (my $poller_pid = safe_fork()) {
        DEBUG("Poller for '$service' running with pid $poller_pid")
            if $config->{DEBUG};

        $self->{pollers}{$poller_pid} = $service;

        return;
    }

    # don't want the pollers to have the kill-all-the-process-group handler
    # installed.  !!!NOTE!!! this should always be the same list as the one up
    # there in run()
    delete @SIG{qw( INT TERM HUP )};

    $0 .= " [$service]";

    # Fetch data
    _poller_loop($interval, sub {
        INFO(sprintf "%s: %d %d", $service, gettimeofday);  # FIXME: for testing timing accuracy

        my @result = $self->_fetch_service($service);
        DEBUG("Read " . scalar @result . " lines from $service")
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


# takes the PID of a dead poller, and respawns it.
sub _restart_poller
{
    my ($self, $pid) = @_;

    my $service = delete $self->{pollers}{$pid};

    my $exit   = ($? >> 8);
    my $signal = ($? & 127);
    NOTICE("Poller $pid ($service) exited with $exit/$signal");

    # avoid restarting the poller if it was last restarted too recently.
    if (time - ($self->{poller_restarted}{$service} || 0) < 10) {
        ERROR("Poller for '$service' last restarted at $self->{poller_restarted}{$service}.  Giving up.");
        return;
    }

    # Respawn the poller
    INFO("Respawning poller for '$service'");
    $self->_launch_single_poller($service, $self->{intervals}{$service});
    $self->{poller_restarted}{$service} = time;

    return;
}

### NODE INTERACTION ###########################################################

# returns an open IO::Socket to the node, ready for reading.
sub _open_node_connection
{
    my ($self) = @_;

    DEBUG("Opening connection to $self->{host}:$self->{port}")
        if $config->{DEBUG};

    $self->{socket} = IO::Socket::INET->new(
        PeerAddr => $self->{host},
        PeerPort => $self->{port},
        Proto    => 'tcp',
    ) or die "Failed to connect to node on $self->{host}:$self->{port}: $!\n";

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

    DEBUG("DEBUG: > $command") if $config->{DEBUG};
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
    DEBUG("DEBUG: < $line") if $config->{DEBUG};

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

  Munin::Node::ProxySpooler->run(spooldir => '/var/spool/munin');
  # never returns.

  # meanwhile, in another process
  my $spoolreader = Munin::Node::Spoolreader->new(
      spooldir => '/var/spool/munin',
  );
  print $spoolreader->fetch(123456789);

=head1 METHODS

=over 4

=item B<new>

  Munin::Node::ProxySpooler->new(%args);

Constructor.  It is called automatically by the C<run> method, so probably
isn't of much use otherwise.

=item B<run>

  Munin::Node::ProxySpooler->run(%args);

Daemonises the current process, and starts fetching data from a Munin node.

Never returns.  The process will clean up and exit(0) upon receipt of SIGINT,
SIGTERM or SIGHUP.

=over 8

=item C<spooldir>

The directory to write results to.  Optional.

=item C<host>, C<port>

The host and port the spooler will gather results from.  Defaults to
C<localhost> and C<4949> respectively, which should be acceptable for most
purposes.

=item C<pid_file>

The pidfile to use.  Required.

=back

=back

=cut

# vim: sw=4 : ts=4 : et
