use warnings;
use strict;

package Munin::Common::Timeout;
use base qw(Exporter);

use English qw(-no_match_vars);


BEGIN {
    our @EXPORT = qw(
        &do_with_timeout
        &reset_timeout
    );
}


my $current_timeout;


sub do_with_timeout {
    my ($timeout, $block) = @_;

    my $old_alarm           = alarm 0;
    my $old_handler         = $SIG{ALRM};
    my $old_current_timeout = $current_timeout;

    $current_timeout = $timeout;

    eval {
        local $SIG{ALRM} = sub { die "alarm\n" };
        alarm $timeout;
        $block->();
        alarm 0;
    };
    my $err = $EVAL_ERROR;

    my $remaining_alarm = alarm 0;

    $SIG{ALRM} = $old_handler ? $old_handler : 'DEFAULT';

    $current_timeout = $old_current_timeout;

    if ($old_alarm) {
	my $old_alarm = $old_alarm - $timeout + $remaining_alarm;
	if ($old_alarm > 0) {
	    alarm($old_alarm);
	} else {
            #It should have gone off already - so set it off
	    kill 'ALRM', $$;
	}
    }

    if ($err) {
        return if $EVAL_ERROR eq "alarm\n";
        die;
    }

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


=head1 DESCRIPTION

See also L<Time::Out>, L<Sys::AlarmCall>

=head1 SUBROUTINES

=over

=item B<do_with_timeout>

 my $finished_with_no_timeout = do_with_timeout($seconds, $block)
     or die "Timed out!";

FIX

=item B<reset_timeout>

 reset_timeout();

FIX

=back

