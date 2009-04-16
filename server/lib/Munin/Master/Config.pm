package Munin::Master::Config;
use base qw(Munin::Common::Config);

use warnings;
use strict;

use Carp;
use English qw(-no_match_vars);
use Munin::Common::Defaults;

{
    my $instance;

    sub instance {
        my ($class) = @_;
        
        $instance ||= bless {
            config_file  => "$Munin::Common::Defaults::MUNIN_CONFDIR/munin.conf",
            dbdir        => $Munin::Common::Defaults::MUNIN_DBDIR,
            logdir       => $Munin::Common::Defaults::MUNIN_LOGDIR,
            rundir       => $Munin::Common::Defaults::MUNIN_RUNDIR,
            tmpldir      => "$Munin::Common::Defaults::MUNIN_CONFDIR/templates",
        }, $class;
        
        return $instance;
    }
}


sub parse_config {
    my ($self, $io) = @_;
        
    my $section = $self;

    while (my $line = <$io>) {
        $self->_strip_comment($line);
        $self->_trim($line);
        next unless length $line;
        
        if ($line =~ m{\A \[ ([^]]+) \] \s* \z}xms) {
            $self->{$1} ||= {};
            $section = $self->{$1};
        }
        elsif ($line =~ m { \A \s* (\S+) \s+ (.*) }xms) {
            $section->{$1} = $2;
        }
        else {
            croak "Parse error: $line";
        }
    }
}


sub get_groups_and_hosts {
    my ($self) = @_;
    
    my %groups_and_hosts = ();
    while (my ($key, $val) = each %$self) {
        $groups_and_hosts{$key} = $val if ref $val eq 'HASH';
    }
    return %groups_and_hosts;
}


sub set {
    my ($self, $config) = @_;
    
    %$self = (%$self, %$config); 
}




1;


__END__

=head1 NAME

FIX

=head1 SYNOPSIS

FIX

=head1 METHODS

FIX

