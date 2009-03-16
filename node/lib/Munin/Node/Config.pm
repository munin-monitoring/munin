use strict;
use warnings;

package Munin::Node::Config;

use English qw(-no_match_vars);
use Carp;
use Munin::OS;


{
    my $instance;

    sub instance {
        my ($class) = @_;
        
        return $instance ||= bless {}, $class;
    }
}


sub reinitialize {
    my ($self, $attrs) = @_;

    $attrs ||= {};

    my $new_self = bless $attrs, ref $self;
    %$self = %$new_self;
}


sub parse_config_from_file {
    my ($self, $file_name) = @_;

    open my $FILE, '<', $file_name 
        or croak "Cannot open '$file_name': $OS_ERROR";

    eval {
        $self->parse_config($FILE);
    };
    if ($EVAL_ERROR) {
        croak "Failed to parse config file '$file_name': $EVAL_ERROR";
    }
    
    close $FILE
        or croak "Cannot close '$file_name': $OS_ERROR";;
}


sub parse_config {
    my ($self, $IO_HANDLE) = @_;

    while (my $line = <$IO_HANDLE>) {
        my @var = $self->_parse_line($line);
        next unless @var;
        if ($var[0] eq 'ignore') {
            $self->{ignores} ||= [];
            push @{$self->{ignores}}, $var[1];
        } 
        elsif ($var[0] eq 'unhandled') {
            $self->{sconf} ||= {};
            next if defined $self->{sconf}{$var[1]};
            $self->{sconf}{$var[1]} = $var[2];
        }
        else {
            $self->{$var[0]} = $var[1];
        }
    }
}


sub _parse_line {
    my ($self, $line) = @_;

    $self->_strip_comment($line);
    $self->_trim($line);
    return unless length $line;

    $line =~ m{\A (\w+) \s+ (.+) \z}xms
        or croak "Line is not well formed ($line)";

    my ($var_name, $var_value) = ($1, $2);

    if ($var_name eq 'host_name' || $var_name eq 'hostname') {
        return (fqdn => $var_value);
    }
    elsif ($var_name eq 'default_plugin_user'
               || $var_name eq 'default_client_user') {
        my $uid = Munin::OS->get_uid($var_value);
        croak "Default user does not exist ($var_value)"
            unless defined $uid;
        return (defuser => $uid);
    }
    elsif ($var_name eq 'default_plugin_group'
               || $var_name eq 'default_client_group') {
        my $gid = Munin::OS->get_gid($var_value);
        croak "Default group does not exist ($var_value)"
            unless defined $gid;
        return (defgroup => $gid);
    }
    elsif ($var_name eq 'paranoia') {
        return (paranoia => $self->_parse_bool($var_value))
    }
    elsif ($var_name eq 'ignore_file') {
        return ('ignore' => $var_value);
    }
    elsif ($var_name eq 'timeout') {
        return (timeout => $var_value);
    }
    else {
        return (unhandled => ($var_name => $var_value));
    }
}


sub _trim {
    my $class = shift;
    
    chomp $_[0];
    $_[0] =~ s/^\s+//;
    $_[0] =~ s/\s+$//;

    return;
}


sub _strip_comment {
    my $class = shift;
    
    $_[0] =~ s/#.*//;
    
    return;
}


sub _parse_bool {
    my ($class, $str) = @_;

    return $str =~ m{\A no|false|off|0 \z}xms ? 0 : 1;
}

1;

__END__

=head1 NAME 

Munin::Node::Config - Singleton node configuration container. Reads
configuration files.


=head1 SYNOPSIS

 $config = Munin::Node::Config->instance();
 $config->parse_config_from_file('/etc/munin/munin-node.conf');
 print $config->{fqdn}, "\n";

=head1 METHODS

=over

=item B<instance>

 $config = Munin::Node::Config->instance();

Returns the sincgleton instance of this class.

=item B<reinitialize>

 $config->reinitialize();

Deletes all configuration variables

 $config->reinitialize(\%variables);

FIX

=item B<parse_config_from_file>

 $config->parse_config_from_file($file_name);

FIX

=item B<parse_config>

 $config->parse_config($io_handle);

FIX

=cut
