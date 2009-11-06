# -*- cperl -*-
use warnings;
use strict;

use Munin::Master::Config;
use Test::More tests => 13;
use Test::MockModule;
use Test::MockObject::Extends;
use Test::Exception;

use Data::Dumper;

use_ok('Munin::Master::Node');

my $config = Munin::Master::Config->instance();
$config->{node}{use_node_name} = 1;

sub setup {
    my $node = Munin::Master::Node->new('127.0.0.1', 4949, 'node');
    my $node_mock = Test::MockObject::Extends->new($node);
    
    $node_mock->mock('_node_write_single', sub {});
    return $node_mock;
}


############################# 2 #########################################


{
    my $node = Munin::Master::Node->new();
    isa_ok($node, 'Munin::Master::Node','Create a node object');
}


############################# 3 #########################################


{
    my $node = setup();
    $node->mock('_node_read_single', sub { 
        return '# munin node at foo.example.com' 
    });
    my $inet = Test::MockModule->new('IO::Socket::INET');
    $inet->mock(new => sub { return {} });

    $node->_do_connect();

    is($node->{node_name}, 'foo.example.com','Node name is detected');
}


############################# 4 #########################################


{
    my $node = Munin::Master::Node->new();
    is($node->_extract_name_from_greeting('# munin node at foo.example.com'),
       'foo.example.com', 'Node name from new greeting');
    is($node->_extract_name_from_greeting('# lrrd client at foo.example.com'),
       'foo.example.com', 'Node name from old greeting');
}


######################################################################


{
    my $node = setup();
    $node->mock('_node_read_single', sub { 
        return ('cap multigraph');
    });
    my @res = $node->negotiate_capabilities();

    is_deeply(\@res, ['multigraph'], 'Capabilities - single');
}


=begin comment

This fails.  Frankly it should result in "multigraph".
{
    my $node = setup();
    $node->mock('_node_read_single', sub { 
        return ('cap bar baz foo');
    });
    my @res = $node->negotiate_capabilities();

    is_deeply(\@res, ['baz'], 'Capabilities - none');
}
=end comment

=cut



######################################################################


{
    my $node = setup();
    $node->mock('_node_read_single', sub { return 'foo bar baz'; });

    $node->{node_name} = 'node';

    my @res = $node->list_plugins();

    is_deeply(\@res, [qw(foo bar baz)], 'List plugins');
}


######################################################################


{
    my $node = setup();
    $node->mock('_node_read', sub { return ('# timeout: bla bla bla') });
    throws_ok { $node->fetch_service_config('foo') }
        qr/Timeout error on node/,
            'Fetch service config - Timeout throws exception';
}


{
    my $node = setup();
    $node->mock('_node_read', sub { 
        return (
            '',
            '# bla bla bla',
            'foo bar',
            'zap gabonk',
            'baz.bar foo',
        );
    });
    throws_ok { $node->fetch_service_config('foo') }
        qr/Missing required attribute 'label' for data source 'baz'/,
            'Fetch service config - Missing "label" throws exception';
}


{
    my $node = setup();
    $node->mock('_node_read', sub { 
        return (
            '',
            '# bla bla bla',
            'foo bar',
            'zap gabonk',
            'baz.label foo',
            'zip.label bar',
        );
    });
    my %res = $node->fetch_service_config('foo');

    is_deeply(\%res,
	      {
	       global => {
			  multigraph => [ 'foo' ],
			  foo => {
				  [qw(foo bar)],
				  [qw(zap gabonk)],
				  ['graph_order', 'baz zip'],
				 },
			 },
	       data_source => {
			       foo => {
				       baz => {label => 'foo'},
				       zip => {label => 'bar'},
				      },
			      },
	      },
	      'Fetch service config - implicit graph order'
	     );
}


{
    my $node = setup();
    $node->mock('_node_read', sub {
        return (
            '',
            '# bla bla bla',
            'foo bar',
            'zap gabonk',
            'baz.label foo',
            'zip.label bar',
            'graph_order zip baz',
        );
    });
    my %res = $node->fetch_service_config('foo');
    is_deeply(\%res, {
        global => [
            [qw(foo bar)],
            [qw(zap gabonk)],
            ['graph_order', 'zip baz']
        ], 
        data_source => {
            baz => {label => 'foo'},
            zip => {label => 'bar'},
        },
    }, 'Fetch service config - explicit graph_order');
}


######################################################################


{
    my $node = setup();
    $node->mock('_node_read', sub { return ('# timeout: bla bla bla') });

    throws_ok { $node->fetch_service_data('foo') }
        qr/Timeout in fetch from 'foo'/,
            'Fetch service data - Timeout throws exception';
}


{
    my $node = setup();
    $node->mock('_node_read', sub {
        return (
            '',
            '# bla bla bla',
            'foo.value bar',
            'zap.value gabonk',
            'baz.value foo',
        );
    });

    my %res = $node->fetch_service_data('foo');

    is_deeply(\%res, {
        foo => {value => 'bar', when => 'N'}, 
        zap => {value => 'gabonk', when => 'N'},
        baz => {value => 'foo', when => 'N'},
    }, 'Fetch service data');
}
