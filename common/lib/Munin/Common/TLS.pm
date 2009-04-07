package Munin::Common::TLS;

use warnings;
use strict;

use Carp;
use English qw(-no_match_vars);

sub new {
    my ($class, $read_fd, $write_fd, $read_func, $write_func, $logger, $debug) = @_;

    my $self = {
        tls          => undef,
        tls_verified => undef,
        read_fd      => $read_fd,
        write_fd     => $write_fd,
        read_func    => $read_func,
        write_func   => $write_func,
        logger       => $logger,
        DEBUG        => $debug || 0,
    };

    return bless $self, $class;
}


sub start_tls_client {
    my $self = shift;

    my $tls_paranoia = shift;
    my $tls_cert     = shift;
    my $tls_priv     = shift;
    my $tls_ca_cert  = shift;
    my $tls_verify   = shift;
    my $tls_vdepth   = shift;

    my $remote_key = 0;

    $self->_start_tls(
        $tls_paranoia,
        $tls_cert,
        $tls_priv,
        $tls_ca_cert,
        $tls_verify,
        $tls_vdepth,
        sub {
            # Tell the node that we want TLS
            $self->{write_func}("STARTTLS\n");
            my $tlsresponse = $self->{read_func}();
            if (!defined $tlsresponse) {
                $self->{logger}("[ERROR] Bad TLS response \"\".");
                return 0
            }
            if ($tlsresponse =~ /^TLS OK/) {
                $remote_key = 1;
            }
            elsif ($tlsresponse !~ /^TLS MAYBE/i) {
                $self->{logger}("[ERROR] Bad TLS response \"$tlsresponse\".");
                return 0;
            }
        },
        sub {
            my ($has_key) = @_;
            return !$remote_key;
        },
        sub {
           # $self->{read_func}(); # Get rid of empty line
            
        },
    );
}


sub start_tls_server {
    my $self         = shift;
    my $tls_paranoia = shift;
    my $tls_cert     = shift;
    my $tls_priv     = shift;
    my $tls_ca_cert  = shift;
    my $tls_verify   = shift;
    my $tls_vdepth   = shift;


    $self->_start_tls(
        $tls_paranoia,
        $tls_cert,
        $tls_priv,
        $tls_ca_cert,
        $tls_verify,
        $tls_vdepth,
        sub {
            my ($has_key) = @_;
            if ($has_key) {
                $self->{write_func}("TLS OK\n");
            }
            else {
                $self->{write_func}("TLS MAYBE\n");
            }
            
            return 1;
        },
        sub {
            my ($has_key) = @_;
            return $has_key;
        },
        sub {},
    );
}

sub _tls_verify_callback {
    my ($self) = @_;

    my %tls_verified = %{$self->{tls_verified}};
    
    return sub {
        my ($ok, $subj_cert, $issuer_cert, $depth, 
	    $errorcode, $arg, $chain) = @_;
        #    $self->{logger}("ok is ${ok}");

        $tls_verified{"level"}++;

        if ($ok) {
            $tls_verified{"verified"} = 1;
            $self->{logger}("[TLS] Verified certificate.") if $self->{DEBUG};
            return 1;           # accept
        }
        
        if (!($tls_verified{"verify"} eq "yes")) {
            $self->{logger}("[TLS] Certificate failed verification, but we aren't verifying.") if $self->{DEBUG};
            $tls_verified{"verified"} = 1;
            return 1;
        }

        if ($tls_verified{"level"} > $tls_verified{"required_depth"}) {
            $self->{logger}("[TLS] Certificate verification failed at depth ".$tls_verified{"level"}.".");
            $tls_verified{"verified"} = 0;
            return 0;
        }

        return 0;               # Verification failed
    }
}

