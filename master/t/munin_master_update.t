use warnings;
use strict;

use English qw(-no_match_vars);
use Test::MockModule;
use Test::More tests => 2;
use File::Temp qw( tempdir );

use_ok('Munin::Master::Update');

my $config = Munin::Master::Config->instance()->{config};
$config->{dbdir} = tempdir(CLEANUP => 1);

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
my $mockconfig = Test::MockModule->new('Munin::Master::Config');
$mockconfig->mock(get_groups_and_hosts => sub { return () });


#
{
    my $update = Munin::Master::Update->new();

    $update->{service_configs} = {
	'g1;host1' => {
	    global => {
		service1 => [['graph_title', 'service1']],
	    },
	    data_source => {
		service1 => {
		    data_source1 => {max => 'U', min => 'U'},
		    data_source2 => {max => 'U', min => 'U'},
		},
	    },
	},
	'g1;host2' => {
	    global => {
		service1 => [['graph_title', 'service1']],
	    },
	    data_source => {
		service1 => {
		    data_source1 => {max => 'U', min => 'U'},
		},
	    },
	},
    };

    my $result = "";
    open my $fh, '>', \$result or die $OS_ERROR;
    $update->_write_new_service_configs($fh);

    no warnings 'once';
    my $expected = "version $Munin::Common::Defaults::MUNIN_VERSION\n" .
	remove_indentation(q{
        g1;host1:service1.graph_title service1
        g1;host1:service1.data_source1.max U
        g1;host1:service1.data_source1.min U
        g1;host1:service1.data_source2.max U
        g1;host1:service1.data_source2.min U
        g1;host2:service1.graph_title service1
        g1;host2:service1.data_source1.max U
        g1;host2:service1.data_source1.min U
    });

    is($result, $expected, 'Write new service config');
}
