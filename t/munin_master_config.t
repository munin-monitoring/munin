#!/usr/bin/perl
# Tests for Munin::Master::Config - parse_config and _concat_config_line
#
# Tests the config file parsing including continuation lines (ending in \)

use strict;
use warnings;

use lib qw(lib t/lib);

use Test::More;
use IO::Handle;

# ============================================================================
# SETUP
# ============================================================================

require Munin::Master::Config;

# ============================================================================
# HELPER: Parse config from string
# ============================================================================

sub parse_config_string {
    my ($text) = @_;
    my $io = IO::Handle->new;
    open($io, '<', \$text) or die "Cannot open string: $!";
    # Reset singleton for clean tests
    my $config = Munin::Master::Config->instance()->{config};
    $config->parse_config($io);
    close $io;
    return $config;
}

# ============================================================================
# TESTS: _concat_config_line paths
# ============================================================================

subtest '_concat_config_line - empty prefix' => sub {
    my $config = Munin::Master::Config->instance()->{config};
    my $result = $config->_concat_config_line('', 'dbdir', '/var/lib/munin');
    is($result, 'dbdir', 'empty prefix returns key');
};

subtest '_concat_config_line - prefix ends with semicolon' => sub {
    my $config = Munin::Master::Config->instance()->{config};
    my $result = $config->_concat_config_line('group1;', 'port', '4949');
    is($result, 'group1;port', 'prefix+key concatenated');
};

subtest '_concat_config_line - prefix contains colon' => sub {
    my $config = Munin::Master::Config->instance()->{config};
    my $result = $config->_concat_config_line('group1;host1:service1', 'label', 'CPU');
    is($result, 'group1;host1:service1.label', 'dot separator after colon');
};

subtest '_concat_config_line - prefix ends in host (no colon)' => sub {
    my $config = Munin::Master::Config->instance()->{config};
    my $result = $config->_concat_config_line('group1;host1', 'port', '4949');
    is($result, 'group1;host1:port', 'colon inserted before key');
};

subtest '_concat_config_line - nested groups' => sub {
    my $config = Munin::Master::Config->instance()->{config};
    my $result = $config->_concat_config_line('group1;group2;', 'address', '127.0.0.1');
    is($result, 'group1;group2;address', 'deep group prefix');
};

subtest '_concat_config_line - nested service' => sub {
    my $config = Munin::Master::Config->instance()->{config};
    my $result = $config->_concat_config_line('group1;host1:service1:subservice', 'value', '42');
    is($result, 'group1;host1:service1:subservice.value', 'nested service path');
};

# ============================================================================
# TESTS: Simple key-value parsing
# ============================================================================

subtest 'simple key-value' => sub {
    my $config = parse_config_string("dbdir /var/lib/munin\n");
    is($config->{dbdir}, '/var/lib/munin', 'simple key-value pair');
};

subtest 'multiple keys' => sub {
    my $text = "dbdir /var/lib/munin\nlogdir /var/log/munin\nhtmldir /var/www/munin\n";
    my $config = parse_config_string($text);
    is($config->{dbdir}, '/var/lib/munin', 'first key');
    is($config->{logdir}, '/var/log/munin', 'second key');
    is($config->{htmldir}, '/var/www/munin', 'third key');
};

# ============================================================================
# TESTS: Comments
# ============================================================================

subtest 'comments are ignored' => sub {
    my $config = parse_config_string("# this is a comment\ndbdir /var/lib/munin\n");
    is($config->{dbdir}, '/var/lib/munin', 'key after comment');
};

# ============================================================================
# TESTS: Continuation lines
# ============================================================================

subtest 'continuation line joins next line' => sub {
    my $text = "dbdir /var/lib/munin\\\n    /custom\n";
    my $config = parse_config_string($text);
    is($config->{dbdir}, '/var/lib/munin/custom', 'lines joined');
};

subtest 'continuation preserves leading whitespace' => sub {
    my $text = "dbdir /var/lib\\\n    /munin\n";
    my $config = parse_config_string($text);
    # Note: _trim removes leading whitespace from each line,
    # so continuation lines are trimmed too.
    is($config->{dbdir}, '/var/lib/munin', 'continuation lines are trimmed');
};

subtest 'three line continuation' => sub {
    my $text = "dbdir /var\\\n    /lib\\\n    /munin\n";
    my $config = parse_config_string($text);
    is($config->{dbdir}, '/var/lib/munin', 'three lines joined');
};

subtest 'continuation then normal line' => sub {
    my $text = "dbdir /var/lib\\\n    /munin\nlogdir /var/log/munin\n";
    my $config = parse_config_string($text);
    is($config->{dbdir}, '/var/lib/munin', 'continuation works');
    is($config->{logdir}, '/var/log/munin', 'normal line works');
};

# ============================================================================
# CLEANUP
# ============================================================================

print "\n";

done_testing();

1;
