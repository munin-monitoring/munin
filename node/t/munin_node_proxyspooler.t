# vim: sw=4 : ts=4 : et
use warnings;
use strict;

use Test::More tests => 12;
use Test::Differences;
use Test::Deep;

use IO::Scalar;
use POSIX ();

use Munin::Node::ProxySpooler;


# till i fix up the debug output
no warnings;
local *Munin::Node::ProxySpooler::logger = sub {};
use warnings;


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


################################################################################

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


################################################################################

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

