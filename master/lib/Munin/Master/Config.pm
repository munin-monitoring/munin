package Munin::Master::Config;
use base qw(Munin::Common::Config);

# $Id$

use warnings;
use strict;

use Carp;
use English qw(-no_match_vars);
use Munin::Common::Defaults;

my $MAXINT = 2 ** 53;

my %booleans = map {$_ => 1} qw(
    debug
    fork
    tls_verify_certificate
    update
    use_node_name
);


{
    my $instance;

    sub instance {
        my ($class) = @_;
        
        $instance ||= bless {
            config_file            => "$Munin::Common::Defaults::MUNIN_CONFDIR/munin.conf",
            dbdir                  => $Munin::Common::Defaults::MUNIN_DBDIR,
            debug                  => 0,
            fork                   => 1,
            graph_data_size        => 'normal',
            groups_and_hosts       => {},
            local_address          => 0,
            logdir                 => $Munin::Common::Defaults::MUNIN_LOGDIR,
            max_processes          => $MAXINT,
            rundir                 => '/tmp',
            timeout                => 180,
            tls                    => 'disabled',
            tls_ca_certificate     => "Munin::Common::Defaults::MUNIN_CONFDIR/cacert.pem",
            tls_certificate        => "$Munin::Common::Defaults::MUNIN_CONFDIR/munin.pem",
            tls_private_key        => "$Munin::Common::Defaults::MUNIN_CONFDIR/munin.pem",
            tls_verify_certificate => 0,
            tls_verify_depth       => 5,
            tmpldir                => "$Munin::Common::Defaults::MUNIN_CONFDIR/templates",
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
            $self->{groups_and_hosts}{$1} ||= {};
            $section = $self->{groups_and_hosts}{$1};
        }
        elsif ($line =~ m { \A \s* (\S+)\.(\S+) \s+ (.*) }xms) {
            $section->{service_config} ||= {};
            $section->{service_config}{$1} ||= {};
            $section->{service_config}{$1}{$2} = $booleans{$2} ? $self->_parse_bool($3) : $3;
        }
        elsif ($line =~ m { \A \s* (\S+) \s+ (.*) }xms) {
            $section->{$1} = $booleans{$1} ? $self->_parse_bool($2) : $2;
        }
        else {
            croak "Parse error: $line";
        }
    }
}


sub get_groups_and_hosts {
    my ($self) = @_;
    
    return %{$self->{groups_and_hosts}};
}


sub set {
    my ($self, $config) = @_;
    
    %$self = (%$self, %$config); 
}


1;


__END__

=head1 NAME

Munin::Master::Config - Holds the master configuration.

=head1 SYNOPSIS

FIX

=head1 METHODS

=over

=item B<instance>

FIX

=item B<parse_config>

FIX

=item B<set>

FIX

=item B<get_groups_and_hosts>

FIX

=back
