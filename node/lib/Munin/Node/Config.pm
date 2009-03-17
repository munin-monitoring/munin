package Munin::Node::Config;

use strict;
use warnings;

use English qw(-no_match_vars);
use Carp;
use Munin::Node::OS;


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
        my $uid = Munin::Node::OS->get_uid($var_value);
        croak "Default user does not exist ($var_value)"
            unless defined $uid;
        return (defuser => $uid);
    }
    elsif ($var_name eq 'default_plugin_group'
               || $var_name eq 'default_client_group') {
        my $gid = Munin::Node::OS->get_gid($var_value);
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


sub process_plugin_configuration_files {
    my ($self) = @_;

    opendir my $DIR, $self->{sconfdir}
        or croak "Could not open plugin configuration directory: $!";


    my @ignores = @{$self->{ignores}};
    push @ignores, '^\.'; # Hidden files

  FILES:
    for my $file (grep { -f "$self->{sconfdir}/$_" } readdir ($DIR)) {

        # Untaint file
        next if $file !~ m/^([-\w.]+)$/; # Skip if any weird chars
        $file = $1;

        for my $regex (@ignores) {
            next FILES if $file =~ /$regex/;
        }

        # check perms on a file also checks the directory permissions
        next unless Munin::Node::OS->check_perms("$self->{sconfdir}/$file");
        
        open my $CONF, '<', "$self->{sconfdir}/$file"
            or carp "Could not open file '$self->{sconfdir}/$file' for reading ($!),"
                . "skipping plugin\n";
        next unless $CONF;
        
        eval {
            $self->parse_plugin_config($CONF)
        };
        if ($EVAL_ERROR) {
            carp sprintf(
                '%s at %s/%s line %d. Skipping the rest of the file',
                $EVAL_ERROR,
                $self->{sconfdir},
                $file,
                $CONF->input_line_number(),
            );
        }

        close $CONF
            or carp "Failed to close '$self->{sconfdir}/$file\': $!";

    }
    closedir $DIR
        or carp "Failed to close directory '$self->{sconfdir}': $!";
}


sub parse_plugin_config {
    my ($self, $IO_HANDLE) = @_;

    my $service;

    my $sconf = $self->{sconf};

    while (my $line = <$IO_HANDLE>) {
        $self->_strip_comment($line);
        $self->_trim($line);
        next unless length $line;

	if ($line =~ m{\A \s* \[ ([^\]]+) \] \s* \z}xms) {
	    $service = $1;
	}
        else {
            carp "Parse error: Clutter before section start." 
                unless $service;

            my @var = $self->_parse_plugin_line($_);
            next unless @var;
            if ($var[0] eq 'allow_deny') {
                $sconf->{$service}{$var[0]} ||= [];
                push @{$sconf->{$service}{$var[0]}}, $var[1];
            }
            elsif ($var[0] eq 'env') {
                $sconf->{$service}{'env'} ||= {};
                $sconf->{$service}{'env'}{$var[0]} = $var[1];
            }
            else {
                $sconf->{$service}{$var[0]} = $var[1];
            }
        }
    }
}


sub _parse_plugin_line {
    my ($class, $line) = @_;

    $line =~~ m{\A \s* env \s+ ([^=\s]+) \s* = \s* (.+) \z}xms
        and croak "Deprecated format: 'env $1=$2' should be rewritten to 'env.$1 $2'";
    $line =~ m{\A \s* (\w+) \s+ (.+) \z}xms
        or croak "Line is not well formed ($line)";

    my ($var_name, $var_value) = ($1, $2);

    if ($var_name eq 'user') {
        my $uid = Munin::Node::OS->get_uid($var_value);
        croak "User '$var_value' is nonexistant." unless defined $uid;
        return (user => $uid);
    }
    elsif ($var_name eq 'group') {
        
        # Support running with more than one group in effect. See
        # documentation on $EFFECTIVE_GROUP_ID in the perlvar(1)
        # manual page.
        my @groups = ();
        for my $group (split /\s*,\s*/, $var_value) {
            my $is_optional = $group =~ m{\A \( ([^)]+) \) \z}xms;
            $group          = $1 if $is_optional;

            my $gid = Munin::Node::OS->get_gid($group);
            croak "Group '$group' does not exist"
                unless defined $gid || $is_optional;

            if (!defined $gid && $is_optional) {
                carp "DEBUG: Skipping optional nonexistant group '$group'";
                return;
            }
            
            push @groups, $gid;
        }
        return (group => join ' ', @groups);
    }
    elsif ($var_name eq 'command') {
        return (command => [split /\s+/, $var_value]);
    }
    elsif ($var_name eq 'host_name') {
        return (host_name => $var_value);
    }
    elsif ($var_name eq 'timeout') {
        return (timeout => $var_value);
    }
    elsif ($var_name eq 'allow' || $var_name eq 'deny') {
        return ('allow_deny' => [$var_name, $var_value]);
    }
    elsif (index($var_name, 'env.') == 0) {
        return (env => { substr($var_name, 3) => $var_value});
    }
    else {
        croak "Failed to parse line: $line. "
            . "Should it have been 'env.$var_name $var_value'?";
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

=item B<process_plugin_configuration_files>

 $config->process_plugin_configuration_files();

FIX

=item B<parse_plugin_config>

 $config->parse_plugin_config($io_handle);

FIX

=cut