sub _start_tls {
    my $self = shift;

    my $tls_paranoia = shift || 0;
    my $tls_cert     = shift || '';
    my $tls_priv     = shift || '';
    my $tls_ca_cert  = shift || '';
    my $tls_verify   = shift || 0;
    my $tls_vdepth   = shift || 0; 

    my $communicate        = shift;
    my $use_key_if_present = shift;
    my $finalize           = shift;

    my $ctx;
    my $err;
    my $has_key = 0;

    $self->{tls_verified} = { "level" => 0, "cert" => "", "verified" => 0, "required_depth" => $tls_vdepth, "verify" => $tls_verify};

    $self->{logger}("[TLS] Enabling TLS.") if $self->{DEBUG};
    eval {
        require Net::SSLeay;
    };
    if ($@) {
	$self->{logger}("[ERROR] TLS enabled but Net::SSLeay unavailable.");
	return 0;
    }

    # Init SSLeay
    Net::SSLeay::load_error_strings();
    Net::SSLeay::SSLeay_add_ssl_algorithms();
    Net::SSLeay::randomize();
    $ctx = Net::SSLeay::CTX_new();
    if (!$ctx)
    {
	$self->{logger}("[ERROR] Could not create SSL_CTX");
	return 0;
    }

    # Tune a few things...
    if (Net::SSLeay::CTX_set_options($ctx, &Net::SSLeay::OP_ALL))
    {
	$self->{logger}("[ERROR] Could not set SSL_CTX options");
	return 0;
    }

    # Should we use a private key?
    if (defined $tls_priv and length $tls_priv)
    {
    	if (-e $tls_priv or $tls_paranoia eq "paranoid")
	{
	    if (Net::SSLeay::CTX_use_PrivateKey_file($ctx, $tls_priv, 
                                                     &Net::SSLeay::FILETYPE_PEM))
	    {
                $has_key = 1;
            }
            else {
	        if ($tls_paranoia eq "paranoid") 
	        {
	    	    $self->{logger}("[ERROR] Problem occured when trying to read file with private key \"$tls_priv\": $!");
		    return 0;
	        }
	        else
	        {
	    	    $self->{logger}("[ERROR] Problem occured when trying to read file with private key \"$tls_priv\": $!. Continuing without private key.");
	        }
	    }
	}
	else
	{
	    $self->{logger}("[WARNING] No key file \"$tls_priv\". Continuing without private key.");
        }
    }

    # How about a certificate?
    if ($tls_cert && -e $tls_cert)
    {
        if (defined $tls_cert and length $tls_cert)
        {
	    if (!Net::SSLeay::CTX_use_certificate_file($ctx, $tls_cert, 
		    &Net::SSLeay::FILETYPE_PEM))
	    {
	        $self->{logger}("[WARNING] Problem occured when trying to read file with certificate \"$tls_cert\": $!. Continuing without certificate.");
	    }
        }
    }
    else
    {
	$self->{logger}("[WARNING] No certificate file \"$tls_cert\". Continuing without certificate.");
    }

    # How about a CA certificate?
    if ($tls_ca_cert && -e $tls_ca_cert)
    {
    	if(!Net::SSLeay::CTX_load_verify_locations($ctx, $tls_ca_cert, ''))
    	{
    	    $self->{logger}("[WARNING] Problem occured when trying to read file with the CA's certificate \"$tls_ca_cert\": ".&Net::SSLeay::print_errs("").". Continuing without CA's certificate.");
   	 }
    }


    my $status = $communicate->($has_key);
    return 0 if $status == 0;
    
    # Now let's define our requirements of the node
    $tls_vdepth = 5 if !defined $tls_vdepth;
    Net::SSLeay::CTX_set_verify_depth ($ctx, $tls_vdepth);
    $err = &Net::SSLeay::print_errs("");
    if (defined $err and length $err)
    {
	$self->{logger}("[WARNING] in set_verify_depth: $err");
    }
    Net::SSLeay::CTX_set_verify ($ctx, &Net::SSLeay::VERIFY_PEER, $self->_tls_verify_callback());
    $err = &Net::SSLeay::print_errs("");
    if (defined $err and length $err)
    {
	$self->{logger}("[WARNING] in set_verify: $err");
    }

    # Create the local tls object
    if (! ($self->{tls} = Net::SSLeay::new($ctx)))
    {
	$self->{logger}("[ERROR] Could not create TLS: $!");
	return 0;
    }
    if ($self->{DEBUG})
    {
	my $i = 0;
	my $p = '';
	my $cipher_list = 'Cipher list: ';
	$p=Net::SSLeay::get_cipher_list($self->{tls},$i);
	$cipher_list .= $p if $p;
	do {
	    $i++;
	    $cipher_list .= ', ' . $p if $p;
	    $p=Net::SSLeay::get_cipher_list($self->{tls},$i);
	} while $p;
        $cipher_list .= '\n';
	$self->{logger}("[TLS] Available cipher list: $cipher_list.");
    }


    Net::SSLeay::set_rfd($self->{tls}, $self->{read_fd});
    $err = &Net::SSLeay::print_errs("");
    if (defined $err and length $err) {
        $self->{logger}("TLS Warning in set_rfd: $err");
    }
    Net::SSLeay::set_wfd($self->{tls}, $self->{write_fd});
    $err = &Net::SSLeay::print_errs("");
    if (defined $err and length $err) {
        $self->{logger}("TLS Warning in set_wfd: $err");
    }

    $self->{logger}("Accept/Connect: $has_key, " . $use_key_if_present->($has_key)) if $self->{DEBUG};
    my $res;
    if ($use_key_if_present->($has_key)) {
        $res = Net::SSLeay::accept($self->{tls});
    }
    else {
        $res = Net::SSLeay::connect($self->{tls});
    }
    $self->{logger}("Done Accept/Connect") if $self->{DEBUG};

    $err = &Net::SSLeay::print_errs("");
    if (defined $err and length $err)
    {
	$self->{logger}("[ERROR] Could not enable TLS: " . $err);
	Net::SSLeay::free ($self->{tls});
	Net::SSLeay::CTX_free ($ctx);
	$self->{tls} = undef;
    }
    elsif (!$self->{tls_verified}{"verified"} and $tls_paranoia eq "paranoid")
    {
	$self->{logger}("[ERROR] Could not verify CA: " . Net::SSLeay::dump_peer_certificate($self->{tls}));
	write_socket_single ($self->{tls}, "quit\n");
	Net::SSLeay::free ($self->{tls});
	Net::SSLeay::CTX_free ($ctx);
	$self->{tls} = undef;
    }
    else
    {
	$self->{logger}("[TLS] TLS enabled.");
	$self->{logger}("[TLS] Cipher `" . Net::SSLeay::get_cipher($self->{tls}) . "'.");
	$self->{logger}("[TLS] client cert: " . Net::SSLeay::dump_peer_certificate($self->{tls}));
    }

    $finalize->();

    return $self->{tls};
}


sub read {
    my ($self, $tls_session) = @_;

    local $_;

    eval { $_ = Net::SSLeay::read($tls_session); };
    my $err = &Net::SSLeay::print_errs("");
    if (defined $err and length $err) {
        $self->{logger}("TLS Warning in read: $err");
        return;
    }
    if($_ eq '') { undef $_; } #returning '' signals EOF

    $self->{logger}("DEBUG: < $_") if $self->{DEBUG};

    return $_;
}


sub write {
    my ($self, $tls_session, $text) = @_;

    $self->{logger}("DEBUG: > $text") if $self->{DEBUG};

    eval { Net::SSLeay::write($tls_session, $text); };
    my $err = &Net::SSLeay::print_errs("");
    if (defined $err and length $err) {
        $self->{logger}("TLS Warning in write: $err");
    }
}



1;

=head1 NAME

Munin::Node::TLS - Implements the STARTTLS protocol


=head1 SYNOPSIS

FIX


=head1 METHODS

=over

=item B<new>

FIX

=item B<start_tls_client>

FIX

=item B<start_tls_server>

FIX

=item B<read>

FIX

=item B<write>

FIX

=back
