package Munin::Node::Session::Tests;
use base qw(Test::Class);
use Test::More;
use Test::Deep;

use Munin::Node::Session;

sub setup : Test(setup) {
    my $self = shift;

    $self->{session} = Munin::Node::Session->new();

}

sub class_defaults : Test {
    my $session = shift->{session};

    cmp_deeply(
        $session,

        all(
            isa('Munin::Node::Session'),
            noclass(
                {
                    capabilities => ignore(),
                    peer_address => ignore(),
                    tls_started  => ignore(),
                }
            ),
        )
    );
}

1;
