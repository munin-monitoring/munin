package Munin::Common::Config;

use warnings;
use strict;

use Carp;
use English qw(-no_match_vars);

# Functions here are unable to log as they don't know if they're used
# by the node or the master which use divergent logging facilities.
# In fact, the list in %legal is only used by the master.

my %legal = map { $_ => 1 } qw(
	address
	always_send
	category_order
	cdef
	cdef_name
	cgitmpdir
	cgiurl
	cgiurl_graph
	colour
	command
	compare
	contact
	contacts
	create_args
	critical
	dbdir
	domain_order
	draw
	dropdownlimit
	extinfo
	fetch_data
	filename
	fork
	graph
	graph
	graphable
	graph_args
	graph_args_after
	graph_category
	graph_data_size
	graph_future
	graph_height
	graph_info
	graph_noscale
	graph_order
	graph_period
	graph_printf
	graph_scale
	graph_sources
	graph_strategy
	graph_sums
	graph_title
	graph_total
	graph_vlabel
	graph_vtitle
	graph_width
	group_order
	host_name
	htaccess
	htmldir
	html_rename
	html_strategy
	includedir
	info
	label
	line
	local_address
	logdir
	max
	max_cgi_graph_jobs
	max_graph_jobs
	max_html_jobs
	max_messages
	max_processes
	max_size_x
	max_size_y
	min
	munin_cgi_graph_jobs
	nagios
	ncsa
	ncsa_config
	ncsa_server
	negative
	node_order
	notify_alias
	nsca
	nsca_config
	nsca_server
	num_messages
	num_unknowns
	ok
	onlynullcdef
	palette
	pipe
	pipe_command
	port
	predict
	process
	realname
	realservname
	rrdcached_socket
	rundir
	service_order
	skipdraw
	ssh_command
	ssh_options
	stack
	state
	staticdir
	sum
	text
	timeout
	tls
	tls_ca_certificate
	tls_certificate
	tls_match
	tls_pem
	tls_private_key
	tls_verify_certificate
	tls_verify_depth
	tmpldir
	trend
	type
	unknown
	unknown_limit
	update
	update_rate
	use_default_name
	use_node_name
	use_default_node
	version
	warn
	warning
	worker_start_delay
);

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


# allows # characters to get through as long as they're escaped
# with a backslash
sub _strip_comment {
    my $class = shift;

    $_[0] =~ s/(?<!\\)#.*//;
    $_[0] =~ s/\\#/#/g;

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
