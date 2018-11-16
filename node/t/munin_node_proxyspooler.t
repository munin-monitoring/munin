# vim: sw=4 : ts=4 : et
use warnings;
use strict;

use Test::More tests => 32;
use Test::Differences;
use Test::Deep;

use IO::Scalar;
use POSIX ();
use Data::Dumper;
use Time::HiRes qw( tv_interval gettimeofday ualarm );
use File::Temp qw( tempdir );

use Munin::Node::ProxySpooler;

$Munin::Common::Defaults::MUNIN_SPOOLDIR = tempdir(CLEANUP => 1);

# the hostname and port of a node to test against.
my ($host, $port) = @ENV{qw( MUNIN_HOST MUNIN_PORT )};


### new
{
    my $spooler = new_ok 'Munin::Node::ProxySpooler' => [ ], 'no arguments' or next;
    cmp_deeply([ keys %$spooler ], superbagof(qw( spooldir spool user group port )), 'constructor sets defaults');
    isa_ok($spooler->{spool}, 'Munin::Node::SpoolWriter', 'SpoolWriter object was created');
}
{
    my $spooldir = POSIX::getcwd();

    my $spooler = new_ok 'Munin::Node::ProxySpooler' => [
        spooldir => $spooldir,
    ], 'spooldir provided' or next;

    is($spooler->{spooldir}, $spooldir, 'custom spooldir is being used');
    isa_ok($spooler->{spool}, 'Munin::Node::SpoolWriter', 'SpoolWriter object was created');
    is($spooler->{spool}->{spooldir}, $spooldir, 'SpoolWriter object is using the spooldir');
}


### NODE INTERACTION ###########################################################

### _open_node_connection
### _close_node_connection
SKIP: {
    skip 'Set MUNIN_HOST and MUNIN_PORT environment variables to the hostname and port of a node to test against', 2
        unless $host and $port;

    my $spooler = Munin::Node::ProxySpooler->new(
        host => $host,
        port => $port,
    ) or next;

    $spooler->_open_node_connection;

    my $socket = $spooler->{socket};

    print $socket "version\n";
    like(scalar(<$socket>), qr{version}, 'was able to read the version string');

    $spooler->_close_node_connection;
    ok(! exists($spooler->{socket}), 'Socket was deleted');
}


### _talk_to_node
SKIP: {
    skip 'Set MUNIN_HOST and MUNIN_PORT environment variables to the hostname and port of a node to test against', 1
        unless $host and $port;

    my $spooler = Munin::Node::ProxySpooler->new(
        host => $host,
        port => $port,
    ) or next;

    $spooler->_open_node_connection;

    eval { my $scalar = $spooler->_talk_to_node('nodes') };
    like($@, qr{scalar}, 'error if expecting a multiline response, but called in a scalar context');
}
SKIP: {
    skip 'Set MUNIN_HOST and MUNIN_PORT environment variables to the hostname and port of a node to test against', 1
        unless $host and $port;

    my $spooler = Munin::Node::ProxySpooler->new(
        host => $host,
        port => $port,
    ) or next;

    $spooler->_open_node_connection;

    my $socket = $spooler->{socket};

    like($spooler->_talk_to_node('version'), qr{version}, 'was able to read the version string');
}


### _write_line
{
    my $spooler = Munin::Node::ProxySpooler->new() or next;

    $spooler->{socket} = IO::Scalar->new(\(my $sent));

    $spooler->_write_line('line of text to write');
    is($sent, "line of text to write\n", 'Line was written to the socket, with a newline on the end');
}


### _read_line
{
    my $spooler = Munin::Node::ProxySpooler->new() or next;

    $spooler->{socket} = IO::Scalar->new(\"line of text to read\n");

    eq_or_diff(
        [ $spooler->_read_line() ],
        [ 'line of text to read' ],
        'read a single line from the socket, which was chomped'
    );
}


