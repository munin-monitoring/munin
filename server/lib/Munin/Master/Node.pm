package Munin::Master::Node;

use warnings;
use strict;

use Carp;
use Munin::Common::Timeout;
use Munin::Master::Logger;

sub new {
    my ($class, $address, $port, $host) = @_;

    my $self = {
        address => $address,
        port    => $port,
        host    => $host,
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
}

sub _do_close {
    my ($self) = @_;
    
    close $self->{socket};
    $self->{socket} = undef;
}

sub negotiate_capabilities {}

sub list_services {
    my ($self) = @_;
    
    $self->_write_socket_single("list $self->{host}\n");
    my $list = $self->_read_socket_single();
    
    return split / /, $list;
}

sub fetch_service_config {}

sub fetch_service_data {}

sub start_tls {}



sub _write_socket_single {
    my ($self, $text) = @_;

    logger("[DEBUG] Writing to socket: \"$text\"."); #FIX if $DEBUG;
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
    logger("[DEBUG] Reading from socket: \"$res\"."); # if $DEBUG;
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

