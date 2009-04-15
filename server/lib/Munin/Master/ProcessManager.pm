package Munin::Master::ProcessManager;

use warnings;
use strict;

use Carp;
use English qw(-no_match_vars);
use IO::Socket;
use Munin::Common::Timeout;
use POSIX qw(:sys_wait_h);
use Storable qw(nstore_fd fd_retrieve);


my $E_DIED      = 18;
my $E_TIMED_OUT = 19;

sub new {
    my ($class, $result_callback, $error_callback) = @_;

    croak "Argument exception: result_callback"
        unless ref $result_callback eq 'CODE';

    $error_callback ||= sub { warn "Worker failed: @_" };

    my $self = {
        max_concurrent  => 2,
        socket_file     => '/tmp/MuninMasterProcessManager.sock',
        result_callback => $result_callback,
        error_callback  => $error_callback,
        worker_pids     => {},
        worker_timeout  => 1,
        timeout         => 10,
    };
    
    return bless $self, $class;
}


sub add_workers {
    my ($self, @workers) = @_;

    for my $worker (@workers) {
        croak "Argument exception: \@workers"
            unless $worker->isa('Munin::Master::Worker');
    }

    $self->{workers} = \@workers;
}


sub start_work {
    my ($self) = @_;
    
    $self->{iterator_index} = 0;
    
    my $sock = $self->_prepare_unix_socket();

    $SIG{CHLD} = $self->_sig_chld_handler();

    for my $worker (@{$self->{workers}}) {
        my $pid = fork;
        if (!defined $pid) {
            croak "$!";
        }
        elsif ($pid) {
            $self->{worker_pids}{$pid} = $worker->{ID};
        }
        else {
            $self->_do_work($worker);
            exit 0;
        } 
    }

    $self->_collect_results($sock);
}


sub _sig_chld_handler {
    my ($self) = @_;

    return sub {
        my %code2msg = (
            $E_TIMED_OUT => 'Timed out',
            $E_DIED      => 'Died',
        );
        my $worker_pid;
        while (($worker_pid = waitpid(-1, &WNOHANG)) > 0) {
            if ($CHILD_ERROR) {
                $self->{error_callback}($self->{worker_pids}{$worker_pid},
                                        $code2msg{$CHILD_ERROR >> 8});
            }
            delete $self->{worker_pids}{$worker_pid};
        }
        $SIG{CHLD} = $self->_sig_chld_handler();   # install *after* calling waitpid
    };
}

sub _collect_results {
    my ($self, $sock) = @_;

    while (%{$self->{worker_pids}}) {
        my $worker_sock;
        my $timed_out = !do_with_timeout($self->{worker_timeout}, sub {
            accept $worker_sock, $sock;
        });
        next if $timed_out;
        next unless fileno $worker_sock;

        my $res = fd_retrieve($worker_sock);
        my ($worker_id, $real_res) = @$res;
        $self->{result_callback}($res);
    }
}


sub _prepare_unix_socket {
    my ($self) = @_;

    unlink $self->{socket_file}
        or $! ne 'No such file or directory' && croak "unlink failed: $!";
    socket my $sock, PF_UNIX, SOCK_STREAM, 0
        or croak "socket failed: $!";
    bind $sock, sockaddr_un($self->{socket_file})
        or croak "bind failed: $!";
    chmod oct(700), $self->{socket_file}
        or croak "chomd failed: $!";
    listen $sock, SOMAXCONN
        or croak "listen failed: $!";
    
    return $sock;
}


sub _do_work {
    my ($self, $worker) = @_;

    my $res;
    my $timed_out;
    eval {
        $timed_out = !do_with_timeout(1, sub {
            $res = $worker->do_work();
        });
    };
    exit $E_TIMED_OUT if $timed_out;
    exit $E_DIED if $EVAL_ERROR;

    socket my $sock, PF_UNIX, SOCK_STREAM, 0
        or croak "$!";
    connect $sock, sockaddr_un($self->{socket_file})
        or croak "$!";
    
    nstore_fd([ $worker->{ID},  $res], $sock);

    close $sock;
}


1;


__END__

=head1 NAME

FIX

=head1 SYNOPSIS

FIX

=head1 METHODS

FIX

