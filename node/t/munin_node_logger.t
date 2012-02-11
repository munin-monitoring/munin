use warnings;
use strict;

use Test::More tests => 7;

use Munin::Node::Logger;

{
    open my $fh, '>', \(my $logger_message) or die "Unable to open scalar-backed filehandle: $!";

    {
        local *STDERR = $fh;
        logger('log message');
    }

    ok($logger_message, 'Log message was printed when DEBUG is enabled') or next;
    like($logger_message, qr(\[$$\]), 'Log message contains the PID');
    like($logger_message, qr(\blog message\b), 'Log message contains the text');
}
{
    open my $fh, '>', \(my $logger_message) or die "Unable to open scalar-backed filehandle: $!";

    {
        local *STDERR = $fh;
        logger("log message\n");
    }

    ok($logger_message, 'Log message was printed when DEBUG is enabled') or next;
    like($logger_message, qr([^\n]\n$), 'Log message ends with a single newline');
}
{
    open my $fh, '>', \(my $logger_message) or die "Unable to open scalar-backed filehandle: $!";

    {
        local *STDERR = $fh;
        logger("log\n\nmessage\n");
    }

    ok($logger_message, 'Log message was printed when DEBUG is enabled') or next;
    like($logger_message, qr(\Q\n\n\E), 'Embedded newlines are escaped');
}

# vim: ts=4 : sw=4 : et
