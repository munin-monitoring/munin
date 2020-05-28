package Munin::Master::Worker;

use warnings;
use strict;

use Scalar::Util qw(refaddr);


use overload q{""} => 'to_string';


sub new {
    my ($class, $identity) = @_;

    my $self = bless {}, $class;

    $identity = refaddr($self) unless defined $identity;
    $self->{ID} = $identity;

    return $self;
}


sub to_string {
    my ($self) = @_;

    return sprintf("%s<%s>", ref $self, $self->{ID});
}


1;


__END__

=head1 NAME

Munin::Master::Worker - Abstract base class for workers.

=head1 SYNOPSIS

See L<Munin::Master::ProcessManager>.

=head1 METHODS

=over

=item B<new>

  Munin::Master::Worker->new($identity);

Constructor.  This is an abstract class, so this shouldn't be called directly.

The optional $identity argument should be a unique identifier for the process.

=item B<to_string>

  print $worker->string;

  # Stringifies too
  print "Worker $worker just died";

Returns a unique string representation of the worker.

=back

=cut

# vim: ts=4 : sw=4 : et
