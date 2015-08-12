package Munin::Master::Group::Tests;
use base qw(Test::Class);
use Test::More;
use Test::Deep;

use Munin::Master::Group;

sub setup : Test(setup) {
    my $self = shift;

    $self->{group} = Munin::Master::Group->new('example.com');

    $self->{host1} = Munin::Master::Host->new(
        'host1.example.com',
        $self->{group},
        { address => '192.0.2.1'}
    );

    $self->{host2} = Munin::Master::Host->new(
        'host2.example.com',
        $self->{group},
        { address => '192.0.2.2'}
    );

}

sub object : Test(1) {
    my $group = shift->{group};
    isa_ok($group, 'Munin::Master::Group');
}

sub object_parameters : Test {
    my $group = shift->{group};
    is($group->{group_name}, 'example.com', 'group name');
}

sub object_defaults : Test {
    my $group = shift->{group};
    is(ref $group->{hosts}, 'HASH', 'default host list is a hash');
}

sub function__add_attributes : Test(3) {
    my $group = shift->{group};

    can_ok($group, 'add_attributes');
    ok($group->add_attributes( {
        contacts      => 1,
        local_address => 1,
        node_order    => 1,
    }));

  TODO: {
        local $TODO = "add_attribute croaks on invalid attributes";
        # ok(! $group->add_attributes( {
        #     invalid_attribute => 1
        # }));
    };
}

sub function__add_host : Test(3) {
    my $self = shift;
    my $group = $self->{group};
    my $host = $self->{host1};

    can_ok($group, 'add_host');
    ok($group->add_host($host), 'add host to group');

    cmp_deeply(
        $group->{hosts},
        hash_each(isa('Munin::Master::Host')),
        'host is added to group'
    );
}

sub function__get_all_hosts : Test(5) {
    my $self = shift;
    my $group = $self->{group};
    my @hosts = ($self->{host1}, $self->{host2});

    can_ok($group, 'get_all_hosts');

    foreach my $host (@hosts) {
        ok($group->add_host($host), "setup, add hosts");
    }

    ok(my @result = $group->get_all_hosts);

    cmp_deeply(
        \@result,
        array_each(
            isa('Munin::Master::Host'),
        ),
        'returns an array of Munin::Master::Host objects'
    );
}

sub function__give_attributes_to_hosts : Test(5) {
    my $self = shift;
    my $group = $self->{group};
    my @hosts = ($self->{host1}, $self->{host2});

    can_ok($group, 'give_attributes_to_hosts');

    foreach my $host (@hosts) {
        ok($group->add_host($host), "setup, add hosts");
    }

    ok($group->give_attributes_to_hosts({
        contacts => 'nobody@example.com'
    }));

    cmp_deeply(
        $group->{hosts},
        hash_each(isa('Munin::Master::Host'))
    );
}
1;