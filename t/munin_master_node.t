# -*- cperl -*-
use warnings;
use strict;

use Munin::Master::Config;
use Test::More tests => 15;
use Test::MockModule;
use Test::MockObject::Extends;
use Test::Exception;

use Test::Differences;

use Data::Dumper;

use Munin::Common::Logger;
Munin::Common::Logger->_remove_default_logging;

use_ok('Munin::Master::Node');

my $config = Munin::Master::Config->instance();
$config->{node}{use_node_name} = 1;

sub setup {
    my $node = Munin::Master::Node->new('127.0.0.1', 4949, 'node');
    my $node_mock = Test::MockObject::Extends->new($node);
    
    $node_mock->mock('_node_write_single', sub {});
    $node_mock->mock('_node_read_fast', sub {
		       my ($self) = @_;
		       return $self->_node_read();
		     });
    return $node_mock;
}


### new
{
    my $node = Munin::Master::Node->new();
    isa_ok($node, 'Munin::Master::Node','Create a node object');
}


### _do_connect
{
    my $node = setup();
    $node->mock('_node_read_single', sub { 
        return '# munin node at foo.example.com' 
    });
    my $inet = Test::MockModule->new('IO::Socket::INET6');
    $inet->mock(new => sub { return {} });

    $node->_do_connect();

    is($node->{node_name}, 'foo.example.com','Node name is detected');
}


### _extract_name_from_greeting
{
    my $node = Munin::Master::Node->new();
    $node->_extract_name_from_greeting('# munin node at foo.example.com');
    is($node->{node_name}, 'foo.example.com', 'Node name from new greeting');

    $node->_extract_name_from_greeting('# lrrd client at foo.example.com');
    is($node->{node_name}, 'foo.example.com', 'Node name from old greeting');
}

### negotiate_capabilities
{
    my $node = setup();
    $node->mock('_node_read_single', sub { 
        return 'cap multigraph';
    });
    my @res = $node->negotiate_capabilities();

    is_deeply(\@res, ['multigraph'], 'Capabilities - single');
}
{
    my $node = setup();
    $node->mock('_node_read_single', sub { 
        return '# Unknown command. Try list, nodes, config, fetch, version or quit';
    });
    my @res = $node->negotiate_capabilities();

    is_deeply(\@res, ['NA'], 'Capabilities - single');
}


{
    my $node = setup();
    $node->mock('_node_read_single', sub {
		  return ['cap bar baz foo'];
		});
    my @res = $node->negotiate_capabilities();

    is_deeply(\@res, ['NA'], 'Capabilities - none');
}


### list_plugins
{
    my $node = setup();
    $node->mock('_node_read_single', sub { return 'foo bar baz'; });

    $node->{node_name} = 'node';

    my @res = $node->list_plugins();

    is_deeply(\@res, [qw(foo bar baz)], 'List plugins');
}


### fetch_service_config
{
    my $node = setup();
    $node->mock('_node_read', sub {
		  return ['# timeout: bla bla bla'];
		});
    throws_ok { $node->fetch_service_config('foo') }
        qr/Timeout error on node/,
            'Fetch service config - Timeout throws exception';
}
{
    my $node = setup();
    $node->mock('_node_read', sub {
		  return ['',
			  '# bla bla bla',
			  'foo bar',
			  'zap gabonk',
			  'baz.bar foo',
			 ];
		});

#die Dumper { $node->fetch_service_config('fun') };

    my %res = $node->fetch_service_config('fun');
    eq_or_diff(\%res, {
            global => {
                multigraph => [ 'fun' ],
                fun        => [
                    [ 'foo', 'bar' ],
                    [ 'zap', 'gabonk' ],
                ],
            },
            data_source => {
                fun => {
                    baz => {
                        bar => 'foo',
                        extinfo => 'NOTE: The plugin did not provide any label for the data source baz.  It is in need of fixing.',
                        label => 'No .label provided',
                    },
                },
            },
        }, 'Fetch service config - missing label',
    );
}
{
    my $node = setup();
    $node->mock('_node_read', sub { 
		  return ['',
			  '# bla bla bla',
			  'foo bar',
			  'zap gabonk',
			  'baz.label foo',
			  'zip.label bar',
			 ];
		});
    my %res = $node->fetch_service_config('fun');

    is_deeply(\%res, {
            global => {
                multigraph => ['fun'],
                fun        => [
                    [qw(foo bar)],
                    [qw(zap gabonk)],
                    ['graph_order', 'baz zip'],
                ],
            },
            data_source => {
                fun => {
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
		  return ['',
			  '# bla bla bla',
			  'foo bar',
			  'zap gabonk',
			  'baz.label foo',
			  'zip.label bar',
			  'graph_order zip baz',
			  ];
		});
    my %res = $node->fetch_service_config('fun');
    is_deeply(\%res, {
            global => {
                multigraph => [qw( fun )],
                fun        => [
                    [qw( foo bar    )],
                    [qw( zap gabonk )],
                    [ 'graph_order', 'zip baz' ],
                ],
            },
            data_source => {
                fun => {
                    baz => {
                        label => 'foo',
                    },
                    zip => {
                        label => 'bar',
                    },
                }
            },
        },
        'Fetch service config - explicit graph_order'
    );
}


### fetch_service_data
{
    my $node = setup();
    $node->mock('_node_read', sub {
		  return ['# timeout: bla bla bla'];
		});

    throws_ok { $node->fetch_service_data('foo') }
        qr/Timeout in fetch from 'foo'/,
            'Fetch service data - Timeout throws exception';
}
{
    my $node = setup();
    $node->mock('_node_read', sub {
		  return ['',
			  '# bla bla bla',
			  'fun.value bar',
			  'zap.value gabonk',
			  'baz.value foo',
			 ];
		});

    my $time = time;  # this will work, except when the clock ticks at the wrong time
    my %res = $node->fetch_service_data('foo');

    is_deeply(\%res, {
            foo => {
                fun => {
                    value => ['bar'],
                    when  => [$time],
                },
                zap => {
                    value => ['gabonk'],
                    when  => [$time],
                },
                baz => {
                    value => ['foo'],
                    when  => [$time],
                },
            },
        },
        'Fetch service data'
    );
}

# vim: sw=8 : ts=4 : et
