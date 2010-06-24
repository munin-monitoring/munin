# vim: sw=4 : ts=4 : et
use warnings;
use strict;

use Test::More tests => 10;
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

