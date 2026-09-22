#!/usr/bin/perl
# Minimal single-process munin-node for integration testing.
# No fork — handles one connection at a time via IO::Select.

use strict;
use warnings;
use IO::Socket::INET;
use IO::Select;

my $port = shift || 24949;
my $num_plugins = shift || 30;

my $server = IO::Socket::INET->new(
    LocalPort => $port,
    LocalAddr => '0.0.0.0',
    Listen    => 10,
    ReuseAddr => 1,
    Proto     => 'tcp',
) or die "Cannot bind to port $port: $!\n";

print STDERR "node-test: listening on 0.0.0.0:$port\n";

my $select = IO::Select->new($server);

while (my @ready = $select->can_read()) {
    for my $fh (@ready) {
        if ($fh == $server) {
            my $client = $server->accept();
            next unless $client;
            handle_client($client);
        }
    }
}

sub handle_client {
    my ($client) = @_;
    my $hostname = "testhost$port";

    print $client "# munin node at $hostname\n";

    while (my $line = <$client>) {
        chomp($line);
        if ($line =~ /^list/) {
            my @plugins = map { "plugin_$_" } (1..$num_plugins);
            print $client join(" ", @plugins) . "\n";
        } elsif ($line =~ /^cap/) {
            print $client "cap multigraph\n";
        } elsif ($line =~ /^config (\S+)/) {
            my $plugin = $1;
            print $client "graph_title Test $plugin\n";
            for my $f (1..5) {
                print $client "field$f.label Field $f\n";
                print $client "field$f.type GAUGE\n";
                print $client "field$f.warning 80\n";
                print $client "field$f.critical 90\n";
                print $client "field$f.cdef field$f,1,*\n";
            }
            print $client ".\n";
        } elsif ($line =~ /^fetch (\S+)/) {
            my $plugin = $1;
            my $t = time();
            for my $f (1..5) {
                print $client "field$f.value $t:" . int(rand(100)) . "\n";
            }
            print $client ".\n";
        } elsif ($line =~ /^quit/) {
            close $client;
            return;
        } else {
            print $client ".\n";
        }
    }
    close $client;
}
