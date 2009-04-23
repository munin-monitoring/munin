package Munin::Master::Update;

use warnings;
use strict;

use Carp;
use Munin::Master::Config;
use Munin::Master::GroupRepository;
use Munin::Master::Logger;
use Munin::Master::UpdateWorker;
use Munin::Master::ProcessManager;
use Munin::Master::Utils;
use Time::HiRes;


my $config = Munin::Master::Config->instance();

sub new {
    my ($class) = @_;

    return bless {}, $class;
}


sub run {
    my ($self) = @_;
    
    $self->_create_rundir_if_missing();

    $self->_do_with_lock_and_timing("$config->{rundir}/munin-update.lock", sub {
        my ($STATS) = @_;

        logger("Starting munin-update");

        my @workers = $self->_create_workers();

        if ($config->{fork}) {
            my $pm = Munin::Master::ProcessManager->new(sub {
                my ($res) = @_;
                printf $STATS "UD|%s|%.2f\n", @$res;
            });
            $pm->add_workers(@workers);
            $pm->start_work();
        }
        else {
            for my $worker (@workers) {
                my $res = $worker->do_work();
                use Data::Dumper; warn Dumper($res);
            }
        }
    });
}


sub _create_rundir_if_missing {
    my ($self) = @_;

    unless (-d $config->{rundir}) {
	mkdir $config->{rundir}, oct(700)
            or croak "Failed to create rundir: $!";
        
    }
}


sub _create_workers {
    my ($self) = @_;

    my %gah = $config->get_groups_and_hosts();
    my $gr  = Munin::Master::GroupRepository->new(\%gah);

    my @hosts = $gr->get_all_hosts();

    if (%{$config->{limit_hosts}}) {
        @hosts = grep { $config->{limit_hosts}{$_->{host_name}} } @hosts
    }

    return map { Munin::Master::UpdateWorker->new($_) } @hosts;
}


sub _do_with_lock_and_timing {
    my ($self, $lock, $block) = @_;

    munin_runlock($lock);

    my $update_time = Time::HiRes::time;
    my $STATS;
    if (!open ($STATS, '>', "$config->{dbdir}/munin-update.stats.tmp")) {
        logger("[WARNING] Unable to open $config->{dbdir}/munin-update.stats");
        # Use /dev/null instead - if the admin won't fix he won't care
        open($STATS, '>', "/dev/null") or die "Could not open STATS to /dev/null: $?";
    }

    my $retval = $block->($STATS);

    $update_time = sprintf("%.2f", (Time::HiRes::time - $update_time));
    print $STATS "UT|$update_time\n";
    close ($STATS);
    rename ("$config->{dbdir}/munin-update.stats.tmp", "$config->{dbdir}/munin-update.stats");
    logger("Munin-update finished ($update_time sec)");

    munin_removelock($lock);

    return $retval;
}


1;


__END__

=head1 NAME

Munin::Master::Update - Contacts Munin Nodes, gathers data from
service data sources, and stores this information in RRD files.

=head1 SYNOPSIS

 my $update = Munin::Master::Update->new();
 $update->run();

=head1 METHODS

=over

=item B<new>

 my $update = Munin::Master::Update->new();

Constructor.

=item B<run>

 $update->run();

This is where all the work gets done.

=back

