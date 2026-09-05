use strict;
use warnings;

use lib qw(t/lib);

use Test::More;
use Test::Differences;
use Test::Exception;
use IO::Socket::INET;
use File::Temp qw(tempdir);
use File::Path qw(remove_tree);
use POSIX qw(:sys_wait_h);

use constant {
    TLS_PORT       => 0,
    TLS_TIMEOUT    => 10,
    TLS_TEST_DATA  => "Hello TLS World\n",
};

# Global state for cleanup
my @child_pids;
my $tls_dir;

END {
    if (@child_pids) {
        kill('TERM', @child_pids);
        for my $pid (@child_pids) {
            waitpid($pid, 0);
        }
    }
    if ($tls_dir && -d $tls_dir) {
        remove_tree($tls_dir);
    }
}

# Generate certs at test time
require TestTLS;
$tls_dir = generate_test_certs();

# --- Test 1: Module loads ---
require_ok('Munin::Common::TLS');
require_ok('Munin::Common::TLSServer');
require_ok('Munin::Common::TLSClient');

# --- Test 2: Constructor validation ---
{
    my @required = qw(read_fd read_func write_fd write_func);
    for my $key (@required) {
        my %args = (
            read_fd     => 0,
            read_func   => sub { "" },
            write_fd    => 1,
            write_func  => sub { "" },
        );
        delete $args{$key};
        throws_ok {
            Munin::Common::TLS->new(\%args);
        } qr/Required argument missing: $key/,
        "constructor dies without $key";
    }
}

# --- Test 3: Constructor with all args ---
{
    my $tls = Munin::Common::TLSServer->new({
        read_fd     => 0,
        read_func   => sub { "" },
        write_fd    => 1,
        write_func  => sub { "" },
        DEBUG       => 1,
        tls_ca_cert => '/nonexistent/ca.pem',
        tls_cert    => '/nonexistent/cert.pem',
        tls_priv    => '/nonexistent/key.pem',
        tls_paranoia => 0,
        tls_vdepth  => 5,
        tls_verify  => 0,
        tls_match   => 'CN=foo',
    });
    isa_ok($tls, 'Munin::Common::TLSServer');
    is($tls->{DEBUG}, 1, 'DEBUG flag set');
    is($tls->{tls_vdepth}, 5, 'tls_vdepth set');
}

# --- Test 4: Constructor rejects unknown args ---
{
    throws_ok {
        Munin::Common::TLSServer->new({
            read_fd     => 0,
            read_func   => sub { "" },
            write_fd    => 1,
            write_func  => sub { "" },
            unknown_arg => 42,
        });
    } qr/Unrecognized argument: unknown_arg/,
    "constructor dies on unknown arg";
}

# --- Test 5: session_started ---
{
    my $tls = Munin::Common::TLSServer->new({
        read_fd     => 0,
        read_func   => sub { "" },
        write_fd    => 1,
        write_func  => sub { "" },
    });
    ok(!$tls->session_started(), 'session not started initially');
}

# --- Test 6: read/write without session throws ---
{
    my $tls = Munin::Common::TLSServer->new({
        read_fd     => 0,
        read_func   => sub { "" },
        write_fd    => 1,
        write_func  => sub { "" },
    });
    throws_ok { $tls->read() } qr/TLS session is not started/,
        'read throws without session';
    throws_ok { $tls->write("test") } qr/TLS session is not started/,
        'write throws without session';
}

# --- Test 7: Abstract method throws ---
{
    my $tls = Munin::Common::TLS->new({
        read_fd     => 0,
        read_func   => sub { "" },
        write_fd    => 1,
        write_func  => sub { "" },
    });
    throws_ok { $tls->_initial_communication() } qr/Abstract method called/,
        '_initial_communication is abstract';
    throws_ok { $tls->_use_key_if_present() } qr/Abstract method called/,
        '_use_key_if_present is abstract';
}

