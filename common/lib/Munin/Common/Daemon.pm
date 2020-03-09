package Munin::Common::Daemon;


use warnings;
use strict;

use English;
use IO::Socket;

use Munin::Node::Logger qw(logger);


sub emit_sd_notify_message {
    eval {
        logger("sd_notify: looking for NOTIFY_SOCKET environment variable");
        my $socket_path = $ENV{NOTIFY_SOCKET};
        if (defined $socket_path) {
            logger("sd_notify: preparing connection to '$socket_path'");
            # Prevent children from talking to the socket provided solely for us.
            delete $ENV{NOTIFY_SOCKET};
            # A socket path starting with "@" is interpreted as a Linux abstract namespace socket.
            # This can be indicated by the socket path starting with a null byte.
            # See "Address format: abstract" in "man 7 unix".
            $socket_path =~ s/^@/\0/;
            my $socket = IO::Socket::UNIX->new(Type => SOCK_DGRAM, Peer => $socket_path);
            logger("sd_notify: connected to socket '$socket_path'");
            if (defined $socket) {
                logger("sd_notify: sending READY signal to '$socket_path'");
                print($socket "READY=1\n");
                close($socket);
            } else {
                logger("sd_notify: failed to connect to socket '$socket_path'");
            }
        }
    }
}


1;


__END__

=head1 NAME

Munin::Common::Daemon - utilities for daemons.

=head1 SYNOPSIS

The following daemon-related features are supported:

=over
=item sd_notify: signal readiness of the daemon
=back


=head1 SUBROUTINES

=over

=item B<emit_sd_notify_message>

 emit_sd_notify_message();

Send a "ready" signal according to the C<sd_notify> interface:

=over
=item 1. check whether the environment variable "NOTIFY_SOCKET" is defined
=item 2. remove this variable from the environment (this interface is not propagated to children)
=item 3. send the string "READY=1" to the socket
=back

The function returns silently, if something fails.

The function should be called as soon as the service is ready to accept
requests.
Calling this function is always safe - independent of the caller supporting the
C<sd_notify> interface or not.

Examples for callers supporting the C<sd_notify> interface:

=over
=item systemd: see C<Type=Notify> in L<systemd.exec/5>
=item start-stop-daemon: see C<--notify-await> in L<start-stop-daemon/8>
=back

See L<text|https://www.freedesktop.org/software/systemd/man/sd_notify.html> for
details of this interface.

=back
