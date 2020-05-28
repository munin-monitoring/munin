package Munin::Common::TLS;

use warnings;
use strict;

use Carp;
use English qw(-no_match_vars);

sub new {
    my ($class, $args) = @_;

    my $self = {
        logger             => $args->{logger},
        read_fd            => $args->{read_fd},
        read_func          => $args->{read_func},
        write_fd           => $args->{write_fd},
        write_func         => $args->{write_func},
    };

    for my $key (keys %$self) {
        croak "Required argument missing: $key" unless defined $self->{$key};
    }

    $self = {
        %$self,
        DEBUG              => $args->{DEBUG} || 0,
        tls_ca_cert        => $args->{tls_ca_cert} || '',
        tls_cert           => $args->{tls_cert} || '',
        tls_paranoia       => $args->{tls_paranoia}|| 0,
        tls_priv           => $args->{tls_priv} || '',
        tls_vdepth         => $args->{tls_vdepth} || 0,
        tls_verify         => $args->{tls_verify} || 0,
        tls_match          => $args->{tls_match} || '',
    };

    for my $args_key (keys %$args) {
        croak "Unrecognized argument: $args_key" unless exists $self->{$args_key};
    }

    $self = {
        %$self,
        tls_context        => undef,
        tls_session        => undef,
        private_key_loaded => 0,
    };

    return bless $self, $class;
}


sub _start_tls {
    my $self = shift;

    my %tls_verified = (
        level          => 0, 
        cert           => "",
        verified       => 0, 
        required_depth => $self->{tls_vdepth}, 
        verify         => $self->{tls_verify},
    );

    $self->{logger}("[TLS] Enabling TLS.") if $self->{DEBUG};
    
    $self->_load_net_ssleay()
        or return 0;

    $self->_initialize_net_ssleay();

    $self->{tls_context} = $self->_creat_tls_context();

    $self->_load_private_key()
        or return 0;
    
    $self->_load_certificate();

    $self->_load_ca_certificate();
    
    $self->_initial_communication()
        or return 0;
    
    $self->_set_peer_requirements(\%tls_verified);
    
    if (! ($self->{tls_session} = Net::SSLeay::new($self->{tls_context})))
    {
	$self->{logger}("[ERROR] Could not create TLS: $!");
	return 0;
    }

    $self->_log_cipher_list() if $self->{DEBUG};

    $self->_set_ssleay_file_descriptors();

    $self->_accept_or_connect(\%tls_verified);

    return $self->{tls_session};
}


sub _load_net_ssleay {
    my ($self) = @_;

    eval {
        require Net::SSLeay;
    };
    if ($@) {
	$self->{logger}("[ERROR] TLS enabled but Net::SSLeay unavailable.");
	return 0;
    }

    return 1;
}


sub _initialize_net_ssleay {
    my ($self) = @_;

    Net::SSLeay::load_error_strings();
    Net::SSLeay::SSLeay_add_ssl_algorithms();
    Net::SSLeay::randomize();
}


sub _creat_tls_context {
    my ($self) = @_;

    my $ctx = Net::SSLeay::CTX_new();
    if (!$ctx) {
	$self->{logger}("[ERROR] Could not create SSL_CTX");
	return 0;
    }

    # Tune a few things...
    Net::SSLeay::CTX_set_options($ctx, Net::SSLeay::OP_ALL());
    if (my $errno = Net::SSLeay::ERR_get_error()) {
	$self->{logger}("[ERROR] Could not set SSL_CTX options: " + Net::SSLeay::ERR_error_string($errno));
	return 0;
    }

    return $ctx;
}


sub _load_private_key {
    my ($self) = @_;

    if (defined $self->{tls_priv} and length $self->{tls_priv}) {
    	if (-e $self->{tls_priv} or $self->{tls_paranoia} eq "paranoid") {
	    if (Net::SSLeay::CTX_use_PrivateKey_file($self->{tls_context}, 
                                                     $self->{tls_priv}, 
                                                     &Net::SSLeay::FILETYPE_PEM)) {
                $self->{private_key_loaded} = 1;
            }
            else {
	        if ($self->{tls_paranoia} eq "paranoid") {
                    $self->{logger}("[ERROR] Problem occurred when trying to read file with private key \"$self->{tls_priv}\": $!");
		    return 0;
	        }
	        else {
                    $self->{logger}("[ERROR] Problem occurred when trying to read file with private key \"$self->{tls_priv}\": $!. Continuing without private key.");
	        }
	    }
	}
	else {
	    $self->{logger}("[WARNING] No key file \"$self->{tls_priv}\". Continuing without private key.");
        }
    }

    return 1;
}


