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


###############################################################################
#                         _ H A S _ A C C E S S

{
    my $session = {peer_address => '127.0.0.1'};
    my $conf    = Munin::Node::Config->instance();
    $conf->reinitialize({});

    ok(Munin::Node::Server::_has_access($session), "Allow all");
}


{
    my $session = {peer_address => '127.0.0.1'};
    my $conf    = Munin::Node::Config->instance();
    $conf->reinitialize({
        allow_deny => [['allow', '^127\.0\.0\.1$']],
    });

    ok(Munin::Node::Server::_has_access($session), "Allow specific host");
}


{
    my $session = {peer_address => '127.0.0.1'};
    my $conf    = Munin::Node::Config->instance();
    $conf->reinitialize({
        allow_deny => [['deny', '^127\.0\.0\.1$']],
    });

    ok(!Munin::Node::Server::_has_access($session), "Deny specific host");
}


{
    my $session = {peer_address => '127.0.0.1'};
    my $conf    = Munin::Node::Config->instance();
    $conf->reinitialize({
        allow_deny => [['allow', '^10\.0\.0\.1$']],
    });

    ok(!Munin::Node::Server::_has_access($session), "Doesn't match allowed host -> denied");
}


{
    my $session = {peer_address => '127.0.0.1'};
    my $conf    = Munin::Node::Config->instance();
    $conf->reinitialize({
        allow_deny => [['deny', '^10\.0\.0\.1$']],
    });

    ok(Munin::Node::Server::_has_access($session), "Doesn't match denied host -> allowed");
}


