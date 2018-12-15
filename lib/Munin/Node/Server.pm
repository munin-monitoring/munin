package Munin::Node::Server;


use base qw(Net::Server::Fork);

use strict;
use warnings;

use English qw(-no_match_vars);

use Munin::Node::Config;
use Munin::Common::Defaults;
use Munin::Common::Timeout;
use Munin::Common::TLSServer;
use Munin::Common::Logger;
use Munin::Node::Session;
use Munin::Node::Utils;


# the Munin::Node::Service object, used to run plugins, etc
my $services;

# may reference a Munin::Node::SpoolReader object, which is used to
# to provide spooling functionality.
my $spool;

# A set of all services that this node can run.
my %services;

# Services that require the server to support certain capabilities
my (@multigraph_services, @dirtyconfig_services);

# Which hosts this node's services applies to. Typically this is the
# same as the host the node is running on, but some services query
# other hosts (e.g SNMP services).
my %nodes;


my $config = Munin::Node::Config->instance();


sub pre_loop_hook {
    my $self = shift;
    DEBUG("In pre_loop_hook.") if $config->{DEBUG};

    $services = $config->{services} or die 'no services list';
    $spool    = $config->{spool};

    my @services = $services->list;
    @services{@services} = (1) x @services;

    $services->prepare_plugin_environment(keys %services);
    _add_services_to_nodes(keys %services);
    return $self->SUPER::pre_loop_hook();
}


sub request_denied_hook
{
    my $self = shift;
    NOTICE("Denying connection from: $self->{server}->{peeraddr}");
    return;
}


