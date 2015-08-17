use warnings;
use strict;

use Test::More;

if ($ENV{TEST_HEAVY}) {
    plan tests => 17;
}
else {
    plan skip_all => 'set TEST_HEAVY to enable these tests'
}

use Time::HiRes qw(sleep);
use File::Temp qw( tempdir );
use Munin::Common::Logger;
Munin::Common::Logger->_remove_default_logging;

use_ok('Munin::Master::ProcessManager');

use Munin::Master::Config;
my $config = Munin::Master::Config->instance()->{config};
$config->{rundir} = tempdir(CLEANUP => 1);

#
# Define some test workers 
#
package Test::Worker;
use base q(Munin::Master::Worker);

sub do_work {
    my ($self) = @_;

    1 for (0 .. rand 1_000_000); # sleep and alarm does not mix ...
    return $self->{ID};
}


package Test::NastyWorker;
use base q(Munin::Master::Worker);

use Carp;

sub do_work {
    croak "I'm nasty!";
}

package Test::SpinningWorker;
use base q(Munin::Master::Worker);

sub do_work {
    1 while (1);
}

package main;

#
# The tests
#

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


{
    my $pm = Munin::Master::ProcessManager->new(\&result_callback);

    $pm->{max_concurrent} = 1;
 
    $pm->add_workers(
        Test::Worker->new(1),
        Test::Worker->new(2),
        Test::Worker->new(3),
    );

    $pm->start_work();
}


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
 
    $pm->{worker_timeout} = 1;
   
    $pm->add_workers(
        Test::NastyWorker->new(),
        Test::SpinningWorker->new(),
        Test::Worker->new(1),
    );

    $pm->start_work();
}
