# vim: sw=4 : ts=4 : et
use warnings;
use strict;

use Test::More tests => 22;
use Test::Differences;
use Test::Deep;

use IO::Scalar;
use POSIX ();

use Munin::Node::ProxySpooler;


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
    skip 'Set MUNIN_HOST and MUNIN_PORT environment variables to the hostname and port of a node to test against', 1
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
    skip 'Set MUNIN_HOST and MUNIN_PORT environment variables to the hostname and port of a node to test against', 3
        unless $host and $port;

    my $spooler = Munin::Node::ProxySpooler->new(
        host => $host,
        port => $port,
    ) or next;

    $spooler->_open_node_connection;

    my @nodes = $spooler->_get_node_list;

    my @services = $spooler->_get_service_list($nodes[0]);
    ok(\@services, 'Got a list of services from the node') or next;

    cmp_deeply(\@services, array_each(re('^[-\w.:]+$')), 'all the services look reasonable');

    ###############

    @services = $spooler->_get_service_list('fnord.example.com');
    is(scalar(@services), 0, 'No services for an unknown node') or next;
}


### _get_intervals
SKIP: {
    skip 'Set MUNIN_HOST and MUNIN_PORT environment variables to the hostname and port of a node to test against', 2
        unless $host and $port;

    my $spooler = Munin::Node::ProxySpooler->new(
        host => $host,
        port => $port,
    ) or next;

    $spooler->_open_node_connection;

    my $intervals = $spooler->_get_intervals or next;

    cmp_deeply([ keys   %$intervals ], array_each(re('^[-\w.:]+$')), 'all the keys look like services');
    cmp_deeply([ values %$intervals ], array_each(re('^\d+$')),      'all the values look like times');
}