# Runs config on each plugin, and add them to the right nodes and plugin groups.
sub _add_services_to_nodes
{
    my (@services) = @_;

    for my $service (@services) {
        DEBUG("Configuring $service\n") if $config->{DEBUG};

        my @response = _run_service($service, 'config');

        if (!@response or grep(/# Timed out/, @response)) {
            DEBUG("Error running $service.  Dropping it.") if $config->{DEBUG};
            delete $services{$service};
            next;
        }

        my ($host_name) = grep /^host_name /, @response;
        my $node = $config->{sconf}{$service}{host_name}
                || (split /\s+/, ($host_name || ''))[1]
                || $config->{fqdn};

        # hostname checks are case insensitive, so store everything in lowercase
        $node = lc($node);

        DEBUG("\tAdding to node $node") if $config->{DEBUG};
        push @{$nodes{$node}}, $service;

        # Note any plugins that require particular server capabilities.
        if (grep /^multigraph\s+/, @response) {
            DEBUG("\tAdding to multigraph plugins") if $config->{DEBUG};
            push @multigraph_services, $service;
        }
        if (grep /^[A-Za-z0-9_]+\.value /, @response) {
            # very dirty plugins -- they do a dirtyconfig even when
            # "not allowed" by their environment.
            DEBUG("\tAdding to dirty plugins") if $config->{DEBUG};
            push @dirtyconfig_services, $service;
        }
    }
    DEBUG("Finished configuring services") if $config->{DEBUG};

    return;
}


sub process_request
{
    my $self = shift;

    my $timed_out;
    my $session = Munin::Node::Session->new();

    $session->{tls}          = undef;
    $session->{tls_started}  = 0;
    $session->{tls_mode}     = $config->{tls} || 'auto';
    $session->{peer_address} = $self->{server}->{peeraddr};

    $0 .= " [$session->{peer_address}]";

    # Used to provide per-master state-files
    $ENV{MUNIN_MASTER_IP} = $session->{peer_address};

    _net_write($session, "# munin node at $config->{fqdn}\n");

    my $line = '<no command received yet>';

    # catch and report any system errors in a clean way.
    eval {
	my $global_timeout = $config->{global_timeout} || (60 * 15); # Defaults to 15 min. Should be enough
        $timed_out = !do_with_timeout($global_timeout, sub {
            while (defined ($line = _net_read($session))) {
                chomp $line;
		if (! _process_command_line($session, $line)) {
		    $line = "<finished '$line', ending input loop>";
		    last;
		}
		$line = "<waiting for input from master, previous was '$line'>";
            }
	    return 1;
        });
    };

    ERROR($@)                                   if ($@);
    ERROR("Node side timeout while processing: '$line'") if ($timed_out);

    return;
}


# This method is used by Net::Server for retrieving default values (in case they are not specified
# in the given "conf_file").
sub default_values {
    return {
        port => 4949,
    };
}


sub _process_command_line {
    my ($session, $cmd_line) = @_;

    local $_ = $cmd_line;

    if (_expect_starttls($session)) {
        if (!(/^starttls\s*$/i)) {
            ERROR ("ERROR: Client did not request TLS. Closing.");
            _net_write($session, "# I require TLS. Closing.\n");
            return 0;
        }
    }

    DEBUG ("DEBUG: Running command '$_'.") if $config->{DEBUG};
    if (/^list\s*([0-9a-zA-Z\.\-]+)?/i) {
	my $hostname_lc = defined($1) ? lc($1) : undef;
        _list_services($session, $hostname_lc);
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
        _print_service($session, _run_service($1))
    }
    elsif (/^config\s?(\S*)/i) {
        _print_service($session, _run_service($1, 'config'));
    }
    elsif (/^spoolfetch (\d+)/ and $spool) {
        _net_write($session, $spool->fetch($1));
        _net_write($session, ".\n");
    }
    elsif (/^starttls\s*$/i) {
        eval {
            $session->{tls_started} = _process_starttls_command($session);
        };
        if ($@) {
            ERROR($@);
            return 0;
        }
        DEBUG ('DEBUG: Returned from starttls.') if $config->{DEBUG};
    }
    else {
        _net_write($session, "# Unknown command. Try cap, list, nodes, config, fetch, version or quit\n");
    }

    return 1;
}

# We override this function from Net::Server.  It prefers to read
# /proc/PID/cmdline, which causes $0 to become /usr/bin/perl (after a re-exec
# to the argv returned by this function), while we want to keep the value
# which is the path to the script itself.
sub _get_commandline {
  my $self = shift;

  my $script = $0;
  # make relative path absolute
  $script = $ENV{'PWD'} .'/'. $script if $script =~ m|^[^/]+/| && $ENV{'PWD'};
  # untaint for later use in hup
  # TBD: should we prevent script names containing TAB, LF and other unusual
  # characters?
  $script =~ /^(.+)$/;
  return [ $1, @ARGV ]
}


sub _expect_starttls {
    my ($session) = @_;

    return !$session->{tls_started}
        && ($session->{tls_mode} eq 'paranoid' || $session->{tls_mode} eq 'enabled');
}


sub _negotiate_session_capabilities
{
    my ($session, $server_capabilities) = @_;

    my $node_cap = 'multigraph dirtyconfig';
    $node_cap .= ' spool' if $spool;

    # telnet uses a full CRLF line ending.  chomp just removes the \n, so need
    # to strip \r manually.  see ticket #902
    $server_capabilities =~ s/\r$//;

    $session->{server_capabilities} = {
            map { $_ => 1 } split(/ /, $server_capabilities)
    };

    $ENV{MUNIN_CAP_DIRTYCONFIG} = 1 if ($session->{server_capabilities}{dirtyconfig});

    _net_write($session, "cap $node_cap\n");
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
                  || 0;
    my $tls_match  = $config->{tls_match};

    my $depth = $config->{tls_verify_depth};
    $depth = 5 unless defined $depth;

    $session->{tls} = Munin::Common::TLSServer->new({
        DEBUG        => $config->{DEBUG},
        read_fd      => fileno(STDIN),
        read_func    => sub { die "Shouldn't need to read!?" },
        tls_ca_cert  => $ca_cert,
        tls_cert     => $cert,
        tls_paranoia => $mode,
        tls_priv     => $key,
        tls_vdepth   => $depth,
        tls_verify   => $tls_verify,
        tls_match    => $tls_match,
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
    $node ||= lc($config->{fqdn});
    if (keys %nodes == 1 && ! exists $nodes{$node}) {
	    # Only one node. Naming mismatch. Just give the use what he wants.
	    ($node) = keys %nodes;
    }

    if (exists $nodes{$node}) {
        my @services = @{$nodes{$node}};

        # remove any plugins that require capabilities the master doesn't support
        @services = Munin::Node::Utils::set_difference(\@services, \@multigraph_services)
            unless $session->{server_capabilities}{multigraph};
        @services = Munin::Node::Utils::set_difference(\@services, \@dirtyconfig_services)
            unless $session->{server_capabilities}{dirtyconfig};

        _net_write($session, join(" ", @services));
    }
    _net_write($session, "\n");
}


sub _run_service
{
    my ($service, $command) = @_;

    return '# Unknown service' unless $services{$service};

    # temporarily ignore SIGCHLD.  this stops Net::Server from reaping the
    # dead service before we get the chance to check the return value.
    local $SIG{CHLD};
    my $res = $services->fork_service($service, $command);

    if ($res->{timed_out}) {
        ERROR("Service '$service' timed out.");
        return '# Timed out';
    }

    if (my @errors = grep !/^# /, @{$res->{stderr}}) {
        ERROR(qq{Error output from $service:});
        ERROR("\t$_") foreach @errors;
    }

    if ($res->{retval}) {
        my $plugin_exit   = $res->{retval} >> 8;
        my $plugin_signal = $res->{retval} & 127;

        ERROR(qq{Service '$service' exited with status $plugin_exit/$plugin_signal.});
        return '# Bad exit';
    }

    return (@{$res->{stdout}});
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
    DEBUG('DEBUG: < ' . (defined $_ ? $_ : 'undef')) if $config->{DEBUG};
    return $_;
}


sub _net_write {
    my ($session, $text) = @_;
    DEBUG("DEBUG: > $text") if $config->{DEBUG};
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

=back

=cut