### _read_multiline
{
    my $spooler = Munin::Node::ProxySpooler->new() or next;

    $spooler->{socket} = IO::Scalar->new(\<<EOT);
node1.example.com
node2.example.com
.
EOT

    eq_or_diff(
        [ $spooler->_read_multiline() ],
        [ qw(
            node1.example.com
            node2.example.com
        ) ],
        'read a multiline response from the socket, but not the . that marks the end'
    );
}


### SETUP ######################################################################

### _service_interval
{
    my @config = (
        'graph_title CPU usage',
        'graph_order system user nice idle iowait irq softirq',
        'graph_args --base 1000 -r --lower-limit 0 --upper-limit 200',
        'system.label system',
    );
    is(Munin::Node::ProxySpooler::_service_interval(@config), 300, 'Default interval is 5 minutes');
}
{
    my @config = (
        'graph_title CPU usage',
        'graph_order system user nice idle iowait irq softirq',
        'graph_args --base 1000 -r --lower-limit 0 --upper-limit 200',

        'update_rate 86400',

        'system.label system',
    );
    is(Munin::Node::ProxySpooler::_service_interval(@config), 86400, 'Can override the default interval');
}


### _get_node_list
SKIP: {
    skip 'Set MUNIN_HOST and MUNIN_PORT environment variables to the hostname and port of a node to test against', 1
        unless $host and $port;

    my $spooler = Munin::Node::ProxySpooler->new(
        host => $host,
        port => $port,
    ) or next;

    $spooler->_open_node_connection;

    cmp_deeply([ $spooler->_get_node_list ], array_each(re('^[-\w.:]+$')), 'all the node names look reasonable');
}


### _get_service_list
SKIP: {
    skip 'Set MUNIN_HOST and MUNIN_PORT environment variables to the hostname and port of a node to test against', 2
        unless $host and $port;

    my $spooler = Munin::Node::ProxySpooler->new(
        host => $host,
        port => $port,
    ) or next;

    $spooler->_open_node_connection;

    my @services = $spooler->_get_service_list();
    ok(\@services, 'Got a list of services from the node') or next;

    cmp_deeply(\@services, array_each(re('^[-\w.:]+$')), 'all the services look reasonable');
}


### _get_intervals
SKIP: {
    skip 'Set MUNIN_HOST and MUNIN_PORT environment variables to the hostname and port of a node to test against', 2
        unless $host and $port;

    my $spooler = Munin::Node::ProxySpooler->new(
        host => $host,
        port => $port,
    ) or next;

    my $intervals = $spooler->_get_intervals() or next;

    cmp_deeply([ keys   %$intervals ], array_each(re('^[-\w.:]+$')), 'all the keys look like services');
    cmp_deeply([ values %$intervals ], array_each(re('^\d+$')),      'all the values look like times');
}
{
    my $spooler = Munin::Node::ProxySpooler->new();

    my $config = Munin::Node::Config->instance();
    $config->reinitialize({ sconf => { fnord => { update_rate => 100 } } });

    no warnings;
    local *Munin::Node::ProxySpooler::_open_node_connection = sub {};
    local *Munin::Node::ProxySpooler::_close_node_connection = sub {};

    local *Munin::Node::ProxySpooler::_get_service_list = sub { 'fnord' };
    use warnings;

    is_deeply($spooler->_get_intervals, { fnord => 100 }, 'Can override the interval through the config'); 
}


### GATHER DATA ################################################################


