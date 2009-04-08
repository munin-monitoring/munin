package Munin::Node::Server;
use base qw(Net::Server::Fork);

use strict;
use warnings;

use English qw(-no_match_vars);
use Munin::Node::Config;
use Munin::Common::Defaults;
use Munin::Common::TLSServer;
use Munin::Node::Logger;
use Munin::Node::OS;
use Munin::Node::Service;
use Munin::Node::Session;

my $tls;

# A set of all services that this node can run.
my %services;

# Which hosts this node's services applies to. Typically this is the
# same as the host the node is running on, but some services queries
# other hosts (e.g SMTP services).
my %nodes;


my $config = Munin::Node::Config->instance();


sub pre_loop_hook {
    my $self = shift;
    print STDERR "In pre_loop_hook.\n" if $config->{DEBUG};
    _load_services();
    $self->SUPER::pre_loop_hook();
}


sub process_request {
    my $self = shift;

    my $session = Munin::Node::Session->new();

    $session->{tls_started}  = 0;
    $session->{tls_mode}     = $config->{tls} || 'auto';
    $session->{peer_address} = $self->{server}->{peeraddr};

    $PROGRAM_NAME .= " [$session->{peer_address}]";

    _net_write ("# munin node at $config->{fqdn}\n");

    local $SIG{ALRM} = sub {
        logger ("Connection timed out."); 
        die "timeout"
    };

    alarm($config->{sconf}{'timeout'});
    while (defined (my $line = _net_read())) {
        chomp $line;
        _process_command_line($session, $line) 
            or last;
    }
}


