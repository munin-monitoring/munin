package Munin::Node::Server;
use base qw(Net::Server::Fork);

use strict;
use warnings;

use English qw(-no_match_vars);
use Carp;

use Munin::Node::Config;
use Munin::Common::Defaults;
use Munin::Common::Timeout;
use Munin::Common::TLSServer;
use Munin::Node::Logger;
use Munin::Node::Service;
use Munin::Node::Session;

# A set of all services that this node can run.
my %services;

# Which hosts this node's services applies to. Typically this is the
# same as the host the node is running on, but some services query
# other hosts (e.g SNMP services).
my %nodes;


my $config = Munin::Node::Config->instance();


sub pre_loop_hook {
    my $self = shift;
    print STDERR "In pre_loop_hook.\n" if $config->{DEBUG};
    _load_service_configurations();
    _load_services();
    $self->SUPER::pre_loop_hook();
}


sub _load_service_configurations {
    $config->process_plugin_configuration_files();
    $config->apply_wildcards();
    return;
}


sub _load_services {
    opendir (my $DIR, $config->{servicedir}) 
        || die "Cannot open plugindir: $config->{servicedir} $!";

    for my $file (readdir($DIR)) {
        next unless Munin::Node::Service->is_a_runnable_service($file);
        print STDERR "file: '$file'\n" if $config->{DEBUG};
        _add_to_services_and_nodes($file);
    }

    closedir $DIR;
    return;
}


sub process_request {
    my $self = shift;

    my $session = Munin::Node::Session->new();

    $session->{tls}          = undef;
    $session->{tls_started}  = 0;
    $session->{tls_mode}     = $config->{tls} || 'auto';
    $session->{peer_address} = $self->{server}->{peeraddr};

    $PROGRAM_NAME .= " [$session->{peer_address}]";

    _net_write($session, "# munin node at $config->{fqdn}\n");

    my $timed_out = !do_with_timeout($config->{'timeout'}, sub {
        while (defined (my $line = _net_read($session))) {
            chomp $line;
            _process_command_line($session, $line) 
                or last;
        }
    });

    if ($timed_out) {
        logger("Connection timed out");
    }
}


sub _process_command_line {
    my ($session, $cmd_line) = @_;

    reset_timeout();

    local $_ = $cmd_line;

    if (_expect_starttls($session)) {
        if (!(/^starttls\s*$/i)) {
            logger ("ERROR: Client did not request TLS. Closing.");
            _net_write($session, "# I require TLS. Closing.\n");
            return 0;
        }
    }

    logger ("DEBUG: Running command \"$_\".") if $config->{DEBUG};
    if (/^list\s*([0-9a-zA-Z\.\-]+)?/i) {
        _list_services($session, $1);
    }
    elsif (/^cap\s?(.*)/i) {
        _negotiate_session_capabilities($session, $1);
    }
    elsif (/^quit/i || /^\./) {
        exit 1;
    } 
    elsif (/^version/i) {
        _show_version($session);
    } 
    elsif (/^nodes/i) {
        _show_nodes($session);
    }
    elsif (/^fetch\s?(\S*)/i) {
        _print_service($session, _run_service($session, $1)) 
    }
    elsif (/^config\s?(\S*)/i) {
        _print_service($session, _run_service($session, $1, "config"));
    }
    elsif (/^starttls\s*$/i) {
        eval {
            $session->{tls_started} = _process_starttls_command($session);
        };
        if ($EVAL_ERROR) {
            logger($EVAL_ERROR);
            return 0;
        }
        logger ("DEBUG: Returned from starttls.") if $config->{DEBUG};
    }
    else {
        _net_write($session, "# Unknown command. Try cap, list, nodes, config, fetch, version or quit\n");
    }

    return 1;
}


sub _expect_starttls {
    my ($session) = @_;
    
    return !$session->{tls_started} 
        && ($session->{tls_mode} eq 'paranoid' || $session->{tls_mode} eq 'enabled');
}


sub _negotiate_session_capabilities {
    my ($session, $server_capabilities) = @_;

    my %node_cap   = map { $_ => 1 } qw(foo bar baz);
    my %server_cap = map { $_ => 1 } split(/ /, $server_capabilities);

    my %session_capabilities = map { $_ => 1 } grep { $server_cap{$_} } keys %node_cap;
    $session->{capabilities} = \%session_capabilities;

    _net_write($session, sprintf("# Node capabilities: (%s). Session capabilities: (\n", 
                       join(' ', keys %node_cap)));
    _net_write($session, join(' ', keys %session_capabilities) . "\n");
    _net_write($session, "# )\n.\n");

}


