use strict;
use warnings;

use lib qw(lib t/lib);

use Test::More;
use IO::Socket::INET;
use File::Temp qw(tempdir);
use File::Path qw(remove_tree);
use POSIX ":sys_wait_h";

# Skip if no Net::SSLeay
eval { require Net::SSLeay; };
plan skip_all => 'Net::SSLeay not installed' if $@;

use Munin::Common::TLS;
use Munin::Common::TLSServer;
use Munin::Common::TLSClient;

# ============================================================================
# SETUP: Generate test certificates
# ============================================================================

my $tls_dir;

# END block disabled to debug SEGV
# END {
#     remove_tree($tls_dir) if $tls_dir && -d $tls_dir;
# };

require TestTLS;
$tls_dir = TestTLS::generate_test_certs();

# ============================================================================
# HELPER: Create connected socket pair
# ============================================================================

sub create_socket_pair {
    my $server = IO::Socket::INET->new(
        Listen => 1, LocalAddr => '127.0.0.1', LocalPort => 0,
        Proto => 'tcp', ReuseAddr => 1,
    ) or die "Cannot create server socket: $!";
    my $port = $server->sockport();
    my $client = IO::Socket::INET->new(
        PeerAddr => '127.0.0.1', PeerPort => $port, Proto => 'tcp',
    ) or die "Cannot connect: $!";
    my $accepted = $server->accept() or die "Cannot accept: $!";
    return ($accepted, $client, $server);
}

# ============================================================================
# HELPER: Fork TLS server, return (pid, client_sock, sync_r)
# ============================================================================

sub fork_tls_server {
    my (%opts) = @_;
    my ($accepted, $client_sock, $server_listen) = create_socket_pair();
    my ($sync_r, $sync_w);
    pipe($sync_r, $sync_w) or die "pipe: $!";

    my $pid = fork();
    die "Cannot fork: $!" unless defined $pid;

    if ($pid == 0) {
        close $sync_r;
        my $tls = Munin::Common::TLSServer->new({
            read_fd => fileno($accepted),
            read_func => sub { my $b; sysread($accepted, $b, 4096) ? $b : undef },
            write_fd => fileno($accepted),
            write_func => sub { syswrite($accepted, $_[0]) },
            tls_cert    => "$tls_dir/master_cert.pem",
            tls_priv    => "$tls_dir/master_key.pem",
            tls_ca_cert => "$tls_dir/CA/ca_cert.pem",
            tls_verify  => $opts{tls_verify}  // 0,
            tls_paranoia => $opts{tls_paranoia} // '',
            DEBUG       => $opts{debug}        // 0,
        });
        print $sync_w "ready\n";
        close $sync_w;

        # In real munin, main loop reads STARTTLS before calling start_tls
        my $req = $tls->{read_func}->();
        my $session = $tls->start_tls();
        if ($session && $opts{echo}) {
            my $data = $tls->read();
            $tls->write("echo:$data") if defined $data;
        }
        # Explicit cleanup to avoid SEGV in exit
        if ($tls->{tls_session}) {
            Net::SSLeay::free($tls->{tls_session});
            $tls->{tls_session} = undef;
        }
        if ($tls->{tls_context}) {
            Net::SSLeay::CTX_free($tls->{tls_context});
            $tls->{tls_context} = undef;
        }
        close $accepted;
        POSIX::_exit(0);
    }

    close $sync_w;
    close $accepted;
    return ($pid, $client_sock, $sync_r, $server_listen);
}

# ============================================================================
# HELPER: Connect TLS client
# ============================================================================

sub connect_tls_client {
    my (%opts) = @_;
    my $client_sock = delete $opts{client_sock} or die "client_sock required";
    return Munin::Common::TLSClient->new({
        read_fd => fileno($client_sock),
        read_func => sub { my $b; sysread($client_sock, $b, 4096) ? $b : undef },
        write_fd => fileno($client_sock),
        write_func => sub { syswrite($client_sock, $_[0]) },
        tls_cert    => "$tls_dir/node_cert.pem",
        tls_priv    => "$tls_dir/node_key.pem",
        tls_ca_cert => "$tls_dir/CA/ca_cert.pem",
        tls_verify  => $opts{tls_verify}  // 0,
        tls_paranoia => $opts{tls_paranoia} // '',
        DEBUG       => $opts{debug}        // 0,
    });
}

# ============================================================================
# TESTS: Module loading
# ============================================================================

