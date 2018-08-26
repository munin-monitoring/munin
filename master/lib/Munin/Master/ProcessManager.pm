package Munin::Master::ProcessManager;

# $Id$

use warnings;
use strict;

use Carp;
use English qw(-no_match_vars);
use IO::Socket;
use POSIX qw(:sys_wait_h);
use Storable qw(nstore_fd fd_retrieve);
use Time::HiRes;

use Munin::Common::Timeout;
use Munin::Master::Config;
use Munin::Master::Logger;

use Log::Log4perl qw( :easy );

my $E_DIED      = 18;
my $E_TIMED_OUT = 19;
my $E_CONNECT   = 20;

my $config = Munin::Master::Config->instance()->{config};

sub new {
    my ($class, $result_callback, $error_callback) = @_;

    croak "Argument exception: result_callback"
        unless ref $result_callback eq 'CODE';

    $error_callback ||= sub { warn "Worker failed: @_" };

    my $self = {
        max_concurrent  => $config->{max_processes},
        socket_file     => "$config->{rundir}/munin-master-processmanager-$$.sock",
        result_callback => $result_callback,
        error_callback  => $error_callback,

        worker_timeout  => 180,
        timeout         => 240,
        accept_timeout  => 10,

        active_workers  => {},
        result_queue    => {},
        pid2worker      => {},
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
    
    DEBUG "[DEBUG] Starting work";
    
    my $sock = $self->_prepare_unix_socket();

    $self->_start_waiting_workers();
    
    do_with_timeout($self->{timeout}, sub {
        $self->_collect_results($sock);
	return 1;
    }) or croak "Work timed out before all workers finished";

    $self->{workers} = [];
    DEBUG "[DEBUG] Work done";

    $self->_free_socket($sock);
}


sub _prepare_unix_socket {
    my ($self) = @_;

    if ( -e $self->{socket_file} ) {
	    unlink $self->{socket_file}
        	or croak "unlink failed: $!";
    }

    socket my $sock, PF_UNIX, SOCK_STREAM, 0
        or croak "socket failed: $!";
    bind $sock, sockaddr_un($self->{socket_file})
        or croak "bind failed: $!";
    chmod oct(700), $self->{socket_file}
        or croak "chmod failed: $!";
    listen $sock, SOMAXCONN
        or croak "listen failed: $!";
    
    return $sock;
}


sub _start_waiting_workers {
    my ($self) = @_;

    while (@{$self->{workers}}) {
        DEBUG "[DEBUG] Active workers: " . (scalar keys %{$self->{active_workers}}) . "/" . $self->{max_concurrent};
        last if scalar keys %{$self->{active_workers}} == $self->{max_concurrent};
	# Here we just start'em, check results in _collect_results
        $self->_start_next_worker();
    } continue {
	    # Sleep for a random time, to avoid too much process creation all at once
	    sleep ( rand ($config->{worker_start_delay}) ) if $config->{worker_start_delay};
    }
}

sub _start_next_worker {
    my ($self) = @_;

    my $worker = pop @{$self->{workers}};

    my $pid = fork;
    if (!defined $pid) {
        LOGCROAK "Forking worker failed: $!";
    }
    elsif ($pid) {
        $self->{active_workers}{$pid} = $worker;
        $self->{result_queue}{$worker->{ID}} = $worker;
    }
    else {
        $0 .= " [$worker]";
	my $res = $self->_do_work($worker);
	DEBUG "[DEBUG] Exit status $res for worker $worker";
        exit $res;
    } 
}



sub _collect_results {
    my ($self, $sock) = @_;

    while (%{$self->{result_queue}} || @{$self->{workers}}) {

        do {
            $self->_vet_finished_workers();
            $self->_start_waiting_workers();
        } while (!%{$self->{result_queue}} && @{$self->{workers}});

        my $worker_sock;
	DEBUG "[DEBUG] Active workers: " . (scalar keys %{$self->{active_workers}}) . "/" . $self->{max_concurrent};

	if (not %{$self->{active_workers}}) {
	    # Nothing left do do
	    last;
	}

        my $timed_out = !do_with_timeout($self->{accept_timeout}, sub {
            accept $worker_sock, $sock;
	    return 1;
        });
        if ($timed_out) {
	    if (defined($self->{host})) {
		my $nodedesignation = $self->{host}."/".
		    $self->{host}{address}.":".$self->{host}{port};

		WARN "[WARNING] Calling accept to collect results from "
		    . $nodedesignation
		    . " failed.  This could be due to network problems/firewalled munin-node. Remaining workers: "
		    . join(", ", keys %{$self->{result_queue}});
	    } else {
		INFO "[INFO] Remaining workers: " . join(", ", keys %{$self->{result_queue}});
	    }
	    next;
        } # if timed_out

        next unless fileno $worker_sock;

        my $res = fd_retrieve($worker_sock);
        my ($worker_id, $real_res) = @$res;

        delete $self->{result_queue}{$worker_id};

        $self->{result_callback}($res) if defined $real_res;

    }

    while (%{$self->{active_workers}}) {
        $self->_vet_finished_workers();
    }

}


sub _free_socket {
    my ($self, $sock) = @_;

    unlink $self->{socket_file}
        or $! ne 'No such file or directory' && croak "unlink failed: $!";
    close $sock
        or croak "socket close failed: $!";
}


sub _vet_finished_workers {
    my ($self) = @_;

    while ((my $worker_pid = waitpid(-1, WNOHANG)) > 0) {
        if ($CHILD_ERROR) {
	    DEBUG "[DEBUG] Got error from $worker_pid: $CHILD_ERROR.  Handling error";
            $self->_handle_worker_error($worker_pid);
        }
        my $child_exit   = $CHILD_ERROR >> 8;
	my $child_signal = $CHILD_ERROR & 127; 

	INFO "[INFO] Reaping $self->{active_workers}{$worker_pid}.  Exit value/signal: $child_exit/$child_signal";
        delete $self->{active_workers}{$worker_pid};
    }
}


sub _handle_worker_error {
    my ($self, $worker_pid) = @_;

    my %code2msg = (
        $E_TIMED_OUT => 'Timed out',
        $E_DIED      => 'Died',
	$E_CONNECT   => 'Connection failed',
    );
    my $worker_id = $self->{active_workers}{$worker_pid}{ID};
    my $exit_code = $CHILD_ERROR >> 8;
    $self->{error_callback}($self->{active_workers}{$worker_pid},
                            $code2msg{$exit_code} || $exit_code);

}


sub _do_work {
    my ($self, $worker) = @_;

    DEBUG "[DEBUG] Starting $worker";

    my $retval = 0;

    my $res;
    eval {
        my $timed_out = !do_with_timeout($self->{worker_timeout}, sub {
            $res = $worker->do_work();
	    return 1;
        });
	if ($timed_out) {
            ERROR "[ERROR] $worker timed out";
            $res = undef;
            $retval = $E_TIMED_OUT;
        } elsif (!defined($res)) {
	    ERROR "[ERROR] $worker failed to connect to node";
	    $retval = $E_CONNECT;
	}
    };
    if ($EVAL_ERROR) {
        $EVAL_ERROR =~ s/\R//;
        ERROR "[ERROR] $worker died with '$EVAL_ERROR'";
        $res = undef;
        $retval = $E_DIED;
    }

    # Stop trying if we already erred.
    return $retval if $retval;

    my $sock;
    unless (socket $sock, PF_UNIX, SOCK_STREAM, 0) {
	ERROR "[ERROR] Unable to create socket: $!";
	return $E_DIED;
    }
    unless (connect $sock, sockaddr_un($self->{socket_file})) {
	ERROR "[ERROR] Unable to connect to socket: $!";
	return $E_DIED;
    }
    
    nstore_fd([ $worker->{ID},  $res], $sock);

    close $sock;

    return $retval;
}


1;


__END__

=head1 NAME

Munin::Master::ProcessManager - Manager for parallel execution of Workers.

=head1 SYNOPSIS

 use Munin::Master::ProcessManager;
 my $pm = Munin::Master::ProcessManager->new(sub {
     my ($res) = @_;
     # Do something with $res ...
 });
 $pm->add_workers(...);
 $pm->start_work();

=head1 DESCRIPTION

FIX

=head1 METHODS

=over

=item B<new>

FIX

=item B<add_workers>

FIX

=item B<start_work>

FIX

=back

