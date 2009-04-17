package Munin::Master::Update;

use warnings;
use strict;

use Carp;
use Munin::Master::Config;
use Munin::Master::GroupRepository;
use Munin::Master::UpdateWorker;
use Munin::Master::ProcessManager;
use Munin::Master::Utils;


sub new {
    my ($class) = @_;

    my $self = {
        config => Munin::Master::Config->instance(),
    };

    return bless $self, $class;
}


sub run {
    my ($self) = @_;
    
    $self->_create_rundir_if_missing();
    my %gah = $self->{config}->get_groups_and_hosts();
    my $gr  = Munin::Master::GroupRepository->new(\%gah);

    my @hosts = $gr->get_all_hosts();
    my @workers = map { Munin::Master::UpdateWorker->new($_) } @hosts;
    my $pm = Munin::Master::ProcessManager->new(sub { use Data::Dumper; warn Dumper(\@_); });
    $pm->add_workers(@workers);

    $self->_do_locked("$self->{config}{rundir}/munin-update.lock", sub {
        $pm->start_work();
    });
}


sub _create_rundir_if_missing {
    my ($self) = @_;

    unless (-d $self->{config}{rundir}) {
	mkdir $self->{config}{rundir}, oct(700)
            or croak "Failed to create rundir: $!";
        
    }
}


sub _do_locked {
    my ($self, $lock, $block) = @_;

    munin_runlock($lock);
    my $retval = $block->();
    munin_removelock($lock);

    return $retval;
}


1;


__END__

=head1 NAME

FIX

=head1 SYNOPSIS

FIX

=head1 METHODS

FIX