ok(Munin::Common::TLS->isa('Munin::Common::TLS'), 'TLS loaded');
ok(Munin::Common::TLSServer->isa('Munin::Common::TLSServer'), 'TLSServer loaded');
ok(Munin::Common::TLSClient->isa('Munin::Common::TLSClient'), 'TLSClient loaded');

# ============================================================================
# TESTS: Constructor
# ============================================================================

subtest 'constructor validation' => sub {
    for my $key (qw(read_fd read_func write_fd write_func)) {
        my %args = (read_fd => 0, read_func => sub { "" },
                    write_fd => 1, write_func => sub { "" });
        delete $args{$key};
        eval { Munin::Common::TLS->new(\%args) };
        like($@, qr/Required argument missing: $key/, "dies without $key");
    }
};

subtest 'constructor with all args' => sub {
    my $tls = Munin::Common::TLSServer->new({
        read_fd => 0, read_func => sub { "" },
        write_fd => 1, write_func => sub { "" },
        DEBUG => 1, tls_ca_cert => "$tls_dir/CA/ca_cert.pem",
        tls_cert => "$tls_dir/master_cert.pem", tls_priv => "$tls_dir/master_key.pem",
        tls_paranoia => 0, tls_vdepth => 5, tls_verify => 1,
    });
    isa_ok($tls, 'Munin::Common::TLSServer');
    is($tls->{DEBUG}, 1, 'DEBUG set');
    is($tls->{tls_vdepth}, 5, 'vdepth set');
};

subtest 'reject unknown args' => sub {
    eval { Munin::Common::TLSServer->new({
        read_fd => 0, read_func => sub { "" },
        write_fd => 1, write_func => sub { "" }, unknown_arg => 42,
    }) };
    like($@, qr/Unrecognized argument/, 'dies on unknown arg');
};

subtest 'session_started' => sub {
    my $tls = Munin::Common::TLSServer->new({
        read_fd => 0, read_func => sub { "" },
        write_fd => 1, write_func => sub { "" },
    });
    ok(!$tls->session_started(), 'false initially');
};

# ============================================================================
# TESTS: read/write without session
# ============================================================================

subtest 'read/write without session' => sub {
    my $tls = Munin::Common::TLSServer->new({
        read_fd => 0, read_func => sub { "" },
        write_fd => 1, write_func => sub { "" },
    });
    eval { $tls->read() };
    like($@, qr/TLS session is not started/, 'read dies');
    eval { $tls->write("test") };
    like($@, qr/TLS session is not started/, 'write dies');
};

# ============================================================================
# TESTS: Abstract methods
# ============================================================================

subtest 'abstract methods die' => sub {
    my $tls = Munin::Common::TLS->new({
        read_fd => 0, read_func => sub { "" },
        write_fd => 1, write_func => sub { "" },
    });
    eval { $tls->_initial_communication() };
    like($@, qr/Abstract method/, '_initial_communication dies');
    eval { $tls->_use_key_if_present() };
    like($@, qr/Abstract method/, '_use_key_if_present dies');
};

# ============================================================================
# TESTS: _initial_communication
# ============================================================================

subtest 'TLSServer _initial_communication' => sub {
    my @written;
    my $tls = Munin::Common::TLSServer->new({
        read_fd => 0, read_func => sub { "" },
        write_fd => 1, write_func => sub { push @written, @_ },
    });
    $tls->{private_key_loaded} = 0;
    $tls->_initial_communication();
    is($written[0], "TLS MAYBE\n", 'no key => TLS MAYBE');

    @written = ();
    $tls->{private_key_loaded} = 1;
    $tls->_initial_communication();
    is($written[0], "TLS OK\n", 'key loaded => TLS OK');
};

subtest 'TLSClient _initial_communication' => sub {
    for my $case (
        ["TLS OK\n",    1, 'TLS OK',   1],
        ["TLS MAYBE\n", 1, 'TLS MAYBE', 0],
        ["BAD\n",       0, 'bad',       0],
    ) {
        my ($resp, $expect, $desc, $expect_key) = @$case;
        my @written;
        my $tls = Munin::Common::TLSClient->new({
            read_fd => 0, read_func => sub { $resp },
            write_fd => 1, write_func => sub { push @written, @_ },
        });
        is($tls->_initial_communication(), $expect, "$desc result");
        is($tls->{remote_key}, $expect_key, "$desc remote_key");
    }
};

