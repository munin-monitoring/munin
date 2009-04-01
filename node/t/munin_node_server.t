use warnings;
use strict;

use Test::More tests => 4;

use_ok('Munin::Node::Server');

no warnings;
*Munin::Node::Server::_net_write = sub {};
use warnings;

{
    my $session = {};
    Munin::Node::Server::_negotiate_session_capabilities($session, 'foo');

    is_deeply($session, {
        capabilities => {
            foo => 1,
        },
    });
}

{
    my $session = {};
    Munin::Node::Server::_negotiate_session_capabilities($session, '');

    is_deeply($session, {
        capabilities => {
        },
    });
}

{
    my $session = {};
    Munin::Node::Server::_negotiate_session_capabilities($session, 'foo baziiing');

    is_deeply($session, {
        capabilities => {
            foo => 1,
        },
    });
}