sub _process_starttls_command {
    my ($session) = @_;

    my $mode = $session->{tls_mode};

    my $key;
    my $cert;
    my $depth;
    my $ca_cert;
    my $tls_verify;

    $key = $config->{tls_private_key};
    $key = "$Munin::Common::Defaults::MUNIN_CONFDIR/munin-node.pem" 
        unless defined $key;

    $cert = $config->{tls_certificate};
    $cert = "$Munin::Common::Defaults::MUNIN_CONFDIR/munin-node.pem" 
        unless defined $cert;

    $ca_cert = $config->{tls_ca_certificate};
    $ca_cert = "$Munin::Common::Defaults::MUNIN_CONFDIR/cacert.pem" 
        unless defined $ca_cert;

    $depth = $config->{tls_verify_depth};
    $depth = 5 unless defined $depth;

    $tls_verify = $config->{tls_verify_certificate};
    $tls_verify = "no" unless defined $tls_verify;

    $session->{tls} = Munin::Common::TLSServer->new({
        DEBUG        => $config->{DEBUG},
        logger       => \&logger,
        read_fd      => fileno(STDIN),
        read_func    => sub { die "Shouln't need to read!?" },
        tls_ca_cert  => $ca_cert,
        tls_cert     => $cert,
        tls_paranoia => $mode, 
        tls_priv     => $key,
        tls_vdepth   => $depth,
        tls_verify   => $tls_verify,
        write_fd     => fileno(STDOUT),
        write_func   => sub { print @_ },
    });

    if ($session->{tls}->start_tls()) {
        return 1;
    }
    else {
        if ($mode eq "paranoid" or $mode eq "enabled") {
            die "ERROR: Could not establish TLS connection. Closing.";
        }
        $session->{tls} = undef;
        return 0;
    }
}


sub _show_version {
    print "munins node on $config->{fqdn} version: $Munin::Common::Defaults::MUNIN_VERSION\n"
}


sub _show_nodes {
    my ($session) = @_;
    
    for my $node (keys %nodes) {
        _net_write($session, "$node\n");
    }
    _net_write($session, ".\n");
}


sub _add_to_services_and_nodes {
    my ($service) = @_;

    $services{$service} = 1;
    # FIXME: may need to query the plugin to get host_name.  eg. in the case of
    # SNMP plugins.
    my $node = $config->{sconf}{$service}{host_name} || $config->{fqdn};
    $nodes{$node}{$service} = 1;
}


sub _print_service {
  my ($session, @lines) = @_;
  for my $line (@lines) {
    _net_write($session, "$line\n");
  }
  _net_write($session, ".\n");
}


sub _list_services {
    my ($session, $node) = @_;
    $node ||= $config->{fqdn};
    _net_write($session, join(" ", keys %{$nodes{$node}}))
        if exists $nodes{$node};
    _net_write($session, "\n");
}


sub _run_service {
    # FIXME: $autoreap is never set?
    my ($session, $service, $command, $autoreap) = @_;

    unless ($services{$service}) {
        _net_write($session, "# Unknown service");
        return;
    }

    my $res = eval { Munin::Node::Service->fork_service($config->{servicedir},
                                                        $service,
                                                        $command);
    };

    if ($EVAL_ERROR) {
        # Error forking, building pipes, etc
        logger("System error: $EVAL_ERROR");
        return;
    }

    if ($res->{timed_out}) {
        my $msg = "timeout: $service $command.";
        _net_write($session, "# $msg\n");
        logger("Plugin $msg");
        return;
    }

    if ($res->{retval}) {
        my $plugin_exit   = $res->{retval} >> 8;
        my $plugin_signal = $res->{retval} & 127;

#       logger(qq{Plugin '$service' exited with status $CHILD_ERROR. --@lines--});
        return;
    }

    return (@{ $res->{stdout} });
}


sub _net_read {
    my ($session) = @_;

    local $_;

    if ($session->{tls} && $session->{tls}->session_started()) {
        $_ = $session->{tls}->read();
    }
    else {
        $_ = <STDIN>;
    }
    logger('DEBUG: < ' . (defined $_ ? $_ : 'undef')) if $config->{DEBUG};
    return $_;
}


sub _net_write {
    my ($session, $text) = @_;
    logger("DEBUG: > $text") if $config->{DEBUG};
    if ($session->{tls} && $session->{tls}->session_started()) {
        $session->{tls}->write($text);
    }
    else {
        print STDOUT $text;
    }
}


1;

__END__

=head1 NAME

Munin::Node::Server - This module implements a Net::Server server for
the munin node.

=head1 SYNOPSIS

 use Munin::Node::Server;
 Munin::Node::Server->run(...);
 
For arguments to run(), see L<Net::Server>.

=head1 METHODS

=head2 NET::SERVER "CALLBACKS"

=over

=item B<pre_loop_hook>

Loads all the plugins (services)

=item B<process_request>

Processes the request ...

=cut
vim: ts=4 : expandtab
