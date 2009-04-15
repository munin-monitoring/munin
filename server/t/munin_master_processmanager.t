use warnings;
use strict;

use Test::More tests => 11;

use_ok('Munin::Master::ProcessManager');

######################################################################
package Test::Worker;
use base q(Munin::Master::Worker);

use Time::HiRes qw(sleep);

sub do_work {
    my ($self) = @_;

    sleep rand 0.3;
    return $self->{ID};
}


package main;
######################################################################


sub result_callback {
    my ($res) = @_;

    ok($res->[0] == 1 || $res->[0] == 2 || $res->[0] == 3, "$res->[0] in 1,2,3");
    is_deeply($res, [$res->[0], $res->[0]], "\$res == [X,X], X <- $res->[0]");
}

{
    my $pm = Munin::Master::ProcessManager->new(\&result_callback);
    isa_ok($pm, 'Munin::Master::ProcessManager');
    
    $pm->add_workers(
        Test::Worker->new(1),
        Test::Worker->new(2),
        Test::Worker->new(3),
    );

    $pm->start_work();
}


######################################################################
package Test::NastyWorker;
use base q(Munin::Master::Worker);

use Carp;

sub do_work {
    croak "I'm nasty!";
}

package Test::SleepyWorker;
use base q(Munin::Master::Worker);

sub do_work {
    sleep 10 while (1);
}

package main;
######################################################################

sub result_callback2 {
    my ($res) = @_;

    is($res->[1], 1, "Got 1");
}

sub error_callback2 {
    my ($worker_id, $msg) = @_;

    ok($msg eq 'Timed out' || $msg eq 'Died', "Got error msg $msg");
}

{
    my $pm = Munin::Master::ProcessManager->new(\&result_callback2, \&error_callback2);
    
    $pm->add_workers(
        Test::NastyWorker->new(),
        Test::SleepyWorker->new(),
        Test::Worker->new(1),
    );

    $pm->start_work();
}
