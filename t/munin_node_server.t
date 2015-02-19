# vim: sw=4 : et : ts=4
use warnings;
use strict;

use Test::More tests => 9;

use_ok('Munin::Node::Server');

no warnings;
*Munin::Node::Server::_net_write = sub {};
use warnings;


###############################################################################
#                           C A P A B I L I T I E S

{
    my $session = {};
    Munin::Node::Server::_negotiate_session_capabilities($session, 'multigraph');

    is_deeply($session, {
        server_capabilities => {
            multigraph => 1,
        },
    },
    "Negotiate a single capability");
}
{
    my $session = {};
    Munin::Node::Server::_negotiate_session_capabilities($session, '');

    is_deeply($session, {
        server_capabilities => {
        },
    },
    "No capabilities offered");
}
{
    my $session = {};
    Munin::Node::Server::_negotiate_session_capabilities($session, "dirtyconfig multigraph\r");

    is_deeply($session, {
        server_capabilities => {
            dirtyconfig => 1,
            multigraph  => 1,
        },
    },
    "Ignore trailing CR on capabiltities string.");
}


### capabilities are reported to the plugins.
{
    my $session = {};
    Munin::Node::Server::_negotiate_session_capabilities($session, '');
    ok(! $ENV{MUNIN_CAP_DIRTYCONFIG}. 'No dirtyconfig allowed');
}
{
    my $session = {};
    Munin::Node::Server::_negotiate_session_capabilities($session, 'multigraph');
    ok(! $ENV{MUNIN_CAP_DIRTYCONFIG}. 'Still no dirtyconfig allowed');
}
{
    my $session = {};
    Munin::Node::Server::_negotiate_session_capabilities($session, 'dirtyconfig multigraph');
    ok($ENV{MUNIN_CAP_DIRTYCONFIG}. 'Dirtyconfig allowed when server claims it as a capability');
}


{
    no warnings;
    local *Munin::Node::Server::_net_write = sub { return $_[1] };
    use warnings;

    my $session = {};

    is(
        Munin::Node::Server::_negotiate_session_capabilities($session, 'dirtyconfig multigraph'),
        "cap multigraph dirtyconfig\n",
        'Node sends capabilities back to the server'
    );

    $session = {};

    is(
        Munin::Node::Server::_negotiate_session_capabilities($session, ''),
        "cap multigraph dirtyconfig\n",
        q{Node sends capabilities back to the server, even when the server provided none}
    );

}

