package Munin::Master::GroupRepository;

use warnings;
use strict;

use Carp;
use Munin::Master::Group;
use Munin::Master::Host;


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
        croak "Invalid section name [" . $gah . "], check munin configuration file, failed" unless $gah =~ /^[\w;.]+$/;

        my $process = $self->_final_char_is(';', $gah)
            ? \&_process_group_section
            : \&_process_host_section;
        $process->($self, $gah, $groups_and_hosts->{$gah});
    }
    for my $group (values %{$self->{groups}}) {
        $group->give_attributes_to_hosts();
    }
}


sub _final_char_is {
    my ($self, $char, $str) = @_;

    return rindex($str, $char) == length($str);
}


sub _process_group_section {
    my ($self, $definition, $attributes) = @_;

    chop $definition if $self->_final_char_is(';', $definition);

    croak "Invalid group section definition" unless length $definition;

    $self->{groups}{$definition} ||= Munin::Master::Group->new($definition);
    $self->{groups}{$definition}->add_attributes($attributes);
    return $self->{groups}{$definition};
}


sub _process_host_section {
    my ($self, $definition, $attributes) = @_;

    my $group_definition = (index $definition, ';', > 0)
        ? substr $definition, 0, rindex($definition, ';')+1
        : $self->_extract_group_name_from_host_name($definition);

    my $group = $self->_process_group_section($group_definition, {});
    
    my $host_name = substr $definition, rindex($definition, ';')+1;
    my $host =  Munin::Master::Host->new($host_name, $group, $attributes);
    $group->add_host($host);

    return $host;
}


sub _extract_group_name_from_host_name {
    my ($self, $host_name) = @_;

    my $dot_loc = index($host_name, '.');

    return $dot_loc == -1
        ? $host_name
        : substr $host_name, $dot_loc + 1 ;
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