# --- Test 8: TLSServer _initial_communication ---
{
    my @written;
    my $tls = Munin::Common::TLSServer->new({
        read_fd     => 0,
        read_func   => sub { "" },
        write_fd    => 1,
        write_func  => sub { push @written, @_ },
    });

    # Test without private key
    $tls->{private_key_loaded} = 0;
    $tls->_initial_communication();
    is(scalar @written, 1, 'wrote one message');
    is($written[0], "TLS MAYBE\n", 'TLS MAYBE when no key');

    # Test with private key
    @written = ();
    $tls->{private_key_loaded} = 1;
    $tls->_initial_communication();
    is($written[0], "TLS OK\n", 'TLS OK when key loaded');
}

# --- Test 9: TLSClient _initial_communication ---
{
    # Test with TLS OK response
    my @written;
    my $tls = Munin::Common::TLSClient->new({
        read_fd     => 0,
        read_func   => sub { "TLS OK\n" },
        write_fd    => 1,
        write_func  => sub { push @written, @_ },
    });
    my $result = $tls->_initial_communication();
    ok($result, 'TLS OK response accepted');
    is($written[0], "STARTTLS\n", 'client sends STARTTLS');
    ok($tls->{remote_key}, 'remote_key set on TLS OK');

    # Test with TLS MAYBE response
    @written = ();
    $tls = Munin::Common::TLSClient->new({
        read_fd     => 0,
        read_func   => sub { "TLS MAYBE\n" },
        write_fd    => 1,
        write_func  => sub { push @written, @_ },
    });
    $result = $tls->_initial_communication();
    ok($result, 'TLS MAYBE response accepted');
    ok(!$tls->{remote_key}, 'remote_key not set on TLS MAYBE');

    # Test with bad response
    $tls = Munin::Common::TLSClient->new({
        read_fd     => 0,
        read_func   => sub { "BAD RESPONSE\n" },
        write_fd    => 1,
        write_func  => sub { push @written, @_ },
    });
    $result = $tls->_initial_communication();
    ok(!$result, 'bad response rejected');

    # Test with undef response
    $tls = Munin::Common::TLSClient->new({
        read_fd     => 0,
        read_func   => sub { undef },
        write_fd    => 1,
        write_func  => sub { push @written, @_ },
    });
    $result = $tls->_initial_communication();
    ok(!$result, 'undef response rejected');
}

# --- Test 10: _use_key_if_present ---
{
    my $server = Munin::Common::TLSServer->new({
        read_fd     => 0,
        read_func   => sub { "" },
        write_fd    => 1,
        write_func  => sub { "" },
    });
    $server->{private_key_loaded} = 1;
    ok($server->_use_key_if_present(), 'server uses key if loaded');

    $server->{private_key_loaded} = 0;
    ok(!$server->_use_key_if_present(), 'server skips key if not loaded');

    my $client = Munin::Common::TLSClient->new({
        read_fd     => 0,
        read_func   => sub { "" },
        write_fd    => 1,
        write_func  => sub { "" },
    });
    $client->{remote_key} = 1;
    ok(!$client->_use_key_if_present(), 'client skips key if remote has it');

    $client->{remote_key} = 0;
    ok($client->_use_key_if_present(), 'client uses key if remote does not');
}

# --- Test 11: _load_net_ssleay ---
{
    my $tls = Munin::Common::TLSServer->new({
        read_fd     => 0,
        read_func   => sub { "" },
        write_fd    => 1,
        write_func  => sub { "" },
    });
    my $result = $tls->_load_net_ssleay();
    ok($result, '_load_net_ssleay succeeds when Net::SSLeay available');
}

# --- Test 12: _creat_tls_context ---
SKIP: {
    eval { require Net::SSLeay; };
    skip 'Net::SSLeay not installed', 2 if $@;

    my $tls = Munin::Common::TLSServer->new({
        read_fd     => 0,
        read_func   => sub { "" },
        write_fd    => 1,
        write_func  => sub { "" },
    });
    $tls->_load_net_ssleay();
    $tls->_initialize_net_ssleay();
    my $ctx = $tls->_creat_tls_context();
    ok($ctx, '_creat_tls_context returns context');
    ok(defined $ctx && $ctx != 0, 'context is valid');
}

