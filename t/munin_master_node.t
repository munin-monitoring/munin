use warnings;
use strict;

use Munin::Master::Config;
use Test::More;
if ($ENV{TEST_MEDIUM}) {
    plan tests => 9;
}
else {
    plan skip_all => 'set TEST_MEDIUM to enable these tests';
}

use Test::MockModule;
use Test::MockObject::Extends;
use Test::Exception;

use Test::Differences;

use Data::Dumper;

use Munin::Common::Logger;
Munin::Common::Logger->_remove_default_logging;

use_ok('Munin::Master::Node');


sub setup {
    my $node = Munin::Master::Node->new('127.0.0.1', 4949, 'node');
    my $node_mock = Test::MockObject::Extends->new($node);

    $node_mock->{configref} = Munin::Master::Config->instance();
    $node_mock->{configref}{use_node_name} = 1;

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

