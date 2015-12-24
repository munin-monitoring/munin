package Munin::Master::ProcessManager::Tests;
use base qw(Test::Class);
use Test::More;

# use Test::Deep;

use Munin::Master::ProcessManager;
use Munin::Master::Worker;

sub setup : Test(setup) {
    my $self = shift;

    $self->{manager} = Munin::Master::ProcessManager->new(
        sub { ok( 1, 'result_callback reached' ) },
        sub { ok( 0, 'error_callback reached' ) },
    );

    $self->{worker} = Munin::Master::Worker->new();
}

sub class_without_result_callback : Test {
    my $self = shift;

    ok(
        !eval { Munin::Master::ProcessManager->new },
        'should fail without mandatory result_callback'
    );
}

sub class_without_error_callback : Test {
    my $self = shift;

    ok(
        Munin::Master::ProcessManager->new( sub { 1 } ),
        'should not fail without optional error_callback'
    );
}

sub class : Test(1) {
    my $manager = shift->{manager};
    isa_ok( $manager, 'Munin::Master::ProcessManager' );
}

sub method__add_workers : Test(3) {
    my $self    = shift;
    my $manager = $self->{manager};
    my $worker  = $self->{worker};

    can_ok( $manager, 'add_workers' );
    ok( $manager->add_workers($worker) );

    ok(
        !eval { $manager->add_workers('test imposter') },
        'Adding non-worker objects should fail'
    );
}

sub method__start_work : Test(3) {
    my $self    = shift;
    my $manager = $self->{manager};
    my $worker  = $self->{worker};

    can_ok( $manager, 'start_work' );

    # After this step, tests requires sockets and processes.
    return ('Set TEST_MEDIUM to run these tests')
      unless $ENV{TEST_MEDIUM};

    ok( $manager->add_workers($worker), 'setup, add worker' );

    local $TODO = 'testing of start_work unimplemented';
    ok( eval { $manager->start_work } );
}

1;
