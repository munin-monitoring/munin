use strict;
use warnings;

use lib qw(lib t/lib);

use Test::More;
use Socket qw(inet_aton);

# ============================================================================
# Test _get_default_address
#
# Logic:
# 1. If host_name has dot AND resolves → return host_name
# 2. If group_name has dot AND "group.host" resolves → return "$group_name.$host_name"
# 3. Otherwise → return host_name (fallback)
# ============================================================================

# We need to mock _does_resolve to control DNS resolution
# Load the module first
use Munin::Master::UpdateWorker;

# Save original
my $orig_does_resolve = \&Munin::Master::UpdateWorker::_does_resolve;

# Mock _does_resolve
my %should_resolve;
no warnings 'redefine';
*Munin::Master::UpdateWorker::_does_resolve = sub {
    my ($name) = @_;
    return $should_resolve{$name};
};
use warnings 'redefine';

# Helper to call _get_default_address with a mock host
sub get_address {
    my (%opts) = @_;
    my $host = {
        host_name => $opts{host_name},
        group     => { group_name => $opts{group_name} },
    };
    return Munin::Master::UpdateWorker::_get_default_address($host);
}

# ============================================================================
# TEST 1: host_name has dot and resolves → return host_name
# ============================================================================

subtest 'host with dot that resolves → return host_name' => sub {
    %should_resolve = ('server.example.com' => 1);

    my $result = get_address(
        host_name  => 'server.example.com',
        group_name => 'infra',
    );

    is($result, 'server.example.com', 'returns FQDN when it resolves');
};

# ============================================================================
# TEST 2: host_name has dot but doesn't resolve, group has dot → try group.host
# ============================================================================

subtest 'host fails, group has dot and resolves → return group.host' => sub {
    %should_resolve = (
        'server.example.com'            => 0,
        'infra.example.server.example.com' => 1,
    );

    my $result = get_address(
        host_name  => 'server.example.com',
        group_name => 'infra.example',
    );

    is($result, 'infra.example.server.example.com', 'returns group.host');
};

# ============================================================================
# TEST 3: host_name has dot but doesn't resolve, group has dot but doesn't
#         resolve either → fallback to host_name
# ============================================================================

subtest 'host fails, group has dot but fails too → fallback to host_name' => sub {
    %should_resolve = (
        'server.example.com'     => 0,
        'infra.server.example.com' => 0,
    );

    my $result = get_address(
        host_name  => 'server.example.com',
        group_name => 'infra',
    );

    is($result, 'server.example.com', 'returns host_name when group.host also fails');
};

# ============================================================================
# TEST 4: neither resolves → fallback to host_name
# ============================================================================

subtest 'nothing resolves → fallback to host_name' => sub {
    %should_resolve = ();

    my $result = get_address(
        host_name  => 'unknown',
        group_name => 'infra',
    );

    is($result, 'unknown', 'returns host_name as last resort');
};

# ============================================================================
# TEST 5: host has no dot, group has dot but doesn't resolve → fallback
# ============================================================================

subtest 'host no dot, group.host fails → fallback to host_name' => sub {
    %should_resolve = (
        'infra.server' => 0,
    );

    my $result = get_address(
        host_name  => 'server',
        group_name => 'infra',
    );

    is($result, 'server', 'returns host_name when group.host fails');
};

# ============================================================================
# TEST 6: both resolve → host_name wins (first check)
# ============================================================================

subtest 'both resolve → host_name takes precedence' => sub {
    %should_resolve = (
        'server.example.com'     => 1,
        'infra.server.example.com' => 1,
    );

    my $result = get_address(
        host_name  => 'server.example.com',
        group_name => 'infra',
    );

    is($result, 'server.example.com', 'host_name wins over group.host');
};

# ============================================================================
# TEST 7: empty host_name
# ============================================================================

subtest 'empty host_name → returns empty string' => sub {
    %should_resolve = ();

    my $result = get_address(
        host_name  => '',
        group_name => 'infra',
    );

    is($result, '', 'returns empty string for empty host_name');
};

done_testing();

1;
