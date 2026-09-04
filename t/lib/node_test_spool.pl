#!/usr/bin/perl
# Minimal munin-node with spoolfetch support for integration testing.

use strict;
use warnings;
use IO::Socket::INET;
use POSIX;
use File::Temp qw(tempdir);
use File::Path qw(make_path);

my $port = shift || 24949;
my $num_plugins = shift || 3;

my $spooldir = tempdir(CLEANUP => 1);
make_path($spooldir);

my $server = IO::Socket::INET->new(
    LocalPort => $port,
    LocalAddr => '0.0.0.0',
    Listen    => 5,
    ReuseAddr => 1,
    Proto     => 'tcp',
) or die "Cannot bind to port $port: $!\n";

print "node-test-spool: listening on 0.0.0.0:$port (spooldir=$spooldir)\n";

# Pre-generate spool data
my $now = time();
for my $i (1..$num_plugins) {
    my $plugin = "plugin_$i";
    my $spool_file = "$spooldir/munin-daemon.$plugin." . ($now - 300) . ".300";
    open my $fh, '>', $spool_file or die "Cannot write $spool_file: $!\n";
    print $fh "timestamp $now\n";
    print $fh "multigraph $plugin\n";
    print $fh "field1.value 42\n";
    print $fh ".\n";
    close $fh;
}

$SIG{CHLD} = 'IGNORE';

while (my $client = $server->accept()) {
    if (fork() == 0) {
        # Child
        my $hostname = "testhost$port";
        print $client "# munin node at $hostname\n";

        while (my $line = <$client>) {
            chomp($line);
            if ($line =~ /^list/) {
                my @plugins = map { "plugin_$_" } (1..$num_plugins);
                print $client join(" ", @plugins) . "\n";
            } elsif ($line =~ /^cap/) {
                print $client "cap multigraph spool\n";
            } elsif ($line =~ /^config (\S+)/) {
                my $plugin = $1;
                print $client "graph_title Test $plugin\n";
                print $client "field1.label Field 1\n";
                print $client "field1.type GAUGE\n";
                print $client "field1.warning 80\n";
                print $client "field1.critical 90\n";
                print $client ".\n";
            } elsif ($line =~ /^fetch (\S+)/) {
                my $plugin = $1;
                my $t = time();
                print $client "field1.value $t:42\n";
                print $client ".\n";
            } elsif ($line =~ /^spoolfetch (\d+)/) {
                my $from_epoch = $1;
                opendir my $dh, $spooldir or die "Cannot open spooldir: $!\n";
                for my $file (sort readdir $dh) {
                    next unless $file =~ /^munin-daemon\./;
                    my $filepath = "$spooldir/$file";
                    open my $fh, '<', $filepath or next;
                    while (<$fh>) {
                        print $client $_;
                    }
                    close $fh;
                }
                closedir $dh;
                print $client ".\n";
            } elsif ($line =~ /^quit/) {
                close $client;
                POSIX::_exit(0);
            } else {
                print $client "Unknown command: $line\n";
            }
        }
        close $client;
        POSIX::_exit(0);
    }
    # Parent: close client socket, continue accepting
    close $client;
}
