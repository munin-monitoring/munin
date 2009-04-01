package Munin::Node::Server;
use base qw(Net::Server::Fork);

use strict;
use warnings;

use English qw(-no_match_vars);
use Munin::Node::Config;
use Munin::Common::Defaults;
use Munin::Node::Logger;
use Munin::Node::OS;
use Munin::Node::Service;
use Munin::Node::Session;

my $tls;
my %tls_verified = ( 
    "level"          => 0,
    "cert"           => "",
    "verified"       => 0,
    "required_depth" => 5,
    "verify"         => "no"
);

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
    $session->{tls_mode}     = _get_var('tls') || 'auto';
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
    _net_write("# )\n");

}


sub _process_starttls_command {
    my ($session) = @_;

    my $mode = $session->{tls_mode};

    my $key;
    my $cert;
    my $depth;
    my $ca_cert;
    my $tls_verify;

    $key = $cert = &_get_var ("tls_pem");
    $key = &_get_var ("tls_private_key") unless defined $key;
    $key = "$Munin::Common::Defaults::MUNIN_CONFDIR/munin-node.pem" unless defined $key;

    $cert = &_get_var ("tls_certificate") unless defined $cert;
    $cert = "$Munin::Common::Defaults::MUNIN_CONFDIR/munin-node.pem" unless defined $cert;

    $ca_cert = &_get_var("tls_ca_certificate");
    $ca_cert = "$Munin::Common::Defaults::MUNIN_CONFDIR/cacert.pem" unless defined $ca_cert;

    $depth = &_get_var ('tls_verify_depth');
    $depth = 5 unless defined $depth;

    $tls_verify = &_get_var ('tls_verify_certificate');
    $tls_verify = "no" unless defined $tls_verify;

    if (_start_tls($mode, $cert, $key, $ca_cert, $tls_verify, $depth)) {
        return 1;
    }
    else {
        if ($mode eq "paranoid" or $mode eq "enabled") {
            die "ERROR: Could not establish TLS connection. Closing.";
        }
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
    my $node = _get_var($service, 'host_name') || $config->{fqdn};
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
    my ($session, $service) = @_;
    my $host   = $session->{peer_address};
    my $rights = _get_var($service, 'allow_deny');
    
    return 1 unless @{$rights};

    print STDERR "DEBUG: Checking access: $host;$service;\n" if $config->{DEBUG};
    for my $ruleset (@{$rights}) {
        for my $rule (@{$ruleset}) {
            logger ("DEBUG: Checking access: $host;$service;"
                        . $rule->[0].";".$rule->[1])
                if $config->{DEBUG};

            # tls
            if ($rule->[1] eq "tls" and $tls_verified{"verified"}) { 
                return $rule->[0] eq "allow" ? 1 : 0;
            }
            
            # regex
            elsif ($host =~ m($rule->[1])) {
                return $rule->[0] eq "allow" ? 1 : 0;
            }
        }
    }
    return 1;
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

    my $timeout = _get_var ($service, 'timeout');
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

    _set_service_environment($sconf{$service}{env});
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


sub _set_service_environment {
    my ($env) = @_;
    return unless defined $env;
    while (my ($k, $v) = each %$env) {
        $ENV{$k} = $v;
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

sub _net_read 
{
    if (defined $tls)
    {
	eval { $_ = Net::SSLeay::read($tls); };
	my $err = &Net::SSLeay::print_errs("");
	if (defined $err and length $err)
	{
	    logger ("TLS Warning in _net_read: $err");
	}
	if($_ eq '') { undef $_; } #returning '' signals EOF
    }
    else
    {
	$_ = <STDIN>;
    }
    logger ("DEBUG: < $_") if $config->{DEBUG};
    return $_;
}


sub _net_write 
{
    my $text = shift;
    logger ("DEBUG: > $text") if $config->{DEBUG};
    if (defined $tls)
    {
	eval { Net::SSLeay::write ($tls, $text); };
	my $err = &Net::SSLeay::print_errs("");
	if (defined $err and length $err)
	{
	    logger ("TLS Warning in _net_write: $err");
	}
    }
    else
    {
	print STDOUT $text;
    }
}


sub _tls_verify_callback 
{
    my ($ok, $subj_cert, $issuer_cert, $depth, 
	    $errorcode, $arg, $chain) = @_;
#    logger ("ok is ${ok}");

    $tls_verified{"level"}++;

    if ($ok)
    {
        $tls_verified{"verified"} = 1;
        logger ("TLS Notice: Verified certificate.") if $config->{DEBUG};
        return 1; # accept
    }

    if(!($tls_verified{"verify"} eq "yes"))
    {
        logger ("TLS Notice: Certificate failed verification, but we aren't verifying.") if $config->{DEBUG};
	$tls_verified{"verified"} = 1;
        return 1;
    }

    if ($tls_verified{"level"} > $tls_verified{"required_depth"})
    {
        logger ("TLS Notice: Certificate verification failed at depth ".$tls_verified{"level"}.".");
        $tls_verified{"verified"} = 0;
        return 0;
    }

    return 0; # Verification failed
}


sub _start_tls 
{
    my $tls_paranoia = shift;
    my $tls_cert     = shift;
    my $tls_priv     = shift;
    my $tls_ca_cert  = shift;
    my $tls_verify   = shift;
    my $tls_vdepth   = shift;

    my $err;
    my $ctx;
    my $local_key = 0;

    %tls_verified = ( "level" => 0, "cert" => "", "verified" => 0, "required_depth" => $tls_vdepth, "verify" => $tls_verify );

    if ($tls_paranoia eq "disabled")
    {
	logger ("TLS Notice: Refusing TLS request from peer.");
	_net_write ("TLS NOT AVAILABLE\n");
	return 0
    }

    logger("Enabling TLS.") if $config->{DEBUG};
    eval {
        require Net::SSLeay;
    };

    if ($EVAL_ERROR) {
	if ($tls_paranoia eq "auto")
	{
	    logger ("Notice: TLS requested by peer, but Net::SSLeay unavailable.");
	    return 0;
	}
	else # tls really required
	{
	    logger ("Fatal: TLS enabled but Net::SSLeay unavailable.");
	    exit 0;
	}
    }

    # Init SSLeay
    Net::SSLeay::load_error_strings();
    Net::SSLeay::SSLeay_add_ssl_algorithms();
    Net::SSLeay::randomize();
    $ctx = Net::SSLeay::CTX_new();
    if (!$ctx)
    {
	logger ("TLS Error: Could not create SSL_CTX: " . &Net::SSLeay::print_errs(""));
	return 0;
    }

    # Tune a few things...
    if (Net::SSLeay::CTX_set_options($ctx, &Net::SSLeay::OP_ALL))
    {
	logger ("TLS Error: Could not set SSL_CTX options: " . &Net::SSLeay::print_errs(""));
	return 0;
    }

    # Should we use a private key?
    if (-e $tls_priv or $tls_paranoia eq "paranoid")
    {
        if (defined $tls_priv and length $tls_priv)
        {
	    if (!Net::SSLeay::CTX_use_PrivateKey_file($ctx, $tls_priv, 
		    &Net::SSLeay::FILETYPE_PEM))
	    {
	        logger ("TLS Notice: Problem occured when trying to read file with private key \"$tls_priv\": ".&Net::SSLeay::print_errs("").". Continuing without private key.");
	    }
	    else
	    {
	        $local_key = 1;
	    }
        }
    }
    else
    {
	logger ("TLS Notice: No key file \"$tls_priv\". Continuing without private key.");
    }

    # How about a certificate?
    if (-e $tls_cert)
    {
        if (defined $tls_cert and length $tls_cert)
        {
	    if (!Net::SSLeay::CTX_use_certificate_file($ctx, $tls_cert, 
		    &Net::SSLeay::FILETYPE_PEM))
	    {
	        logger ("TLS Notice: Problem occured when trying to read file with certificate \"$tls_cert\": ".&Net::SSLeay::print_errs("").". Continuing without certificate.");
	    }
	}
    }
    else
    {
	logger ("TLS Notice: No certificate file \"$tls_cert\". Continuing without certificate.");
    }

    # How about a CA certificate?
    if (-e $tls_ca_cert)
    {
        if(!Net::SSLeay::CTX_load_verify_locations($ctx, $tls_ca_cert, ''))
        {
            logger ("TLS Notice: Problem occured when trying to read file with the CA's certificate \"$tls_ca_cert\": ".&Net::SSLeay::print_errs("").". Continuing without CA's certificate.");
        }
    }

    # Tell the other side that we're able to talk TLS
    if ($local_key)
    {
        print "TLS OK\n";
    }
    else
    {
        print "TLS MAYBE\n";
    }

    # Now let's define our requirements of the node
    $tls_vdepth = 5 unless defined $tls_vdepth;
    Net::SSLeay::CTX_set_verify_depth ($ctx, $tls_vdepth);
    $err = &Net::SSLeay::print_errs("");
    if (defined $err and length $err)
    {
	logger ("TLS Warning in set_verify_depth: $err");
    }
    Net::SSLeay::CTX_set_verify ($ctx, &Net::SSLeay::VERIFY_PEER, \&_tls_verify_callback);
    $err = &Net::SSLeay::print_errs("");
    if (defined $err and length $err)
    {
	logger ("TLS Warning in set_verify: $err");
    }

    # Create the local tls object
    if (! ($tls = Net::SSLeay::new($ctx)))
    {
	logger ("TLS Error: Could not create TLS: " . &Net::SSLeay::print_errs(""));
	return 0;
    }
    if ($config->{DEBUG})
    {
	my $i = 0;
	my $p = '';
	my $cipher_list = 'Cipher list: ';
	$p=Net::SSLeay::get_cipher_list($tls,$i);
	$cipher_list .= $p if $p;
	do {
	    $i++;
	    $cipher_list .= ', ' . $p if $p;
	    $p=Net::SSLeay::get_cipher_list($tls,$i);
	} while $p;
        $cipher_list .= '\n';
	logger ("TLS Notice: Available cipher list: $cipher_list.");
    }

    # Redirect stdout/stdin to the TLS
    Net::SSLeay::set_rfd($tls, fileno(STDIN));
    $err = &Net::SSLeay::print_errs("");
    if (defined $err and length $err)
    {
	logger ("TLS Warning in set_rfd: $err");
    }
    Net::SSLeay::set_wfd($tls, fileno(STDOUT));
    $err = &Net::SSLeay::print_errs("");
    if (defined $err and length $err)
    {
	logger ("TLS Warning in set_wfd: $err");
    }

    # Try to negotiate the tls connection
    my $res;
    if ($local_key)
    {
        $res = Net::SSLeay::accept($tls);
    }
    else
    {
        $res = Net::SSLeay::connect($tls);
    }
    $err = &Net::SSLeay::print_errs("");
    if (defined $err and length $err)
    {
	logger ("TLS Error: Could not enable TLS: " . $err);
	Net::SSLeay::free ($tls);
	Net::SSLeay::CTX_free ($ctx);
	$tls = undef;
    }
    elsif (!$tls_verified{"verified"} and $tls_paranoia eq "paranoid")
    {
	logger ("TLS Error: Could not verify CA: " . Net::SSLeay::dump_peer_certificate($tls));
	Net::SSLeay::free ($tls);
	Net::SSLeay::CTX_free ($ctx);
	$tls = undef;
    }
    else
    {
	logger ("TLS Notice: TLS enabled.");
	logger ("TLS Notice: Cipher `" . Net::SSLeay::get_cipher($tls) . "'.");
	$tls_verified{"cert"} = Net::SSLeay::dump_peer_certificate($tls);
	logger ("TLS Notice: client cert: " .$tls_verified{"cert"});
    }

    return $tls;
}


sub _get_var {
    my ($name, $var) = @_;

    my $sconf = $config->{sconf};

    return unless defined $name;

    return $sconf->{$name} unless defined $var;

    return $sconf->{$name}{$var} if exists $sconf->{$name};

    return;
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