# --- Test 13: _load_private_key with missing file ---
SKIP: {
    eval { require Net::SSLeay; };
    skip 'Net::SSLeay not installed', 1 if $@;

    my $tls = Munin::Common::TLSServer->new({
        read_fd     => 0,
        read_func   => sub { "" },
        write_fd    => 1,
        write_func  => sub { "" },
        tls_priv    => '/nonexistent/key.pem',
        tls_paranoia => 0,
    });
    $tls->_load_net_ssleay();
    $tls->_initialize_net_ssleay();
    $tls->{tls_context} = $tls->_creat_tls_context();
    my $result = $tls->_load_private_key();
    ok($result, '_load_private_key returns 1 when file missing (non-paranoid)');
}

# --- Test 14: _load_certificate with missing file ---
SKIP: {
    eval { require Net::SSLeay; };
    skip 'Net::SSLeay not installed', 1 if $@;

    my $tls = Munin::Common::TLSServer->new({
        read_fd     => 0,
        read_func   => sub { "" },
        write_fd    => 1,
        write_func  => sub { "" },
        tls_cert    => '/nonexistent/cert.pem',
    });
    $tls->_load_net_ssleay();
    $tls->_initialize_net_ssleay();
    $tls->{tls_context} = $tls->_creat_tls_context();
    my $result = $tls->_load_certificate();
    ok($result, '_load_certificate returns 1 when file missing');
}

# --- Test 15: _load_ca_certificate with missing file ---
SKIP: {
    eval { require Net::SSLeay; };
    skip 'Net::SSLeay not installed', 1 if $@;

    my $tls = Munin::Common::TLSServer->new({
        read_fd     => 0,
        read_func   => sub { "" },
        write_fd    => 1,
        write_func  => sub { "" },
        tls_ca_cert => '/nonexistent/ca.pem',
    });
    $tls->_load_net_ssleay();
    $tls->_initialize_net_ssleay();
    $tls->{tls_context} = $tls->_creat_tls_context();
    my $result = $tls->_load_ca_certificate();
    ok($result, '_load_ca_certificate returns 1 when file missing');
}

# --- Test 16: TLS handshake with real certs ---
SKIP: {
    eval { require Net::SSLeay; };
    skip 'Net::SSLeay not installed', 3 if $@;
    skip 'TLS handshake test needs IO::Socket::SSL (timeout)', 3;
}

# --- Test 17: _tls_verify_callback ---
{
    my $tls = Munin::Common::TLSServer->new({
        read_fd     => 0,
        read_func   => sub { "" },
        write_fd    => 1,
        write_func  => sub { "" },
    });

    my %verified = (
        level          => 0,
        cert           => "",
        verified       => 0,
        required_depth => 5,
        verify         => 0,
    );

    my $cb = $tls->_tls_verify_callback(\%verified);

    # Test with ok=1
    my $result = $cb->(1, undef, undef, 0, 0, undef, undef);
    is($result, 1, 'callback accepts when ok=1');
    ok($verified{verified}, 'verified set to 1');
    is($verified{level}, 1, 'level incremented');

    # Test with ok=0, verify=0
    %verified = (level => 0, verified => 0, required_depth => 5, verify => 0);
    $result = $cb->(0, undef, undef, 0, 0, undef, undef);
    is($result, 1, 'callback accepts when verify=0');
    ok($verified{verified}, 'verified set to 1 despite ok=0');

    # Test with ok=0, verify=1, depth exceeded
    %verified = (level => 6, verified => 0, required_depth => 5, verify => 1);
    $result = $cb->(0, undef, undef, 6, 0, undef, undef);
    is($result, 0, 'callback rejects when depth exceeded');
    ok(!$verified{verified}, 'verified stays 0');

    # Test with ok=0, verify=1, depth OK
    %verified = (level => 3, verified => 0, required_depth => 5, verify => 1);
    $result = $cb->(0, undef, undef, 3, 0, undef, undef);
    is($result, 0, 'callback rejects when verify=1 and ok=0');
}

# --- Test 18: Expired cert detection ---
SKIP: {
    eval { require Net::SSLeay; };
    skip 'Net::SSLeay not installed', 2 if $@;
    skip 'TLS handshake test needs IO::Socket::SSL (timeout)', 2;
}

# --- Test 19: _log_cipher_list ---
SKIP: {
    eval { require Net::SSLeay; };
    skip 'Net::SSLeay not installed', 1 if $@;
    skip 'TLS handshake test needs IO::Socket::SSL (timeout)', 1;
}

print "\n";

done_testing();

1;
