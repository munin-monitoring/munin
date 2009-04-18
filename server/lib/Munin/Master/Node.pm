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
        master_capabilities => qw(foo),
        io_timeout => 5,
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

    my $greeting = $self->_node_read_single();

    $self->_run_starttls_if_required();
}

sub _run_starttls_if_required {
    my ($self) = @_;

    # TLS should only be attempted if explicitly enabled. The default
    # value is therefore "disabled" (and not "auto" as before).
    my $tls_requirement = $config->{tls};
    logger("[DEBUG] TLS set to \"$tls_requirement\".") if $config->{debug};
    return if $tls_requirement eq 'disabled';
    $self->{tls} = Munin::Common::TLSClient->new({
        DEBUG        => $config->{debug},
        logger       => \&logger,
        read_fd      => fileno($self->{socket}),
        read_func    => sub { _node_read_single($self) },
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
            croak("[ERROR] Could not establish TLS connection to '$self->{address}'. Skipping.");
        }
    }
}


sub _do_close {
    my ($self) = @_;
    
    close $self->{socket};
    $self->{socket} = undef;
}

sub negotiate_capabilities {
    my ($self) = @_;

    $self->_node_write_single("cap $self->{master_capabilities}\n");
    my @lines = $self->_node_read();

    if (index($lines[0], '# Unknown command') == 0) {
        return ('NA');
    }

    my $node_capabilities = substr $lines[0], 2, index($lines[0], ')');
    my $session_capabilities = $lines[1];

    logger("[DEBUG] $node_capabilities") if $config->{debug};
    logger("[DEBUG] Session capabilities: $session_capabilities") 
        if $config->{debug};

    return split / /, $session_capabilities;
}

sub list_services {
    my ($self) = @_;
    
    $self->_node_write_single("list\n"); # FIX specify which host
    my $list = $self->_node_read_single();
    
    return split / /, $list;
}

sub fetch_service_config {
    my ($self, $service) = @_;

    logger("[DEBUG] Configuring service: $service") if $config->{debug};
    $self->_node_write_single("config $service\n");

    my @lines = $self->_node_read();
    
    my @global_config = ();
    my @data_source_config = ();

    for my $line (@lines) {
        croak "Client reported timeout in configuration of '$service'"
            if $line =~ /\# timeout/;
        
        next unless $line;
        next if $line =~ /^\#/;
        

        if ($line =~ m{\A (\w+)\.(\w+) \s+ (.+) }xms) {
            push @data_source_config, [$1, $2, $3];
            # FIX sanitise $1 and $2 if label some where
            logger("config: $service->$1.$2 = $3") if $config->{debug};
            # FIX graph_order
        } 
        elsif ($line =~ m{\A (\w+) \s+ (.+) }xms) {
            push @global_config, [$1, $2];
            logger ("Config: $service->$1 = $2") if $config->{debug};
            # FIX graph_order
        }
    }

    return (global => \@global_config, data_source => \@data_source_config);
}

sub fetch_service_data {}


sub _node_write_single {
    my ($self, $text) = @_;

    logger("[DEBUG] Writing to socket: \"$text\".") if $config->{debug};
    my $timed_out = !do_with_timeout($self->{io_timeout}, sub { 
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

sub _node_read_single {
    my ($self) = @_;
    my $res;

    my $timed_out = !do_with_timeout($self->{io_timeout}, sub { 
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


sub _node_read {
    my ($self) = @_;
    my @array = (); 

    my $timed_out = !do_with_timeout($self->{io_timeout}, sub { 
        while (1) {
            my $line = $self->{tls} && $self->{tls}->session_started()
                ? $self->{tls}->read()
                : readline $self->{socket};
            last unless defined $line;
            last if $line =~ /^\.\n$/;
            chomp $line;
            push @array, $line;
        }
    });
    if ($timed_out) {
        logger ("[WARNING] Socket read timed out: $@\n");
        return;
    }
    logger ("[DEBUG] Reading from socket: \"".(join ("\\n",@array))."\".") if $config->{debug};
    return @array;
}


1;


__END__

=head1 NAME

FIX

=head1 SYNOPSIS

FIX

=head1 METHODS

FIX

