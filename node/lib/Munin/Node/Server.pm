package Munin::Node::Server;

# $Id$

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
use Munin::Node::Utils;

# A set of all services that this node can run.
my %services;

# Services that require the server to support multigraph plugins.
my @multigraph_services;

# Which hosts this node's services applies to. Typically this is the
# same as the host the node is running on, but some services query
# other hosts (e.g SNMP services).
my %nodes;


my $config = Munin::Node::Config->instance();


sub pre_loop_hook {
    my $self = shift;
    print STDERR "In pre_loop_hook.\n" if $config->{DEBUG};
    _load_services();
    Munin::Node::Service->prepare_plugin_environment(keys %services);
    _add_services_to_nodes(keys %services);
    return $self->SUPER::pre_loop_hook();
}


sub request_denied_hook {
    my $self = shift;
    logger("Denying connection from: $self->{server}->{peeraddr}");
    return;
}


sub _load_services {
    opendir (my $DIR, $config->{servicedir})
        || die "Cannot open plugindir: $config->{servicedir} $!";

    for my $file (readdir($DIR)) {
        next unless Munin::Node::Service->is_a_runnable_service($file);
        print STDERR "file: '$file'\n" if $config->{DEBUG};
        $services{$file} = 1;
    }

    closedir $DIR;
    return;
}


# Runs config on each plugin, and add them to the right nodes and plugin groups.
sub _add_services_to_nodes
{
    my (@services) = @_;

    for my $service (keys %services) {
        print STDERR "Configuring $service\n";

        my $res = eval {
            local $SIG{CHLD}; # stop Net::Server from reaping the dead service too fast
            Munin::Node::Service->fork_service($config->{servicedir},
                                               $service,
                                               'config');
        };

        # FIXME: report errors, and remove any plugins that failed from %services;
        next if ($EVAL_ERROR or $res->{timed_out} or $res->{retval});

        my ($host_name) = grep /^host_name /, @{$res->{stdout}};
        my $node = $config->{sconf}{$service}{host_name}
                || (split /\s+/, ($host_name || ''))[1]
                || $config->{fqdn};

        $nodes{$node}{$service} = 1;

        # Note any plugins that require particular server capabilities.
        if (grep /^multigraph\s+/, @{$res->{stdout}}) {
           push @multigraph_services, $service;
        }
    }
    print STDERR "Finished configuring services\n";

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

    my @node_cap = qw( multigraph );
    $session->{server_capabilities}
        = { map { $_ => 1 } split(/ /, $server_capabilities) };

    _net_write($session, sprintf("cap %s\n",join(" ", @node_cap)));
}


sub _process_starttls_command {
    my ($session) = @_;

    my $mode = $session->{tls_mode};

    my $key        = $config->{tls_private_key}
                  || "$Munin::Common::Defaults::MUNIN_CONFDIR/munin-node.pem";
    my $cert       = $config->{tls_certificate}
                  || "$Munin::Common::Defaults::MUNIN_CONFDIR/munin-node.pem";
    my $ca_cert    = $config->{tls_ca_certificate}
                  || "$Munin::Common::Defaults::MUNIN_CONFDIR/cacert.pem";
    my $tls_verify = $config->{tls_verify_certificate}
                  || 'no';

    my $depth = $config->{tls_verify_depth}
    $depth = 5 unless defined $depth;

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

    if (exists $nodes{$node}) {
        # remove any plugins that require capabilities the server doesn't provide
        my @services = keys %{$nodes{$node}};
        @services = Munin::Node::Utils::set_difference(\@services, \@multigraph_services)
            unless $session->{server_capabilities}{multigraph};

        _net_write($session, join(" ", @services));
    }
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

Loads all the plugins (services).

=item B<request_denied_hook>

Logs the source of rejected connections.

=item B<process_request>

Processes the request.

=cut
vim: ts=4 : expandtab
