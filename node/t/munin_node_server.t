use warnings;
use strict;

use Test::More tests => 4;

use_ok('Munin::Node::Server');

no warnings;
*Munin::Node::Server::_net_write = sub {};
use warnings;



###############################################################################
#                           C A P A B I L I T I E S


{
    my $session = {};
    Munin::Node::Server::_negotiate_session_capabilities($session, 'foo');

    is_deeply($session, {
        capabilities => {
            foo => 1,
        },
    },

    "Negotiate a single capability");
}

{
    my $session = {};
    Munin::Node::Server::_negotiate_session_capabilities($session, '');

    is_deeply($session, {
        capabilities => {
        },
    },
    
    "No capabilities offered");
}

{
    my $session = {};
    Munin::Node::Server::_negotiate_session_capabilities($session, 'foo baziiing');

    is_deeply($session, {
        capabilities => {
            foo => 1,
        },
    },
    
    "Ignore unknown capability");
}


