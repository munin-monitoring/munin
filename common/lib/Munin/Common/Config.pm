package Munin::Common::Config;

# $Id: Config.pm 3594 2010-05-15 09:59:10Z feiner.tom $

use warnings;
use strict;

use Carp;
use English qw(-no_match_vars);

# Functions here are unable to log as they don't know if they're used
# by the node or the master which use divergent logging facilities.

my %legal = map { $_ => 1 } (

        "tmpldir", "ncsa", "ncsa_server", "ncsa_config", "rundir",
	"dbdir", "logdir", "htmldir", "includedir", "domain_order",
	"node_order", "graph_order", "graph_sources", "fork",
	"graph_title", "create_args", "graph_args", "graph_vlabel",
	"graph_vtitle", "graph_total", "graph_scale", "graph",
	"update", "host_name", "label", "cdef", "draw", "graph",
	"max", "min", "negative", "skipdraw", "type", "warning",
	"critical", "stack", "sum", "address", "htaccess", "warn",
	"use_default_name", "use_node_name", "port", "graph_noscale",
	"nsca", "nsca_server", "nsca_config", "extinfo", "fetch_data",
	"filename", "max_processes", "nagios", "info", "graph_info",
	"graph_category", "graph_strategy", "graph_width",
	"graph_height", "graph_sums", "local_address", "compare",
	"text", "command", "contact", "contacts", "max_messages",
	"always_send", "notify_alias", "line", "state",
	"graph_period", "cgiurl_graph", "cgiurl", "tls",
	"service_order", "category_order", "version",
	"tls_certificate", "tls_private_key", "tls_pem",
	"tls_verify_certificate", "tls_verify_depth", "tls_match",
	"tls_ca_certificate", "graph_data_size", "colour",
	"graph_printf", "ok", "unknown", "palette", "realservname",
	"cdef_name", "graphable", "process", "realname",
	"onlynullcdef", "group_order", "pipe", "pipe_command",
	"unknown_limit", "num_unknowns", "dropdownlimit",
	"max_graph_jobs", "max_cgi_graph_jobs", "munin_cgi_graph_jobs" );

my %bools = map { $_ => 1} qw(yes no true false on off 1 0);

sub cl_is_keyword {
    # Class-less version of is_keyword for legacy code.
    my ($word) = @_;

    return defined $legal{$word};
}


sub is_keyword {
    my ($self, $word) = @_;

    return defined $legal{$word};
}


sub parse_config_from_file {
    my ($self, $config_file) = @_;

    $config_file ||= $self->{config_file};

    open my $file, '<', $config_file
        or croak "ERROR: Cannot open '$config_file': $OS_ERROR";

    # Note, parse_config is provided by node or master specific config class
    eval {
        $self->parse_config($file);
    };
    if ($EVAL_ERROR) {
        croak "ERROR: Failed to parse config file '$config_file': $EVAL_ERROR";
    }

    close $file
        or croak "Cannot close '$config_file': $OS_ERROR";
}


sub _trim {
    # Trim leading and trailing whitespace.
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


sub _looks_like_a_bool {
    my ($class, $str) = @_;

    return $bools{lc $str};
}


sub _parse_bool {
    my ($class, $str) = @_;

    croak "Parse exception: '$str' is not a boolean."
        unless $class->_looks_like_a_bool($str);

    return $str =~ m{\A no|false|off|0 \z}xi ? 0 : 1;
}


1;


__END__

=head1 NAME

Munin::Common::Config - Abstract base class for common config code.

=head1 SYNOPSIS

Don't use it directly. See L<Munin::Master::Config> and L<Munin::Node::Config>.

=head1 METHODS

=over

=item B<parse_config_from_file>

 $config->parse_config_from_file($file_name);

Parses the configuration in $file_name.

=back
