package Munin::Master::Worker::Tests;
use base qw(Test::Class);
use Test::More;

use Munin::Master::Worker;

sub setup : Test(setup) {
    my $self = shift;
    $self->{worker}      = Munin::Master::Worker->new('worker with id');
    $self->{worker_noid} = Munin::Master::Worker->new();
}

sub class : Test {
    my $worker   = shift->{worker};
    isa_ok( $worker, 'Munin::Master::Worker' );
}

sub class_noparameter : Test {
    my $worker = shift->{worker_noid};
    isa_ok( $worker, 'Munin::Master::Worker' );
}

sub method__to_string : Test(2) {
    my $worker = shift->{worker};
    can_ok( $worker, 'to_string' );
    ok( $worker->to_string, 'to_string returns a true value' );
}

1;
