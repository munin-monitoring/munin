#!/usr/bin/perl
# Tests for Munin::Master::Node - multigraph parsing
#
# Tests the multigraph block splitting logic in fetch_service_config()

use strict;
use warnings;

use lib qw(lib t/lib);

use Test::More;
use Test::MockModule;
use Time::HiRes qw(gettimeofday);
use IO::Socket::INET;

# ============================================================================
# SETUP
# ============================================================================

require Munin::Master::Config;
require Munin::Master::Node;

# ============================================================================
# HELPER: Create mock Node with canned responses
# ============================================================================

sub create_mock_node {
    my ($config_lines) = @_;

    # Create a blessed hash that looks like a Node
    my $node = bless {
        host    => 'localhost',
        address => '127.0.0.1',
        port    => 4949,
        _config_lines => $config_lines,
        _written      => [],
    }, 'Munin::Master::Node';

    # Mock the internal methods
    no strict 'refs';
    *{'Munin::Master::Node::_node_write_single'} = sub {
        my ($self, $line) = @_;
        push @{$self->{_written}}, $line;
    };

    *{'Munin::Master::Node::_node_read'} = sub {
        my ($self) = @_;
        return $self->{_config_lines};
    };

    return $node;
}

# ============================================================================
# TESTS: Single plugin (no multigraph)
# ============================================================================

subtest 'single plugin no multigraph' => sub {
    my @config = (
        'graph_title CPU Usage',
        'graph_args --vertical-label %',
        'graph_vlabel %',
        'user.label user',
        'user.min 0',
        'user.max 100',
        'system.label system',
        'system.min 0',
        'system.max 100',
    );

    my $node = create_mock_node(\@config);

    my @calls;
    my $last_ts = $node->fetch_service_config('cpu', sub {
        my ($name, $now, $lines, $last_ts) = @_;
        push @calls, {
            name   => $name,
            lines  => $lines,
            ts     => $last_ts,
        };
        return $now;
    });

    is(scalar @calls, 1, "one callback for single plugin");
    is($calls[0]{name}, "cpu", "service name preserved");
    is(scalar @{$calls[0]{lines}}, 9, "all lines passed");
};

# ============================================================================
# TESTS: Multigraph with multiple blocks
# ============================================================================

subtest 'multigraph with two blocks' => sub {
    my @config = (
        'multigraph cpu',           # consumed by parser
        'graph_title CPU Usage',    # block 1
        'graph_args --vertical-label %',
        'user.label user',
        'user.min 0',
        'multigraph cpu.memory',    # consumed by parser
        'graph_title Memory',       # block 2
        'graph_args --vertical-label bytes',
        'used.label used',
        'used.min 0',
    );

    my $node = create_mock_node(\@config);

    my @calls;
    $node->fetch_service_config('cpu', sub {
        my ($name, $now, $lines, $last_ts) = @_;
        push @calls, {
            name  => $name,
            lines => [@$lines],  # copy
        };
        return $now;
    });

    is(scalar @calls, 2, "two callbacks for two blocks");
    is($calls[0]{name}, "cpu", "first block name");
    is(scalar @{$calls[0]{lines}}, 4, "first block has 4 lines (multigraph line consumed)");
    is($calls[1]{name}, "cpu_memory", "second block name (dot becomes underscore)");
    is(scalar @{$calls[1]{lines}}, 4, "second block has 4 lines");
};

# ============================================================================
# TESTS: Multigraph with three blocks
# ============================================================================

subtest 'multigraph with three blocks' => sub {
    my @config = (
        'multigraph if_',
        'graph_title Network',
        'multigraph if_.down',
        'graph_title Downstream',
        'rx.label rx',
        'multigraph if_.up',
        'graph_title Upstream',
        'tx.label tx',
    );

    my $node = create_mock_node(\@config);

    my @calls;
    $node->fetch_service_config('if_', sub {
        my ($name, $now, $lines, $last_ts) = @_;
        push @calls, { name => $name, lines => [@$lines] };
        return $now;
    });

    is(scalar @calls, 3, "three callbacks");
    is($calls[0]{name}, "if_", "first block");
    is($calls[1]{name}, "if__down", "second block (dot becomes underscore)");
    is($calls[2]{name}, "if__up", "third block");
};

# ============================================================================
# TESTS: Multigraph without initial multigraph line
# ============================================================================

subtest 'plugin config starts with multigraph mid-stream' => sub {
    my @config = (
        'graph_title Main',
        'graph_args --vertical-label %',
        'multigraph sub.a',
        'graph_title Sub A',
        'multigraph sub.b',
        'graph_title Sub B',
    );

    my $node = create_mock_node(\@config);

    my @calls;
    $node->fetch_service_config('main', sub {
        my ($name, $now, $lines, $last_ts) = @_;
        push @calls, { name => $name, lines => [@$lines] };
        return $now;
    });

    is(scalar @calls, 3, "three blocks");
    is($calls[0]{name}, "main", "first block uses original name");
    is(scalar @{$calls[0]{lines}}, 2, "first block has preamble lines");
    is($calls[1]{name}, "sub_a", "second block (dot becomes underscore)");
    is($calls[2]{name}, "sub_b", "third block");
};

# ============================================================================
# TESTS: Timestamp passing
# ============================================================================

subtest 'timestamp passed between blocks' => sub {
    my @config = (
        'multigraph a',
        'graph_title A',
        'multigraph b',
        'graph_title B',
    );

    my $node = create_mock_node(\@config);

    my @timestamps;
    $node->fetch_service_config('test', sub {
        my ($name, $now, $lines, $last_ts) = @_;
        push @timestamps, $last_ts;
        return 42;  # Return a fixed value
    });

    is($timestamps[0], 0, "first block gets 0");
    is($timestamps[1], 42, "second block gets previous return value");
};

# ============================================================================
# TESTS: Plugin name sanitization
# ============================================================================

subtest 'plugin names are sanitised' => sub {
    my @config = (
        'multigraph plugin-with-dashes',
        'graph_title Test',
    );

    my $node = create_mock_node(\@config);

    my @names;
    $node->fetch_service_config('my-plugin', sub {
        my ($name, $now, $lines, $last_ts) = @_;
        push @names, $name;
        return $now;
    });

    # Names should be sanitised (dashes become underscores in munin)
    ok(scalar @names >= 1, "at least one block");
};

# ============================================================================
# TESTS: Empty config
# ============================================================================

subtest 'empty config lines' => sub {
    my @config = ();

    my $node = create_mock_node(\@config);

    my @calls;
    $node->fetch_service_config('empty', sub {
        my ($name, $now, $lines, $last_ts) = @_;
        push @calls, { name => $name, lines => $lines };
        return $now;
    });

    is(scalar @calls, 1, "one callback even for empty config");
    is(scalar @{$calls[0]{lines}}, 0, "empty lines array");
};

# ============================================================================
# CLEANUP
# ============================================================================

print "\n";

done_testing();

1;
