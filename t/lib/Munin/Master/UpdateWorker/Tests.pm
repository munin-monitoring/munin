package Munin::Master::UpdateWorker::Tests;
use base qw(Test::Class);
use Test::More;
use Test::Deep;

use Munin::Master::UpdateWorker;
use Munin::Master::Config;
use Munin::Master::Group;
use Munin::Master::Host;
use File::Temp qw(tempdir);

sub setup : Test(setup) {
    my $self = shift;

    $self->{config} = Munin::Master::Config->instance()->{config};

    $self->{group} = Munin::Master::Group->new('example.com');

    $self->{host} =
      Munin::Master::Host->new( 'localhost', $self->{group} );

    $self->{worker} = Munin::Master::Worker->new();

    $self->{updateworker} =
      Munin::Master::UpdateWorker->new( $self->{host}, $self->{worker} );

}

sub class : Test(1) {
    my $uw = shift->{updateworker};
    isa_ok( $uw, 'Munin::Master::UpdateWorker' );
}

sub method__do_work : Test(2) {
    my $self = shift;
    my $uw   = $self->{updateworker};

    can_ok( $uw, 'do_work' );

    return 'Set TEST_HEAVY to run these tests, and provide a munin node on localhost:4949'
      unless $ENV{TEST_HEAVY};

    $self->{config}->{dbdir}  = tempdir( CLEANUP => 1 );
    $self->{config}->{rundir} = tempdir( CLEANUP => 1 );

    is( $uw->do_work, undef,
        'do_work should return undef unless actually connected' );
}

1;
