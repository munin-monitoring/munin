package Munin::Master::GroupRepository;

use base qw(Munin::Master::Config);

# $Id$

use warnings;
use strict;

use Carp;
use Munin::Master::Group;
use Munin::Master::Host;
use Log::Log4perl qw( :easy );

sub new {
    my ($class, $groups_and_hosts) = @_;
    my $self = bless {}, $class;

    $self->{groups} = {};

    $self->_initialize($groups_and_hosts);

    return $self;
}


sub _initialize {
    my ($self, $groups_and_hosts) = @_;

    #use Data::Dumper; warn Dumper($groups_and_hosts);

    for my $gah (keys %$groups_and_hosts) {
	DEBUG "Initialization loop: section label [$gah]\n";

        croak "Invalid section name [" . $gah . 
	    "], check munin configuration file, failed"
	    unless $gah =~ /^[-\w;:.]+$/;

        $self->_process_section($gah, $groups_and_hosts->{$gah});
    }
    for my $group (values %{$self->{groups}}) {
        $group->give_attributes_to_hosts();
    }
}


sub _process_group {
    # Process group part of section
    my ($self, $group_name, $attributes) = @_;

    DEBUG "Processing section in group $group_name\n";

    croak "Invalid group section definition" unless length $group_name;

    $self->{groups}{$group_name} ||= Munin::Master::Group->new($group_name);
    $self->{groups}{$group_name}->add_attributes($attributes);

    return $self->{groups}{$group_name};
}


sub _process_section {
    my ($self, $definition, $attributes) = @_;

    DEBUG "Processing section labeled [$definition]\n";

    my $group_name = 
	$self->_extract_group_name_from_definition($definition);

    my $group = $self->_process_group($group_name, {});

    my $host_name = substr($definition, rindex($definition, ';')+1 );

    if (length($host_name) > 0) {
	my $host = Munin::Master::Host->new($host_name, $group, $attributes);
	$group->add_host($host);
    }

    return $group;
}


sub _extract_host_name_from_definition {
    my ($self, $definition) = @_;

    my $dot_loc = index($definition, '.');
    my $sc_loc = index($definition, ';');

    # Return bare hostname
    return $definition if $sc_loc == -1 and $dot_loc == -1;
}



sub get_all_hosts {
    my ($self) = @_;
    
    my @hosts = ();
    for my $group (values %{$self->{groups}}) {
        push @hosts, $group->get_all_hosts();
    }
                   
    return @hosts;
}

1;


__END__

=head1 NAME

Munin::Master::GroupRepository - FIX

=head1 SYNOPSIS

FIX

=head1 METHODS

=over

=item B<new>

FIX

=item B<get_all_hosts>

FIX

=back