# ============================================================================
# TESTS: _use_key_if_present
# ============================================================================

subtest '_use_key_if_present' => sub {
    my $server = Munin::Common::TLSServer->new({
        read_fd => 0, read_func => sub { "" },
        write_fd => 1, write_func => sub { "" },
    });
    $server->{private_key_loaded} = 1;
    ok($server->_use_key_if_present(), 'server uses key if loaded');
    $server->{private_key_loaded} = 0;
    ok(!$server->_use_key_if_present(), 'server skips if not loaded');

    my $client = Munin::Common::TLSClient->new({
        read_fd => 0, read_func => sub { "" },
        write_fd => 1, write_func => sub { "" },
    });
    $client->{remote_key} = 1;
    ok(!$client->_use_key_if_present(), 'client skips if remote has key');
    $client->{remote_key} = 0;
    ok($client->_use_key_if_present(), 'client uses if remote lacks key');
};

# ============================================================================
# TESTS: Net::SSLeay methods
# ============================================================================

subtest '_load_net_ssleay' => sub {
    my $tls = Munin::Common::TLSServer->new({
        read_fd => 0, read_func => sub { "" },
        write_fd => 1, write_func => sub { "" },
    });
    ok($tls->_load_net_ssleay(), 'succeeds');
};

subtest 'TLS context creation' => sub {
    my $tls = Munin::Common::TLSServer->new({
        read_fd => 0, read_func => sub { "" },
        write_fd => 1, write_func => sub { "" },
        tls_priv => "$tls_dir/master_key.pem",
        tls_cert => "$tls_dir/master_cert.pem",
        tls_ca_cert => "$tls_dir/CA/ca_cert.pem",
    });
    $tls->_load_net_ssleay();
    $tls->_initialize_net_ssleay();
    my $ctx = $tls->_creat_tls_context();
    ok($ctx, 'context created');
    $tls->{tls_context} = $ctx;
    ok($tls->_load_private_key(), 'private key loaded');
    ok($tls->_load_certificate(), 'certificate loaded');
    ok($tls->_load_ca_certificate(), 'CA loaded');
};

subtest '_load_private_key missing' => sub {
    my $tls = Munin::Common::TLSServer->new({
        read_fd => 0, read_func => sub { "" },
        write_fd => 1, write_func => sub { "" },
        tls_priv => '/nonexistent/key.pem', tls_paranoia => 0,
    });
    $tls->_load_net_ssleay();
    $tls->_initialize_net_ssleay();
    $tls->{tls_context} = $tls->_creat_tls_context();
    ok($tls->_load_private_key(), 'non-paranoid returns 1');
    Net::SSLeay::CTX_free($tls->{tls_context});

    my $tls2 = Munin::Common::TLSServer->new({
        read_fd => 0, read_func => sub { "" },
        write_fd => 1, write_func => sub { "" },
        tls_priv => '/nonexistent/key.pem', tls_paranoia => 'paranoid',
    });
    $tls2->_load_net_ssleay();
    $tls2->_initialize_net_ssleay();
    $tls2->{tls_context} = $tls2->_creat_tls_context();
    ok(!$tls2->_load_private_key(), 'paranoid returns 0');
    Net::SSLeay::CTX_free($tls2->{tls_context});
};

subtest '_tls_verify_callback' => sub {
    my $tls = Munin::Common::TLSServer->new({
        read_fd => 0, read_func => sub { "" },
        write_fd => 1, write_func => sub { "" },
    });
    my $cb = $tls->_tls_verify_callback({
        level => 0, verified => 0, required_depth => 5, verify => 0,
    });
    is($cb->(1, undef, undef, 0, 0, undef, undef), 1, 'ok=1 accepts');

    my %v = (level => 0, verified => 0, required_depth => 5, verify => 0);
    $cb = $tls->_tls_verify_callback(\%v);
    is($cb->(0, undef, undef, 0, 0, undef, undef), 1, 'verify=0 accepts');
    ok($v{verified}, 'verified despite ok=0');

    %v = (level => 6, verified => 0, required_depth => 5, verify => 1);
    $cb = $tls->_tls_verify_callback(\%v);
    is($cb->(0, undef, undef, 6, 0, undef, undef), 0, 'depth exceeded');
};

subtest '_on_unmatched_cert no-op' => sub {
    my $tls = Munin::Common::TLSClient->new({
        read_fd => 0, read_func => sub { "" },
        write_fd => 1, write_func => sub { "" },
    });
    $tls->_on_unmatched_cert();
    ok(1, 'no crash');
};

