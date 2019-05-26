package Munin::Node::Config;
use base qw(Munin::Common::Config);

# $Id$

use strict;
use warnings;

use English qw(-no_match_vars);
use Carp;
use Munin::Node::OS;
use Munin::Common::Defaults;


my %booleans = map {$_ => 1} qw(
    paranoia
    tls_verify_certificate
);


{
    my $instance;

    sub instance {
        my ($class) = @_;

        $instance ||= bless {
            config_file  => "$Munin::Common::Defaults::MUNIN_CONFDIR/munin-node.conf",
        }, $class;

        return $instance;
    }
}


sub reinitialize {
    my ($self, $attrs) = @_;

    $attrs ||= {};

    my $new_self = bless $attrs, ref $self;
    %$self = %$new_self;
}


sub parse_config_from_file
{
    my $self = shift;
    my ($file) = @_;

    # Check permissions of configuration
    unless (Munin::Node::OS->check_perms_if_paranoid($file)) {
        croak "Fatal error. Bailing out.";
    }
    return $self->SUPER::parse_config_from_file(@_);
}


sub parse_config {
    my ($self, $IO_HANDLE) = @_;

    while (my $line = <$IO_HANDLE>) {
        my @var = $self->_parse_line($line);
        next unless @var;
        if ($var[0] eq 'ignore_file') {
            push @{$self->{ignores}}, $var[1];
        }
        elsif ($var[0] eq 'unhandled') {
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

    return if $self->_handled_by_net_server($var_name);

    my %config_variables = map { $_ => 1 } qw(
        global_timeout
        ignore_file
        paranoia
        spooldir
        timeout
        tls
        tls_ca_certificate
        tls_certificate
        tls_private_key
        tls_verify_certificate
        tls_verify_depth
        tls_match
    );

    if ($config_variables{$var_name}) {
        return ($var_name => $booleans{$var_name} ? $self->_parse_bool($var_value) : $var_value);
    }
    elsif ($var_name eq 'host_name' || $var_name eq 'hostname') {
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
    else {
        return (unhandled => ($var_name => $var_value));
    }
}


{

    my %handled_by_net_server = map { $_ => 1 } qw(
          allow
          deny
          cidr_allow
          cidr_deny
          reverse_lookups
     );

    sub _handled_by_net_server {
        my ($self, $var_name) = @_;
        return $handled_by_net_server{$var_name};
    }
}


sub process_plugin_configuration_files {
    my ($self) = @_;

    opendir my $DIR, $self->{sconfdir}
        or croak "Could not open plugin configuration directory: $!";

    $self->{sconf} ||= {};

    my @ignores = $self->{ignores} ? @{$self->{ignores}} : ();
    push @ignores, '^\.'; # Hidden files

FILE:
    for my $file ( grep { -f "$self->{sconfdir}/$_" } sort( readdir($DIR) ) ) {
        # Untaint file
        next if $file !~ m/^([-\w.:]+)$/; # Skip if any weird chars
        $file = $1;

        for my $regex (@ignores) {
            next FILE if $file =~ /$regex/;
        }

        $self->parse_plugin_config_file("$self->{sconfdir}/$file");
    }

    closedir $DIR
        or carp "Failed to close directory '$self->{sconfdir}': $!";
}


sub parse_plugin_config_file {
    # Parse configuration files.  Any errors should cause processing
    # of the current file to abort with error message, but should not
    # be fatal.
    my ($self, $file) = @_;

    # check perms on a file also checks the directory permissions
    if (!Munin::Node::OS->check_perms_if_paranoid($file)) {
	print STDERR "Plugin configuration $file has unsafe permissions, skipping\n";
	return;
    }

    my $CONF;
    unless (open $CONF, '<', $file) {
        my $err = $!;
        carp "Could not open file '$file' for reading ($err), skipping.\n";
        return;
    }

    print STDERR "# Processing plugin configuration from $file\n"
	if $self->{DEBUG};

    eval { $self->parse_plugin_config($CONF) };
    if ($EVAL_ERROR) {
        carp sprintf(
            '%s at %s line %d. Skipping the rest of the file',
            $EVAL_ERROR,
            $file,
            $INPUT_LINE_NUMBER,
        );
    }

    close $CONF
        or carp "Failed to close '$file': $!";
}



sub parse_plugin_config {
    my ($self, $IO_HANDLE) = @_;

    my $service;

    my $sconf = $self->{sconf};

    while (my $line = <$IO_HANDLE>) {
        $self->_strip_comment($line);
        $self->_trim($line);
        next unless $line;

        if ($line =~ m{\A \s* \[ ([^\]]+) \] \s* \z}xms) {
            $service = $1;
        }
        else {
            croak "Parse error: Clutter before section start."
                unless $service;

            my @var = $self->_parse_plugin_line($line);
            next unless @var;
            if ($var[0] eq 'env') {
                my ($key, $value) = %{$var[1]};
                $sconf->{$service}{$var[0]}{$key} = $value;
            }
            else {
                $sconf->{$service}{$var[0]} = $var[1];
            }
        }
    }
}


sub _parse_plugin_line {
    my ($self, $line) = @_;

    $line =~ m{\A \s* env \s+ ([^=\s]+) \s* = \s* (.+) \z}xms
        and croak "Deprecated format: 'env $1=$2' should be rewritten to 'env.$1 $2'";
    $line =~ m{\A \s* ([\w\.]+) \s+ (.+) \z}xms
        or croak "Line is not well formed ($line)";

    my ($var_name, $var_value) = ($1, $2);

    if ($var_name eq 'user') {
        # Evaluation of user name is lazy, so that configuration for
        # plugins that are not used does not cause errors.
        return (user => $var_value);
    }
    elsif ($var_name eq 'group') {
        # Evaluation of group names is lazy too.
        return (group => [split /[\s,]+/, $var_value]);
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
    elsif ($var_name eq 'update_rate') {
        return (update_rate => $var_value);
    }
    elsif (index($var_name, 'env.') == 0) {
        return (env => { substr($var_name, length 'env.') => $var_value});
    }
    else {
        croak "Failed to parse line: $line. "
            . "Should it have been 'env.$var_name $var_value'?";
    }
}


sub apply_wildcards {
    my ($self, @services) = @_;
    my $wildcard_regex;

    # Need to sort the keys in descending order so that more specific
    # wildcards take precedence.
    for my $wildservice (grep { /\*$/ || /^\*/ } reverse sort keys %{$self->{sconf}}) {
        if ($wildservice =~ /\*$/) {
            $wildcard_regex = qr{^} . substr($wildservice, 0, -1);
        } else {
            $wildcard_regex = substr($wildservice, 1) . qr{$};
        }

        for my $service (@services) {
            next unless $service =~ /$wildcard_regex/;
            $self->_apply_wildcard_to_service($self->{sconf}{$wildservice},
                                              $service);
        }

        delete $self->{sconf}{$wildservice};
    }
}


sub _apply_wildcard_to_service {
    my ($self, $wildservice, $service) = @_;

    my $sconf = $self->{sconf}{$service} || {};

    # Environment
    if (exists $wildservice->{'env'}) {
        for my $key (keys %{$wildservice->{'env'}}) {
            next if exists $sconf->{'env'}
                 && exists $sconf->{'env'}{$key};
            $sconf->{'env'}{$key} = $wildservice->{'env'}{$key};
        }
    }

    for my $key (keys %{$wildservice}) {
        next if $key eq 'env';           # Already handled
        next if exists $sconf->{$key};

        $sconf->{$key} = $wildservice->{$key};
    }

    $self->{sconf}{$service} = $sconf;
    return;
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

Returns the singleton instance of this class.

=item B<reinitialize>

 $config->reinitialize();

Deletes all configuration variables

 $config->reinitialize(\%variables);

Deletes all configuration variables and reinitializes the object with
values from \%variables.

=item B<parse_config_from_file>

  $config->parse_config_from_file($filename);

Parses the munin node configuration from a file.  Dies if the file fails the
paranoia checks.

=item B<parse_config>

 $config->parse_config($io_handle);

Parses the munin node configuration from a filehandle.

=item B<process_plugin_configuration_files>

 $config->process_plugin_configuration_files();

Parses all unignored files in the plugin configuration folder.

=item B<parse_plugin_config_file>

 $config->parse_plugin_config_file($file);

Parses the plugin configuration in $file.

=item B<parse_plugin_config>

 $config->parse_plugin_config($io_handle);

Parses the plugin configuration from an L<IO::Handle>.

=item B<apply_wildcards>

 $config->apply_wildcards();

Applies the contents of any wildcard plugin configuration sections
to matching plugins.

See L<http://munin-monitoring.org/wiki/Priority_and_inheritance>

=back

=cut
# vim: sw=4 : ts=4 : et
