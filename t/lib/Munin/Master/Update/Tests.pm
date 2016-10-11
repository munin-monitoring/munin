package Munin::Master::Update::Tests;
use base qw(Test::Class);
use Test::More;
use Test::MockObject;

use File::Temp qw(tempdir);

use Munin::Master::Update;
use Munin::Master::Config;

sub setup : Test(setup) {
    my $self = shift;

    $self->{update} = Munin::Master::Update->new();

    $self->{config} = Munin::Master::Config->instance()->{config};

}

sub class : Test(1) {
    my $update = shift->{update};
    isa_ok( $update, 'Munin::Master::Update' );
}

sub method__run : Test(2) {
    my $self   = shift;
    my $update = $self->{update};

    can_ok( $update, 'run' );

    return 'Set TEST_HEAVY to use these tests'
      . ' and provide a munin node on localhost:4949'
      unless $ENV{TEST_HEAVY};

    $self->{mock} = Test::MockObject->new();
    $self->{mock}->fake_module(
        'RRDs',
        'create' => sub(@) { },
        'error'  => sub { },
    );

    my $config = Munin::Master::Config->instance()->{config};
    $config->{dbdir}  = tempdir( CLEANUP => 1 );
    $config->{rundir} = tempdir( CLEANUP => 1 );

  TODO: {
        local $TODO = 'Not implemented yet';
        ok( eval{$update->run} );
    }
}

1;
