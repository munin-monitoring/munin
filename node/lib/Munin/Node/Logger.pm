package Munin::Node::Logger;

use warnings;
use strict;


BEGIN {
    use Exporter();
    our @ISA    = qw(Exporter);
    our @EXPORT = qw(&logger);
}


sub logger {
    my $text  = shift;
    my @date  = localtime (time);

    chomp ($text);
    $text =~ s/\n/\\n/g;

    printf STDERR ("%d/%02d/%02d-%02d:%02d:%02d [%d] %s\n",
                   $date[5]+1900,
                   $date[4]+1,
                   $date[3],
                   $date[2],
                   $date[1],
                   $date[0],
                   $$,
                   $text,
               );

    return;
}


1;


__END__

=head1 NAME

Munin::Node::Logger - The logger for munin node.

=head1 SYNOPSIS

Exports a logger() subroutine.

 use Munin::Node::Logger;

 logger("Nice log message");

=head1 SUBROUTINES

=over

=item B<< logger() >>

  logger($message);

Writes $message to STDERR together with the timestamp and process id.

=back
