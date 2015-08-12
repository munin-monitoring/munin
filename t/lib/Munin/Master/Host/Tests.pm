package Munin::Master::Host::Tests;
use base qw(Test::Class);
use Test::More;

use Munin::Master::Host;
use Munin::Master::Group;

sub setup : Test(setup) {
    my $self = shift;

    $self->{group} = Munin::Master::Group->new('example.com');

    $self->{host} = Munin::Master::Host->new(
        'test.example.com',
        $self->{group},
        { address => '192.0.2.2'}
        );

}

sub class : Test(1) {
    my $host = shift->{host};
    isa_ok($host, 'Munin::Master::Host');
}

sub class_parameters : Test(2) {
    my $self = shift;

    my $host = $self->{host};
    my $group = $self->{group};

    is($host->{host_name}, 'test.example.com', 'host name');
    is($host->{group}, $self->{group}, 'group');
}

sub class_defaults : Test(3) {
    my $host = shift->{host};
    is($host->{update}, 1, 'default update');
    is($host->{port}, 4949, 'default port');
    is($host->{use_node_name}, 0, 'default use_node_name');
}

sub method__get_full_path : Test(2) {
    my $host = shift->{host};

    can_ok($host, 'get_full_path');
    is($host->get_full_path, 'example.com;test.example.com',
       'should return "example.com;test.example.com"');
}

sub method__add_attributes_if_not_exists : Test(3) {
    my $host = shift->{host};
    can_ok($host, 'add_attributes_if_not_exists');

    ok($host->add_attributes_if_not_exists({ 'foo' => 'bar'}),
       'add attribute foo with content "bar"');

    is($host->{foo}, 'bar',
       'read attribute foo should return "bar"');
}

sub method__get_canned_ds_config : Test(2) {
    my $host = shift->{host};
    can_ok($host, 'get_canned_ds_config');

  TODO: {
      local $TODO = 'Figure out what this method really does';
    }
}

1;
