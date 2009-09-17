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


sub _final_char_is {
    # Not a object method.
    my ($char, $str) = @_;
 	
    return rindex($str, $char) == length($str);
}

sub _create_and_set {
    my ($self,$groups,$host,$rest,$value) = @_;
    # Nested creation of group and host class objects, and then set
    # attribute value.

    my $groupref = $self;

    my @rest = split(/\./, $rest);
    my $last_word = pop @rest;

    if ($booleans{$last_word}) {
	$value = $self->_parse_bool($value);
    }

    foreach my $group (@{$groups}) {
	# Create nested group objects
	$groupref->{groups}{$group} ||= Munin::Master::Group->new($group);
	if ($groupref eq $self) {
	    $groupref->{groups}{$group}{group}=undef;
	} else {
	    $groupref->{groups}{$group}{group}=$groupref;
	}
	$groupref = $groupref->{groups}{$group};
    }
    
    if ($host) {
	if (! defined ( $groupref->{hosts}{$host} ) ) {
	    $groupref->{hosts}{$host} =
		Munin::Master::Host->new($host,$groupref,{ $rest => $value });
	} else {
	    $groupref->{hosts}{$host}->add_attibutes_if_not_exists({ $rest => $value } );
    }
    }
}

sub set_value {
    # Set value in config hash, $value is full ;:. separated value.
    my ($self, $key, $value) = @_;
    
    my @words = split (/[;:.]/, $key);
    my $last_word = pop(@words);

    if (! $self->is_keyword($last_word)) {
	croak "Parse error in ".$self->{config_file}." in section [$prefix]:\n".
	    " Unknown keyword at end of left hand side of line ($key $value)\n";
    }

    my ($groups,$rest) = split(/:/, $key);
    my @groups = split(/;/, $groups);

    my $host;

    if (defined($rest)) {
	$host = pop(@groups);
    } else {
	# If there is no rest then the last "group" is a keyword.
	$host = '';
	$rest = pop(@groups);
    }
    $setting = $rest;

    $self->_create_and_set(\@groups,$host,$rest,$value);
}
    

sub _parse_config_line {
    my ($self, $prefix, $key, $value) = @_;

    my $longkey;

    # Allowed prefixes:
    # [group;]
    # [group;host]
    # [group;host:service]
    # [group;host:service.field]
    # [group1;group2;host:service.field]
    #    keyword value
    #    foo.bar value
    #    group_order ....
    #

    # Note that keywords can comme directly after group names in the
    # concatenated syntax: group;group_order ...

    if ($self->_final_char(';',$prefix)) {
	# Prefix ended in the middle of a group.  The rest can be
	# appended.
	$longkey = $prefix.$key;
    } elsif (index($prefix,':') != -1) {
	# Service name is part of the prefix.  Append with a "." betweeen
	$longkey = $prefix.".".$key;
    } else {
	# Prefix ends in host name, append with a ":" between
	$longkey = $prefix.":".$key;
    }
    my @words = split (/[;:.]/, $longkey);
    my $last_word = pop(@words);

    if (! $self->is_keyword($last_word)) {
	croak "Parse error in ".$self->{config_file}." in section [$prefix]:\n".
	    " Unknown keyword at end of left hand side of line ($key $value)\n";
    }

    $self->set_value($longkey,$value);
	
}


sub parse_config {
    my ($self, $io) = @_;
        
    my $section = undef;

    my $prefix = '';

    while (my $line = <$io>) {
        $self->_strip_comment($line);
        $self->_trim($line);
        if ( !length($line) ) {
	    next;
	}
        
	# Group/host/service configuration is saved for later persual.
	# Everything else is saved at once.  Note that _trim removes
	# leading whitespace so section changes can only happen if a new
	# [foo] comes along.

        if ($line =~ m{\A \[ ([^]]+) \] \s* \z}xms) {
	    $prefix = $1;
	} else {
	    my($key,$value) = split(/\s+/,$line,2);
	    $self->_parse_config_line($prefix,$key,$value);
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