subtest '_log_cipher_list + _set_ssleay_file_descriptors' => sub {
    my $tls = Munin::Common::TLSServer->new({
        read_fd => 0, read_func => sub { "" },
        write_fd => 1, write_func => sub { "" },
        tls_priv => "$tls_dir/master_key.pem",
        tls_cert => "$tls_dir/master_cert.pem",
        tls_ca_cert => "$tls_dir/CA/ca_cert.pem",
    });
    $tls->_load_net_ssleay();
    $tls->_initialize_net_ssleay();
    $tls->{tls_context} = $tls->_creat_tls_context();
    $tls->_load_private_key();
    $tls->_load_certificate();
    $tls->_load_ca_certificate();
    $tls->{tls_session} = Net::SSLeay::new($tls->{tls_context});
    if ($tls->{tls_session}) {
        $tls->_log_cipher_list();
        ok(1, '_log_cipher_list OK');
        $tls->_set_ssleay_file_descriptors();
        ok(1, '_set_ssleay_file_descriptors OK');
        Net::SSLeay::free($tls->{tls_session});
        Net::SSLeay::CTX_free($tls->{tls_context});
    } else {
        fail('Could not create session');
    }
};

# ============================================================================
# TEST: Full TLS handshake + echo
# ============================================================================

subtest 'TLS handshake + echo (no verify)' => sub {
    my ($pid, $client_sock, $sync_r) = fork_tls_server(echo => 1, tls_verify => 0);
    my $tls = connect_tls_client(client_sock => $client_sock, tls_verify => 0);

    my $ready = <$sync_r>;
    close $sync_r;

    my $session = $tls->start_tls();
    ok(defined $session, 'TLS session established');
    ok($tls->session_started(), 'session_started true');

    $tls->write("hello");
    my $response = $tls->read();
    is($response, "echo:hello", 'encrypted echo works');

    close $client_sock;
    waitpid($pid, 0);
    is($?, 0, 'server exited OK');
};

# ============================================================================
# TEST: Full TLS handshake with verification
# ============================================================================

subtest 'TLS handshake + echo (with verify)' => sub {
    my ($pid, $client_sock, $sync_r) = fork_tls_server(echo => 1, tls_verify => 1);
    my $tls = connect_tls_client(client_sock => $client_sock, tls_verify => 1);

    my $ready = <$sync_r>;
    close $sync_r;

    my $session = $tls->start_tls();
    ok(defined $session, 'verified TLS session established');

    $tls->write("test");
    my $response = $tls->read();
    is($response, "echo:test", 'verified echo works');

    close $client_sock;
    waitpid($pid, 0);
    is($?, 0, 'server exited OK');
};

# ============================================================================
# TEST: _start_tls failure paths
# ============================================================================

subtest '_start_tls fails when _load_net_ssleay fails' => sub {
    my $tls = Munin::Common::TLSServer->new({
        read_fd => 0, read_func => sub { "" },
        write_fd => 1, write_func => sub { "" },
    });
    no warnings 'redefine';
    my $orig = \&Munin::Common::TLSServer::_load_net_ssleay;
    *Munin::Common::TLSServer::_load_net_ssleay = sub { 0 };
    is($tls->start_tls(), 0, 'returns 0');
    *Munin::Common::TLSServer::_load_net_ssleay = $orig;
    use warnings 'redefine';
};

subtest '_start_tls fails when _load_private_key fails' => sub {
    my $tls = Munin::Common::TLSServer->new({
        read_fd => 0, read_func => sub { "" },
        write_fd => 1, write_func => sub { "" },
        tls_paranoia => 'paranoid', tls_priv => '/nonexistent/key.pem',
    });
    is($tls->start_tls(), 0, 'returns 0');
};

subtest '_start_tls fails when _initial_communication fails' => sub {
    my $tls = Munin::Common::TLSServer->new({
        read_fd => 0, read_func => sub { "" },
        write_fd => 1, write_func => sub { "" },
    });
    no warnings 'redefine';
    my $orig = \&Munin::Common::TLSServer::_initial_communication;
    *Munin::Common::TLSServer::_initial_communication = sub { 0 };
    is($tls->start_tls(), 0, 'returns 0');
    *Munin::Common::TLSServer::_initial_communication = $orig;
    use warnings 'redefine';
};

done_testing();

1;
