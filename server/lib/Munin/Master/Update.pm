package Munin::Master::Update;

use warnings;
use strict;

use Carp;
use Munin::Master::Config;
use Munin::Master::GroupRepository;
use Munin::Master::UpdateWorker;
use Munin::Master::ProcessManager;
use Munin::Master::Utils;


my $config = Munin::Master::Config->instance();


sub new {
    my ($class) = @_;

    return bless {}, $class;
}


sub run {
    my ($self) = @_;
    
    $self->_create_rundir_if_missing();
    my @workers = $self->_create_workers();

    $self->_do_locked("$config->{rundir}/munin-update.lock", sub {
        if ($config->{fork}) {
            my $pm = Munin::Master::ProcessManager->new(sub {
                use Data::Dumper; warn Dumper(\@_); 
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

Munin::Master::Update - FIX

=head1 SYNOPSIS

FIX

=head1 METHODS

=over

=item B<new>

FIX

=item B<run>

FIX

=back

