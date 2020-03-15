package Munin::Node::Configure::Debug;

use strict;
use warnings;

use Exporter ();
our @ISA = qw/Exporter/;
our @EXPORT = qw/DEBUG/;

use Munin::Node::Config;
my $config = Munin::Node::Config->instance();


sub DEBUG { print '# ', @_, "\n" if $config->{DEBUG}; }


1;

__END__

=head1 NAME

Munin::Node::Configure::Debug - Prints a debug message in the standard munin-node-configure format.


=head1 SYNOPSIS

  DEBUG('This is a debug message');

=head1 SUBROUTINES

=over

=item B<DEBUG($message)>

Prints $message in the standard munin-node-configure format (to STDOUT,
prefixed with a '#' character), if and only if the DEBUG flag was set in the
Config instance.

$message should not have a leading '# ', or trailing newline.

=back

=cut
# vim: ts=4 : sw=4 : expandtab
