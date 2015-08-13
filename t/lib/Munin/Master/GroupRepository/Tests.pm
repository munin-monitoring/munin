package Munin::Master::GroupRepository::Tests;
use base qw(Test::Class);
use Test::More;

use Munin::Master::GroupRepository;

sub setup : Test(setup) {
    my $self = shift;
    $self->{group} = Munin::Master::GroupRepository->new('testing;testing');
}

sub class : Test {
    my $group = shift->{group};
    isa_ok($group, 'Munin::Master::GroupRepository');
}

sub class_parameter : Test {
    my $group = shift->{group};
    is($group->{groups}, 'testing;testing');
}

1;
