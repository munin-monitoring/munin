use warnings;
use strict;

package Munin::Common::Timeout;
use base qw(Exporter);

use Carp;
use English qw(-no_match_vars);


BEGIN {
    our @EXPORT = qw(
        &do_with_timeout
    );
}

# This represents the current ALRM signal setting
my $current_timeout_epoch;

# This sub always uses absolute epoch time reference.
# This is in order to cope with eventual stealed time... 
# ... and to avoid complex timing computations
#
# $timeout is relative seconds, $timeout_epoch is absolute.
sub do_with_timeout {
    my ($timeout, $block) = @_;

    croak 'Argument exception: $timeout' 
        unless $timeout && $timeout =~ /^\d+$/;
    croak 'Argument exception: $block' 
        unless ref $block eq 'CODE';

    my $new_timeout_epoch = time + $timeout;

    # Nested timeouts cannot extend the global timeout, 
    # and we always leave 5s for outer loop to finish itself
    if ($current_timeout_epoch && $new_timeout_epoch > $current_timeout_epoch - 5) {
	    $new_timeout_epoch = $current_timeout_epoch - 5;
    }

    if ($new_timeout_epoch <= time) {
    	# Yey ! Time's up already, don't do anything, just : "farewell !"
        return undef;
    }

    # Ok, going under new timeout setting
    my $old_current_timeout_epoch = $current_timeout_epoch;
    $current_timeout_epoch = $new_timeout_epoch;

    my $ret_value;
    eval {
        local $SIG{ALRM} = sub { die "alarm\n" }; # NB: \n required 
        alarm ($new_timeout_epoch - time);
        $ret_value = $block->();
    };
    my $err = $EVAL_ERROR;

    # Restore the old $current_timeout_epoch...
    $current_timeout_epoch = $old_current_timeout_epoch;

    # ... and restart the old alarm if needed
    if ($current_timeout_epoch) {
       my $timeleft = $current_timeout_epoch - time;
       if ($timeleft <= 0) {
	       # no timeleft : directly raise alarm
	       die "alarm\n";
       }

       alarm ($timeleft);
    } else {
       # Remove the alarm
       alarm (0);
    }

    # And handle the return code
    if ($err) {
        return undef if $err eq "alarm\n";
        die $err; # Propagate any other exceptions
    }

    return $ret_value;
}

1;
__END__


=head1 NAME

Munin::Common::Timeout - Run code with a timeout. May nest.


=head1 SYNOPSIS

 use Munin::Common::Timeout;

 do_with_timeout(50, sub {
     # ...
 	do_with_timeout(5, sub {
		# ...
		# ...
	});
     # ...
 });


=head1 DESCRIPTION

See also L<Time::Out>, L<Sys::AlarmCall>

=head1 SUBROUTINES

=over

=item B<do_with_timeout>

 my $finished_with_no_timeout = do_with_timeout($seconds, $code_ref)
     or die "Timed out!";

Executes $block with a timeout of $seconds.  Returns the return value of the $block 
if it completed within the timeout.  If the timeout is reached and the code is still
running, it halts it and returns undef.

NB: every $code_ref should return something defined, otherwise the caller doesn't know
if a timeout occurred.

Calls to do_with_timeout() can be nested.  Any exceptions raised 
by $block are propagated.

=back

=cut
# vim: ts=4 : sw=4 : et
