package Munin::Master::Config::Tests;
use base qw(Test::Class);
use Test::More;
use Test::Deep;

use Munin::Master::Config;

sub setup : Test(setup) {
    my $self = shift;

    $self->{config} = Munin::Master::Config->instance();
}

sub class : Test {
    my $config = shift->{config};
    isa_ok( $config, 'Munin::Master::Config' );
}

sub function__look_up : Test(8) {
    my $config = shift->{config};
    can_ok( $config, 'look_up' );

    $config->parse_config( \*DATA );

    is( $config->look_up('example.com'),
        undef, 'look up first level group should fail' );
    is( $config->look_up('example.com'),
        undef, 'look up non existing host in first level group should fail' );
    is( $config->look_up('example.com;extra'),
        undef, 'look up second level group should fail' );

    ok( $result1 = $config->look_up('example.com;test1.example.com'),
        'look up host in first level group' );

    cmp_deeply(
        $result1,
        noclass( superhashof( { host_name => 'test1.example.com' } ) ),
        'host name matches test1.example.com'
    );

    ok( $result2 = $config->look_up('example.com;extra;test2.example.com'),
        'look up host in second level group' );

    cmp_deeply(
        $result2,
        noclass( superhashof( { host_name => 'test2.example.com' } ) ),
        'host name matches test2.example.com'
    );
}

sub function__parse_config : Test(2) {
    my $config = shift->{config};

    can_ok( $config, 'parse_config' );

    $config->parse_config( \*DATA );

    cmp_deeply(
        $config,
        noclass(
            {
                groups                 => ignore(),
                dbdir                  => '/test/dbdir',
                htmldir                => '/test/htmldir',
                config                 => ignore(),
                logdir                 => '/test/logdir',
                oldconfig              => ignore(),
                root_instance          => ignore(),
                rrdcached_socket       => '/test/rrdcached.sock',
                rundir                 => '/test/rundir',
                staticdir              => '/test/staticdir',
                tls                    => 'enabled',
                tls_ca_certificate     => '/test/ca_certificate.pem',
                tls_certificate        => '/test/tls_certificate.pem',
                tls_private_key        => '/test/tls_private_key.pem',
                tls_verify_certificate => '1',
                tls_verify_depth       => '5',
                tmpldir                => '/test/tmpldir',
            }
        )
    );
}

# Test parsed node definitions
sub function__parse_config__nodes : Test(2) {
    my $config = shift->{config};

    can_ok( $config, 'parse_config' );

    $config->parse_config( \*DATA );

    cmp_deeply(
        $config,
        noclass(
            superhashof(
                {
                    groups => {
                        'example.com' => {
                            hosts => {
                                'test1.example.com' => ignore(),
                            },
                            group_name => 'example.com',
                            group      => ignore(),
                            groups     => {
                                extra => {
                                    hosts => {
                                        'test2.example.com' => ignore(),
                                    },
                                    group      => ignore(),
                                    group_name => 'extra',
                                }
                            },
                        }
                    },
                }
            )
        )
    );
}

1;

__DATA__

# This is a comment

dbdir   /test/dbdir
htmldir /test/htmldir
logdir  /test/logdir
rundir  /test/rundir

tmpldir /test/tmpldir
staticdir /test/staticdir

tls enabled
tls_private_key /test/tls_private_key.pem
tls_certificate /test/tls_certificate.pem
tls_ca_certificate /test/ca_certificate.pem
tls_verify_certificate yes
tls_verify_depth 5

rrdcached_socket /test/rrdcached.sock

# Define two test nodes.
[test1.example.com]
  address 192.0.2.3
  load1.graph_title Loads side by side
  load1.graph_order fii=fii.foo.com:load.load fay=fay.foo.com:load.load

[example.com;extra;test2.example.com]
  address 192.0.2.4
  port 4948
  use_node_name yes
  load1.graph_title Loads side by side
  load1.graph_order fii=fii.foo.com:load.load fay=fay.foo.com:load.load