### _poller_loop
{
    my $ii = 10;
    my @times;
    my $poller = sub {
        if ($ii-- < 0) {
            ualarm(0);
            die;
        }
        push @times, [gettimeofday];
    };

    eval { Munin::Node::ProxySpooler::_poller_loop(0.01, $poller) };

    my $last = shift @times;
    my @intervals = map { my $interval = tv_interval($last, $_), $last = $_; $interval } @times;

    cmp_deeply(\@intervals, array_each(num(0.01, 0.005)), 'Callback takes less long than the interval');
}
TODO: {
    local $TODO = "select/ualarm interaction needs investigation";
    my $ii = 10;
    my @times;

    my $poller = sub {
        if ($ii-- < 0) {
            ualarm(0);
            die;
        }
        push @times, [gettimeofday];
        select(undef, undef, undef, 0.5);  # sleep without sleep()ing.
    };

    eval { Munin::Node::ProxySpooler::_poller_loop(0.3, $poller) };

    my $last = shift @times;
    my @intervals = map { my $interval = tv_interval($last, $_), $last = $_; $interval } @times;

    cmp_deeply(\@intervals, array_each(
        any(
            num(0.5,       0.005),
            num(0.5 + 0.3, 0.005),
        )
    ), 'Callback takes longer than the interval');
}
{
    my $ii = 10;
    my @times;

    my $poller = sub {
        if ($ii-- < 0) {
            ualarm(0);
            die;
        }
        push @times, [gettimeofday];
        select(undef, undef, undef, 0.1);  # sleep without sleep()ing.
    };

    eval { Munin::Node::ProxySpooler::_poller_loop(0.1, $poller) };

    my $last = shift @times;
    my @intervals = map { my $interval = tv_interval($last, $_), $last = $_; $interval } @times;

    cmp_deeply(\@intervals, array_each(
        any(
            num(0.1,       0.005),
            num(0.1 + 0.1, 0.005),
        )
    ), 'Callback takes about the same time as interval');
}


### _fetch_service
{
    my @config = (
        'graph_title Load average',
        'graph_category system',
        'load.label load',
    );
    my @fetch = (
        'load.value 0.25',
    );
    my @timeout = (
        '# Timed out',
    );
    my @unknown = (
        '# Unknown service',
    );
    my @badexit = (
        '# Bad exit',
    );

    no warnings;
    local *Munin::Node::ProxySpooler::_open_node_connection = sub {};
    local *Munin::Node::ProxySpooler::_close_node_connection = sub {};

    local *Munin::Node::ProxySpooler::_talk_to_node = sub {
        return $_[1] eq 'config normal' ? @config
             : $_[1] eq 'fetch normal'  ? @fetch

             : $_[1] eq 'config dirty'  ? (@config, @fetch)
             : $_[1] eq 'fetch dirty'   ? ('no need to fetch a dirty plugin')

             : $_[1] eq 'config timeout' ? @timeout
             : $_[1] eq 'fetch timeout'  ? ('should not fetch a plugin that timed out')

             : $_[1] eq 'config timeout2' ? @config
             : $_[1] eq 'fetch timeout2'  ? @timeout

             : $_[1] eq 'config unknown' ? @unknown
             : $_[1] eq 'fetch unknown'  ? ('should not fetch a plugin that does not exist')

             : $_[1] eq 'config badexit' ? @badexit
             : $_[1] eq 'fetch badexit'  ? ('should not fetch a plugin that fell over during config')

             : $_[1] eq 'config badexit2' ? @config
             : $_[1] eq 'fetch badexit2'  ? @badexit

             : die "unknown command $_[1]\n";
    };
    use warnings;

    my @tests = (
        # name, expected, message
        [ 'normal',    [ @config, @fetch ], 'normal service' ],

        [ 'dirty',     [ @config, @fetch ], 'dirty service'  ],

        [ 'timeout',   [],                  'timed out during config' ],
        [ 'timeout2',  [],                  'timed out during fetch' ],

        [ 'unknown',   [],                  'unknown service' ],

        [ 'badexit',   [],                  'bad exit from service during config' ],
        [ 'badexit2',  [],                  'bad exit during fetch' ],
    );

    foreach my $test (@tests) {
        my ($name, $expected, $msg) = @$test;

        my $spooler = Munin::Node::ProxySpooler->new()
            or fail('Could not create a new ProxySpooler');

        my @response = $spooler->_fetch_service($name);
        eq_or_diff(\@response, $expected, $msg);
    }
}


