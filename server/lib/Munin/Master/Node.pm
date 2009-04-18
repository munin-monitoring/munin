package Munin::Master::Node;

use warnings;
use strict;

use Carp;
use Munin::Master::Config;
use Munin::Common::Timeout;
use Munin::Common::TLSClient;
use Munin::Master::Logger;

my $config = Munin::Master::Config->instance();

sub new {
    my ($class, $address, $port, $host) = @_;

    my $self = {
        address => $address,
        port    => $port,
        host    => $host,
        tls     => undef,
        socket  => undef,
    };

    return bless $self, $class;
}

sub session {
    my ($self, $block) = @_;

    $self->_do_connect();
    $block->();
    $self->_do_close();
}

sub _do_connect {
    my ($self) = @_;

    $self->{socket} = IO::Socket::INET->new(
        PeerAddr  => $self->{address},
        PeerPort  => $self->{port},
        LocalAddr => undef,
        Proto     => 'tcp', 
        Timeout   => 60,
    ) or croak "Failed to create socket: $!";

    my $greeting = $self->_read_socket_single();

    $self->_run_starttls_if_required();
}

sub _run_starttls_if_required {
    my ($self) = @_;

    # TLS should only be attempted if explicitly enabled. The default
    # value is therefore "disabled" (and not "auto" as before).
    my $tls_requirement = $config->{tls};
    logger("[DEBUG]: TLS set to \"$tls_requirement\".") if $config->{debug};
    return if $tls_requirement eq 'disabled';
    $self->{tls} = Munin::Common::TLSClient->new({
        DEBUG        => $config->{debug},
        logger       => \&logger,
        read_fd      => fileno($self->{socket}),
        read_func    => sub { _read_socket_single($self) },
        tls_ca_cert  => $config->{tls_ca_certificate},
        tls_cert     => $config->{tls_certificate},
        tls_paranoia => $tls_requirement, 
        tls_priv     => $config->{tls_private_key},
        tls_vdepth   => $config->{tls_verify_depth},
        tls_verify   => $config->{tls_verify_certificate},
        write_fd     => fileno($self->{socket}),
        write_func   => sub { _write_socket_single($self, @_) },
    });

    if (!$self->{tls}->start_tls()) {
        $self->{tls} = undef;
        if ($tls_requirement eq "paranoid" or $tls_requirement eq "enabled") {
            croak("[ERROR]: Could not establish TLS connection to '$self->{address}'. Skipping.");
        }
    }
}


sub _do_close {
    my ($self) = @_;
    
    close $self->{socket};
    $self->{socket} = undef;
}

sub negotiate_capabilities {}

sub list_services {
    my ($self) = @_;
    
    $self->_write_socket_single("list\n"); # FIX specify which host
    my $list = $self->_read_socket_single();
    
    return split / /, $list;
}

sub fetch_service_config {}

sub fetch_service_data {}

sub _starttls {}



sub _write_socket_single {
    my ($self, $text) = @_;

    logger("[DEBUG] Writing to socket: \"$text\".") if $config->{debug};
    my $timed_out = !do_with_timeout(5, sub { 
	if ($self->{tls} && $self->{tls}->session_started()) {
	    $self->{tls}->write($text)
                or exit 9;
	}
	else {
	    print { $self->{socket} } $text;
	}
    });
    if ($timed_out) {
	logger("[WARNING] Socket write timed out\n");
	return;
    }
    return 1;
}

sub _read_socket_single {
    my ($self) = @_;
    my $res;

    my $timed_out = !do_with_timeout(5, sub { 
      if ($self->{tls} && $self->{tls}->session_started()) {
          $res = $self->{tls}->read();
      }
      else {
	  $res = readline $self->{socket};
      }
      chomp $res if defined $res;
    });
    if ($timed_out) {
	logger("[WARNING] Socket read timed out\n");
	return;
    }
    logger("[DEBUG] Reading from socket: \"$res\".") if $config->{debug};
    return $res;
}

1;

__END__

=head1 NAME

FIX

=head1 SYNOPSIS

FIX

=head1 METHODS

FIX

