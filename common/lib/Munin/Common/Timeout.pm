use warnings;
use strict;

package Munin::Common::Timeout;
use base qw(Exporter);

use English qw(-no_match_vars);


BEGIN {
    our @EXPORT = qw(&do_with_timeout, &reset_timeout);
}


my $current_timeout;


sub do_with_timeout {
    my ($timeout, $block) = @_;

    my $current_timeout = $timeout;

    eval {
        local $SIG{ALRM} = sub { die "alarm\n" };
        alarm $timeout;
        $block->();
        alarm 0;
    };
    if ($EVAL_ERROR) {
        return if $EVAL_ERROR eq "alarm\n";
        die;
    }

    alarm 0;
    return 1;
}


sub reset_timeout {
    alarm $current_timeout;
}

1;




__END__


=head1 NAME

Munin::Common::Timeout - FIX


=head1 SYNOPSIS

 use Munin::Common::Timeout;

 do_with_timeout(5, sub {
     # ...
     reset_timout(); # If needed
     # ...
 });


=head1 SUBROUTINES

=over

=item B<do_with_timeout>

 my do_with_timeout($seconds, $block)
     or die "Timed out!";

FIX

=item B<reset_timeout>

 reset_timeout();

FIX

=back

