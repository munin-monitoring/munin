use warnings;
use strict;

use Munin::Master::Config;
use Test::More tests => 11;
use Test::MockObject::Extends;
use Test::Exception;

use_ok('Munin::Master::Node');

my $config = Munin::Master::Config->instance();
$config->{node}{use_node_name} = 1;

sub setup {
    my $node = Munin::Master::Node->new('127.0.0.1', 4949, 'node');
    my $node_mock = Test::MockObject::Extends->new($node);
    
    $node_mock->mock('_node_write_single', sub {});
    return $node_mock;
}


######################################################################


{
    my $node = Munin::Master::Node->new();
    isa_ok($node, 'Munin::Master::Node');
}


######################################################################


{
    my $node = setup();
    $node->mock('_node_read', sub { 
        return (
            '# Node capabilities: (bar baz foo). Session capabilities: (',
            'foo',
            '# )',
        );
    });
    my @res = $node->negotiate_capabilities();

    is_deeply(\@res, ['foo'], 'Capabilities - single');
}


{
    my $node = setup();
    $node->mock('_node_read', sub { 
        return (
            '# Node capabilities: (bar baz foo). Session capabilities: (',
            '',
            '# )',
        );
    });
    my @res = $node->negotiate_capabilities();

    is_deeply(\@res, [], 'Capabilities - none');
}


{
    my $node = setup();
    $node->mock('_node_read', sub { 
        return (
            '# Node capabilities: (bar baz foo). Session capabilities: (',
            'bar baz foo',
            '# )',
        );
    });
    my @res = $node->negotiate_capabilities();

    is_deeply(\@res, [qw(bar baz foo)], 'Capabilities - multiple');
}


{
    my $node = setup();
    $node->mock('_node_read', sub { 
        return (
            '# Unknown command bla bla bla',
        );
    });
    my @res = $node->negotiate_capabilities();

    is_deeply(\@res, ['NA'], 'Capabilities - not applicable');
}


######################################################################


{
    my $node = setup();
    $node->mock('_node_read_single', sub { return 'foo bar baz'; });

    $node->{node_name} = 'node';

    my @res = $node->list_services();

    is_deeply(\@res, [qw(foo bar baz)], 'List services');
}


######################################################################


{
    my $node = setup();
    $node->mock('_node_read', sub { return ('# timeout: bla bla bla') });

    
    throws_ok { $node->fetch_service_config('foo') }
        qr/Client reported timeout in configuration of 'foo'/,
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

    
    my %res = $node->fetch_service_config('foo');

    is_deeply(\%res,  {
        global => [[qw(foo bar)], [qw(zap gabonk)]], 
        data_source => [[qw(baz bar foo)]]
    }, 'Fetch service config');
}


######################################################################


{
    my $node = setup();
    $node->mock('_node_read', sub { return ('# timeout: bla bla bla') });

    
    throws_ok { $node->fetch_service_data('foo') }
        qr/Client reported timeout in configuration of 'foo'/,
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

    my @res = $node->fetch_service_data('foo');

    is_deeply(\@res, [[qw(foo bar N)], [qw(zap gabonk N)], [qw(baz foo N)]],
              'Fetch service data');
}