sub _load_certificate {
    my ($self) = @_;

    if ($self->{tls_cert} && -e $self->{tls_cert}) {
        if (defined $self->{tls_cert} and length $self->{tls_cert}) {
	    if (!Net::SSLeay::CTX_use_certificate_file($self->{tls_context}, 
                                                       $self->{tls_cert}, 
                                                       &Net::SSLeay::FILETYPE_PEM)) {
	        $self->{logger}("[WARNING] Problem occurred when trying to read file with certificate \"$self->{tls_cert}\": $!. Continuing without certificate.");
	    }
        }
    }
    else {
	$self->{logger}("[WARNING] No certificate file \"$self->{tls_cert}\". Continuing without certificate.");
    }

    return 1;
}


sub _load_ca_certificate {
    my ($self) = @_;

    if ($self->{tls_ca_cert} && -e $self->{tls_ca_cert}) {
    	if(!Net::SSLeay::CTX_load_verify_locations($self->{tls_context}, $self->{tls_ca_cert}, '')) {
            $self->{logger}("[WARNING] Problem occurred when trying to read file with the CA's certificate \"$self->{tls_ca_cert}\": ".&Net::SSLeay::print_errs("").". Continuing without CA's certificate.");
   	 }
    }

    return 1;
}


sub _set_peer_requirements {
    my ($self, $tls_verified) = @_;

    $self->{tls_vdepth} = 5 if !defined $self->{tls_vdepth};
    Net::SSLeay::CTX_set_verify_depth ($self->{tls_context}, $self->{tls_vdepth});
    my $err = &Net::SSLeay::print_errs("");
    if (defined $err and length $err) {
        $self->{logger}("[WARNING] in set_verify_depth: $err");
    }
    Net::SSLeay::CTX_set_verify ($self->{tls_context}, 
                                 $self->{tls_verify}  ? &Net::SSLeay::VERIFY_PEER :
                                                        &Net::SSLeay::VERIFY_NONE,
                                 $self->_tls_verify_callback($tls_verified));
    $err = &Net::SSLeay::print_errs("");
    if (defined $err and length $err) {
        $self->{logger}("[WARNING] in set_verify: $err");
    }
    
    return 1;
}


sub _tls_verify_callback {
    my ($self, $tls_verified) = @_;

    return sub {
        my ($ok, $subj_cert, $issuer_cert, $depth, 
	    $errorcode, $arg, $chain) = @_;

        $tls_verified->{"level"}++;

        if ($ok) {
            $tls_verified->{"verified"} = 1;
            $self->{logger}("[TLS] Verified certificate.") if $self->{DEBUG};
            return 1;           # accept
        }
        
        if (!($tls_verified->{"verify"})) {
            $self->{logger}("[TLS] Certificate failed verification, but we aren't verifying.") if $self->{DEBUG};
            $tls_verified->{"verified"} = 1;
            return 1;
        }

        if ($tls_verified->{"level"} > $tls_verified->{"required_depth"}) {
            $self->{logger}("[TLS] Certificate verification failed at depth ".$tls_verified->{"level"}.".");
            $tls_verified->{"verified"} = 0;
            return 0;
        }

        return 0;               # Verification failed
    }
}


sub _log_cipher_list {
    my ($self) = @_;

    my $i = 0;
    my $p = '';
    my $cipher_list = 'Cipher list: ';
    $p=Net::SSLeay::get_cipher_list($self->{tls_session},$i);
    $cipher_list .= $p if $p;
    do {
        $i++;
        $cipher_list .= ', ' . $p if $p;
        $p=Net::SSLeay::get_cipher_list($self->{tls_session},$i);
    } while $p;
    $cipher_list .= '\n';
    $self->{logger}("[TLS] Available cipher list: $cipher_list.") if $self->{DEBUG};
}


sub _set_ssleay_file_descriptors {
    my ($self) = @_;

    Net::SSLeay::set_rfd($self->{tls_session}, $self->{read_fd});
    my $err = &Net::SSLeay::print_errs("");
    if (defined $err and length $err) {
        $self->{logger}("[TLS] Warning in set_rfd: $err");
    }
    Net::SSLeay::set_wfd($self->{tls_session}, $self->{write_fd});
    $err = &Net::SSLeay::print_errs("");
    if (defined $err and length $err) {
        $self->{logger}("[TLS] Warning in set_wfd: $err");
    }
}


