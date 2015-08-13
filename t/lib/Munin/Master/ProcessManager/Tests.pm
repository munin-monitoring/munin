package Munin::Master::ProcessManager::Tests;
use base qw(Test::Class);
use Test::More;
# use Test::Deep;

use Munin::Master::ProcessManager;

sub setup : Test(setup) {
    my $self = shift;

    $self->{manager} = Munin::Master::ProcessManager->new(
        sub{ ok(1, 'async complete')}
    );

    $self->{worker} = Munin::Master::Worker->new();

}

sub class : Test(1) {
    my $manager = shift->{manager};
    isa_ok($manager, 'Munin::Master::ProcessManager');
}

sub method__add_workers : Test {
    my $manager = shift->{manager};
    can_ok($manager, 'add_workers');
}

sub method__start_work : Test {
    my $manager = shift->{manager};
    can_ok($manager, 'start_work');
}

1;