sub _process_command_line {
    my ($session, $cmd_line) = @_;

    alarm($config->{sconf}{'timeout'});

    local $_ = $cmd_line;

    if (_expect_starttls($session)) {
        if (!(/^starttls\s*$/i)) {
            logger ("ERROR: Client did not request TLS. Closing.");
            _net_write ("# I require TLS. Closing.\n");
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
    } elsif (/^fetch\s?(\S*)/i) {
        _print_service(_run_service($session, $1)) 
    } elsif (/^config\s?(\S*)/i) {
        _print_service(_run_service($session, $1, "config"));
    } elsif (/^starttls\s*$/i) {
        eval {
            $session->{tls_started} = _process_starttls_command($session);
        };
        if ($EVAL_ERROR) {
            logger($EVAL_ERROR);
            return 0;
        }
        logger ("DEBUG: Returned from starttls.") if $config->{DEBUG};
    } else {
        _net_write ("# Unknown command. Try cap, list, nodes, config, fetch, version or quit\n");
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

    _net_write(sprintf("# Node capabilities: (%s). Session capabilities: (\n", 
                       join(' ', keys %node_cap)));
    _net_write(join(' ', keys %session_capabilities) . "\n");
    _net_write("# )\n.\n");

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

    $tls = Munin::Common::TLSServer->new({
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

    if ($tls->start_tls()) {
        return 1;
    }
    else {
        if ($mode eq "paranoid" or $mode eq "enabled") {
            die "ERROR: Could not establish TLS connection. Closing.";
        }
        $tls = undef;
        return 0;
    }
}


sub _show_version {
  print "munins node on $config->{fqdn} version: $Munin::Common::Defaults::MUNIN_VERSION\n"
}


sub _show_nodes {
  for my $node (keys %nodes) {
    _net_write ("$node\n");
  }
  _net_write (".\n");
}


sub _load_services {
    $config->process_plugin_configuration_files();
    $config->apply_wildcards();

    opendir (my $DIR, $config->{servicedir}) 
        || die "Cannot open plugindir: $config->{servicedir} $!";

    for my $file (readdir($DIR)) {
        next unless Munin::Node::Service->is_a_runnable_service($file);
	print "file: '$file'\n" if $config->{DEBUG};
        _add_to_services_and_nodes($file);
    }

    closedir $DIR;
}


sub _add_to_services_and_nodes {
    my ($service) = @_;

    $services{$service} = 1;
    my $node = $config->{sconf}{$service}{host_name} || $config->{fqdn};
    $nodes{$node}{$service} = 1;
}


sub _print_service {
  my (@lines) = @_;
  for my $line (@lines) {
    _net_write ("$line\n");
  }
  _net_write (".\n");
}


sub _list_services {
    my ($session, $node) = @_;
    $node ||= $config->{fqdn};
    _net_write( join( " ",
		     grep( { &_has_access ($session, $_); } keys %{$nodes{$node}} )
		     ) )
      if exists $nodes{$node};
    #print join " ", keys %{$nodes{$node}};
    _net_write ("\n");
}


sub _has_access {
    my ($session) = @_;
    my $host   = $session->{peer_address};
    my $ruleset = $config->{allow_deny} || [];

    return 1 unless @{$ruleset};

    for my $rule (@{$ruleset}) {
        logger(sprintf("DEBUG: Checking access: %s: %s;%s", 
                       $host, $rule->[0], $rule->[1]))
            if $config->{DEBUG};
        
        if ($host =~ m($rule->[1])) {
            return $rule->[0] eq "allow" ? 1 : 0;
        }
    }

    # No rules matched. Return true if in deny mode, else false.
    return $ruleset->[0][0] eq 'deny';
}


sub _run_service {
    my ($session, $service, $command, $autoreap) = @_;

    $command ||= "";

    unless ($services{$service} 
                && ($session->{peer_address} eq '' || _has_access($session, $service))) {
        _net_write("# Unknown service");
        return ();
    }

    my $child_pid = open my $CHILD, '-|';

    unless (defined $child_pid) {
	logger("Unable to fork.");
        return ();
    }

    my @lines;
    if ($child_pid) {
        @lines = _read_service_result($CHILD, $service, $command, $child_pid);
    }
    else {
        # In child, should never return ...
        _exec_service($service, $command);
         # Should never get here ... putting an exit guard here just
         # in case ...
        exit 42;
    }

    unless (close $CHILD) {
        if ($!) {
            # If Net::Server::Fork is currently taking care of reaping,
            # we get false errors. Filter them out.
            unless (defined $autoreap && $autoreap)  {
                logger("Error while executing plugin \"$service\": $!");
            }
        }
        else {
            logger("Plugin \"$service\" exited with status $CHILD_ERROR. --@lines--");
        }
    }

    wait;
    alarm 0;

    chomp @lines;
    return (@lines);
}


sub _read_service_result {
    my ($CHILD, $service, $command, $child_pid) = @_;

    my $timeout = $config->{sconf}{$service}{timeout};
    $timeout = $config->{sconf}{'timeout'} 
    	unless defined $timeout and $timeout =~ /^\d+$/;

    my @lines = ();

    eval {
        local $SIG{ALRM} = sub { die "Timed out: $!" };
        alarm($timeout);
        while (my $line = <$CHILD>) {
	    push @lines, $line;
        }
    };
    if ($EVAL_ERROR) {
        if ($EVAL_ERROR =~ /^Timed out/) {
            my $msg = "Plugin timeout: $service $command: $@ (pid $child_pid) - killing...";
            _net_write($msg); 
            logger($msg);
            Munin::Node::OS->reap_child_group($child_pid);
            _net_write("# done \n"); 
        }
        else {
            die $EVAL_ERROR;
        }
    }

    return @lines;
}


sub _exec_service {
    my ($service, $command) = @_;

    my %sconf = %{$config->{sconf}};

    POSIX::setsid();

    _change_real_and_effective_user_and_group($service);

    unless (Munin::Node::OS->check_perms("$config->{servicedir}/$service")) {
        logger ("Error: unsafe permissions. Bailing out.");
        exit 2;
    }

    Munin::Node::Service->export_service_environment($service);
    if (exists $sconf{$service}{'command'} && defined $sconf{$service}{'command'}) {
        my @run = ();
        for my $t (@{$sconf{$service}{'command'}}) {
            if ($t =~ /^%c$/) {
                push (@run, "$config->{servicedir}/$service", $command);
            } else {
                push (@run, $t);
            }
        }
        print STDERR "# About to run \"", join (' ', @run), "\"\n" if $config->{DEBUG};
        exec (@run) if @run;
    } else {
        exec "$config->{servicedir}/$service", $command;
    }
}


sub _change_real_and_effective_user_and_group {
    my ($service) = @_;

    my $root_uid = 0;
    my $root_gid = 0;

    if ($REAL_USER_ID == $root_uid) {
        # Need to test for defined here since a user might be
        # spesified with UID = 0
        my $u  = defined $config->{sconf}{$service}{'user'} 
            ? $config->{sconf}{$service}{'user'}
                : $config->{defuser};
        my $g  = $config->{defgroup};
        my $gs = "$g $g" .      # FIX why $g two times?
            ($config->{sconf}{$service}{'group'} 
                 ? " $config->{sconf}{$service}{group}" 
                     : "");

        eval {
            if ($Munin::Common::Defaults::MUNIN_HASSETR) {
                Munin::Node::OS->set_real_group_id($g) 
                      unless $g == $root_gid;
                Munin::Node::OS->set_real_user_id($u)
                      unless $u == $root_uid;
            }
    
            Munin::Node::OS->set_effective_group_id($gs) 
                  unless $g == $root_gid;
            Munin::Node::OS->set_effective_user_id($u)
                  unless $u == $root_uid;
        };
        if ($EVAL_ERROR) {
            logger("Plugin \"$service\" Can't drop privileges: $EVAL_ERROR. "
                       . "Bailing out.\n");
            exit 1;
        }
    }
}

sub _net_read {
    local $_;

    if ($tls && $tls->session_started()) {
        $_ = $tls->read();
    }
    else {
	$_ = <STDIN>;
    }
    logger("DEBUG: < $_") if $config->{DEBUG};
    return $_;
}


sub _net_write {
    my $text = shift;
    logger("DEBUG: > $text") if $config->{DEBUG};
    if ($tls && $tls->session_started()) {
        $tls->write($text);
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