sub _accept_or_connect {
    my ($self, $tls_verified) = @_;

    $self->{logger}("[TLS] Accept/Connect: $self->{private_key_loaded}, " . $self->_use_key_if_present()) if $self->{DEBUG};
    my $res;
    if ($self->_use_key_if_present()) {
        $res = Net::SSLeay::accept($self->{tls_session});
    }
    else {
        $res = Net::SSLeay::connect($self->{tls_session});
    }
    $self->{logger}("[TLS] Done Accept/Connect") if $self->{DEBUG};

    my $err = &Net::SSLeay::print_errs("");
    if (defined $err and length $err)
    {
	$self->{logger}("[ERROR] Could not enable TLS: " . $err);
	Net::SSLeay::free ($self->{tls_session});
	Net::SSLeay::CTX_free ($self->{tls_context});
	$self->{tls_session} = undef;
    }
    elsif (!$tls_verified->{"verified"} and $self->{tls_paranoia} eq "paranoid")
    {
	$self->{logger}("[ERROR] Could not verify CA: " . Net::SSLeay::dump_peer_certificate($self->{tls_session}));
	$self->_on_unverified_cert();
	Net::SSLeay::free ($self->{tls_session});
	Net::SSLeay::CTX_free ($self->{tls_context});
	$self->{tls_session} = undef;
    }
    elsif ($self->{"tls_match"} and
    	Net::SSLeay::dump_peer_certificate($self->{tls_session}) !~ /$self->{tls_match}/)
    { 
	$self->{logger}("[ERROR] Could not match pattern \"" . $self->{tls_match} .
		"\" in dump of certificate.");
	$self->_on_unmatched_cert();
	Net::SSLeay::free ($self->{tls_session});
	Net::SSLeay::CTX_free ($self->{tls_context});
	$self->{tls_session} = undef;
    }
    else
    {
	$self->{logger}("[TLS] TLS enabled.") if $self->{DEBUG};
	$self->{logger}("[TLS] Cipher `" . Net::SSLeay::get_cipher($self->{tls_session}) . "'.") if $self->{DEBUG};
	$self->{logger}("[TLS] client cert: " . Net::SSLeay::dump_peer_certificate($self->{tls_session})) if $self->{DEBUG};
    }
}


# Abstract method
sub _initial_communication {
    my ($self) = @_;
    croak "Abstract method called '_initial_communication', "
        . "needs to be defined in child" 
            if ref $self eq __PACKAGE__;
}


# Abstract method
sub _use_key_if_present {
    my ($self) = @_;
    croak "Abstract method called '_use_key_if_present', "
        . "needs to be defined in child" 
            if ref $self eq __PACKAGE__;
}


# Redefine in sub class if needed
sub _on_unverified_cert {}

# Redefine in sub class if needed
sub _on_unmatched_cert {}

sub read {
    my ($self) = @_;

    croak "Tried to do an encrypted read, but a TLS session is not started" 
        unless $self->session_started();

    my $read = Net::SSLeay::read($self->{tls_session});
    my $err = &Net::SSLeay::print_errs("");
    if (defined $err and length $err) {
        $self->{logger}("[TLS] Warning in read: $err");
        return;
    }
    undef $read if($read eq ''); # returning '' signals EOF

    $self->{logger}("DEBUG: < $read") if $self->{DEBUG} && defined $read;
    return $read;
}


sub write {
    my ($self, $text) = @_;

    croak "Tried to do an encrypted write, but a TLS session is not started" 
        unless $self->session_started();

    $self->{logger}("DEBUG: > $text") if $self->{DEBUG};

    Net::SSLeay::write($self->{tls_session}, $text);
    my $err = &Net::SSLeay::print_errs("");
    if (defined $err and length $err) {
        $self->{logger}("[TLS] Warning in write: $err");
        return 0;
    }
    
    return 1;
}


sub session_started {
    my ($self) = @_;

    return defined $self->{tls_session};
}


1;

__END__

=head1 NAME

Munin::Node::TLS - Abstract base class implementing the STARTTLS protocol


=head1 SYNOPSIS

Should not be called directly. See synopsis for
L<Munin::Common::TLSServer> and L<Munin::Common::TLSClient>.


=head1 METHODS

=over

=item B<new>

 my $tls = Munin::Common::TLSFoo->new({ # Substitute Foo with Client or Server
     # Mandatory attributes:  
     logger      => \&a_logger_func,
     read_fd     => fileno($socket),
     read_func   => \&a_socket_read_func,
     write_fd    => fileno($socket),
     write_func  => \&a_socket_read_func,

     # Optional attributes                          DEFAULTS
     DEBUG              => 0,                       # 0
     tls_ca_cert        => "path/to/ca/cert.pem",   # ''
     tls_cert           => "path/to/cert.pem",      # ''
     tls_paranoia       => 1,                       # 0
     tls_priv           => "path/to/priv_key.pem",  # ''
     tls_vdepth         => 5,                       # 0
     tls_verify         => 1,                       # 0
 });

Constructor. Should not be called directly. This documents the
attributes that are in common for L<Munin::Common::TLSServer> and
L<Munin::Common::TLSClient>.

=item B<read>

 my $msg = $tls->read();

Encrypted read.

=item B<write>

 $tls->write($msg);

Encrypted write.

=item B<session_started>

 my $bool = $tls->session_started();

Returns true if the TLS object is ready to read/write encrypted data.

=back
