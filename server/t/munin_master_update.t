use warnings;
use strict;

use English qw(-no_match_vars);
use Test::MockModule;
use Test::More tests => 5;

use_ok('Munin::Master::Update');


# Make 'keys' return the keys in sorted order.
package Munin::Master::Update;
use subs 'keys';
package main;
*Munin::Master::Update::keys = sub {
    my %hash = @_;
    sort(CORE::keys(%hash));
};

#
sub remove_indentation {
    my ($str) = @_;

    $str =~ s{\n\ *}{\n}xmsg;
    $str =~ s{\A \n }{}xms;

    return $str;
}

#
my $config = Test::MockModule->new('Munin::Master::Config');
$config->mock(get_groups_and_hosts => sub { return () });


#
{
    my $update = Munin::Master::Update->new();

    $update->{service_configs} = {
        'g1;host1' => {
            service1 => {
                global => [[qw(graph_title service1)],], 
                data_source => {
                    data_source1 => {max => 'U', min => 'U'},
                    data_source2 => {max => 'U', min => 'U'},
                }, 
            },
        },
        'g1;host2' => {
            service1 => {
                global => [[qw(graph_title service1)],], 
                data_source => {
                    data_source1 => {max => 'U', min => 'U'},
                }, 
            },
        },
    };

    my $result = "";
    open my $fh, '>', \$result or die $OS_ERROR;
    $update->_write_new_service_configs($fh);

    my $expected = remove_indentation(q{
        version svn
        g1;host1;service1;graph_title service1
        g1;host1;service1;data_source1;max U
        g1;host1;service1;data_source1;min U
        g1;host1;service1;data_source2;max U
        g1;host1;service1;data_source2;min U
        g1;host2;service1;graph_title service1
        g1;host2;service1;data_source1;max U
        g1;host2;service1;data_source1;min U
    });

    is($result, $expected, 'Write new service config');
}


{
    my $update = Munin::Master::Update->new();

    $update->{service_configs} = {
        'g1;host1' => {
            service1 => {
                global => [[qw(graph_title service1)],], 
                data_source => {
                    data_source1 => {max => 'U', min => 'U'},
                    data_source2 => {max => 'U', min => 'U'},
                }, 
            },
        },
    };

    $update->{failed_workers} = [qw(g1;host2)];

    $update->{old_service_configs} = {
        'g1;host2' => {
            service1 => {
                global => [[qw(graph_title service1)],], 
                data_source => {
                    data_source1 => {max => '2', min => '0'},
                    data_source2 => {max => '2', min => '0'},
                }, 
            },
        },
    };

    my $result = "";
    open my $fh, '>', \$result or die $OS_ERROR;
    $update->_write_new_service_configs($fh);

    my $expected = remove_indentation(q{
        version svn
        g1;host1;service1;graph_title service1
        g1;host1;service1;data_source1;max U
        g1;host1;service1;data_source1;min U
        g1;host1;service1;data_source2;max U
        g1;host1;service1;data_source2;min U
        g1;host2;service1;graph_title service1
        g1;host2;service1;data_source1;max 2
        g1;host2;service1;data_source1;min 0
        g1;host2;service1;data_source2;max 2
        g1;host2;service1;data_source2;min 0
    });

    is($result, $expected, 'Write new service config - failed worker');
}


{
    my $update = Munin::Master::Update->new();

    $update->{service_configs} = {};
    $update->{old_service_configs} = {};

    my $sconf = remove_indentation(q{
        version svn
        g1;host1;service1;graph_title service1
        g1;host1;service1;data_source1;max U
        g1;host1;service1;data_source1;min U
        g1;host1;service1;data_source2;max U
        g1;host1;service1;data_source2;min U
        g1;host2;service1;graph_title service1
        g1;host2;service1;data_source1;max 2
        g1;host2;service1;data_source1;min 0
    });

    open my $fh, '<', \$sconf or die $OS_ERROR;
    my %service_configs = $update->_parse_service_config_dump($fh);

    is($update->{old_version}, 'svn', 'Parse old service config - version');

    is_deeply(\%service_configs, {
        'g1;host1' => {
            service1 => {
                global => [[qw(graph_title service1)],], 
                data_source => {
                    data_source1 => {max => 'U', min => 'U'},
                    data_source2 => {max => 'U', min => 'U'},
                }, 
            },
        },
        'g1;host2' => {
            service1 => {
                global => [[qw(graph_title service1)],], 
                data_source => {
                    data_source1 => {max => '2', min => '0'},
                }, 
            },
        },
    }, 'Parse old service config');
}
