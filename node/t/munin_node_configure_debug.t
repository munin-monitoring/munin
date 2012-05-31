use strict;
use warnings;

use Test::More tests => 3;

use Munin::Node::Configure::Debug;
use Munin::Node::Config;

my $config = Munin::Node::Config->instance;


{
    open my $fh, '>', \(my $debug_message) or die "Unable to open scalar-backed filehandle: $!";

    $config->{DEBUG} = 0;

    my $old_fh = select $fh;
    DEBUG('error message');
    select $old_fh;

    is($debug_message, undef, 'No debug message printed when DEBUG is not enabled');
}
{
    open my $fh, '>', \(my $debug_message) or die "Unable to open scalar-backed filehandle: $!";

    $config->{DEBUG} = 1;

    my $old_fh = select $fh;
    DEBUG('debug message');
    select $old_fh;

    ok($debug_message, 'Debug message was printed when DEBUG is enabled') or next;
    is($debug_message, "# debug message\n", 'Debug message is correctly formatted');
}

# vim: ts=4 : sw=4 : et
