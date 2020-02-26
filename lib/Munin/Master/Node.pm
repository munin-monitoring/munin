package Munin::Master::Node;


# This module is used by UpdateWorker to keep in touch with a node and
# parse some of the output.

use warnings;
use strict;

use Carp;
use Munin::Master::Config;
use Munin::Common::Timeout;
use Munin::Common::TLSClient;
use Data::Dumper;
use Munin::Common::Logger;

use Time::HiRes qw( gettimeofday tv_interval );
use IO::Socket::IP;

use English qw(-no_match_vars);
my $config = Munin::Master::Config->instance()->{config};

# Quick version, to enable "DEBUG ... if $debug" constructs
my $debug = $config->{debug};

# Note: This timeout governs both small commands and waiting for the total
# output of a plugin.  It is reset for each read.

sub new {
    my ($class, $address, $port, $host, $configref) = @_;

    my $self = {
        address => $address,
        port    => $port,
        host    => $host,
        tls     => undef,
        reader  => undef,
        pid     => undef,
        writer  => undef,
        master_capabilities => "multigraph",
        io_timeout => 120,
	configref => $configref,
    };

    return bless $self, $class;
}


sub do_in_session {
    my ($self, $block) = @_;

    if ($self->_do_connect()) {
	$self->_run_starttls_if_required();
	my $exit_value = $block->();
	$self->_do_close();
	return { exit_value => $exit_value }; # If we're still here
    }
    return 0;  # _do_connect failed.
}


sub _do_connect {
    # Connect to a munin node.  Return false if not, true otherwise.
    my ($self) = @_;

    LOGCROAK("[FATAL] No address!  Did you forget to set 'update no' or to set 'address <IP>' ?")
	if !defined($self->{address});

    # Check if it's an URI or a plain host
    use URI;

    # Parameters are space-separated from the main address
    my ($url, $params) = split(/ +/, $self->{address}, 2);
    my $uri = new URI($url);

    # If address is only "ssh://host/" $params will not get set
    $params = "" unless defined $params;

    # If the scheme is not defined, it's a plain host.
    # Prefix it with munin:// to be able to parse it like others
    $uri = new URI("munin://" . $url) unless $uri->scheme;
    LOGCROAK("[FATAL] '$url' is not a valid address!") unless $uri->scheme;

    if ($uri->scheme eq "munin") {
        $self->{reader} = $self->{writer} = IO::Socket::IP->new(
		PeerAddr  => $uri->host,
		PeerPort  => $self->{port} || $uri->{port},
		LocalAddr => $config->{local_address},
		Proto     => 'tcp',
		MultiHomed => 1,
		Timeout   => $config->{timeout}
	);
	if (! $self->{reader} ) {
		ERROR "Failed to connect to node $self->{address}:$self->{port}/tcp : $!";
		return 0;
	}
    } elsif ($uri->scheme eq "ssh") {
	    my $ssh_command = sprintf("%s %s", $config->{ssh_command}, $config->{ssh_options});
	    my $user_part = ($uri->user) ? ($uri->user . "@") : "";
	    my $remote_cmd = ($uri->path ne '/') ? $uri->path : "";

	    # we use $uri->_port and not $uri->port to have the raw, and avoid
	    # the default being substituted if empty
	    my $remote_port = ($uri->_port) ? " -p $uri->_port" : "";

	    # Add any parameter to the cmd
	    my $remote_connection_cmd = $ssh_command . $remote_port . " " . $user_part . $uri->host . " " . $remote_cmd . " " . $params;

	    # Open a triple pipe
   	    use IPC::Open3;

	    # PATH has to be clean
	    local $ENV{PATH} = '/usr/sbin:/usr/bin:/sbin:/bin';

	    $self->{reader} = new IO::Handle();
	    $self->{writer} = new IO::Handle();
	    $self->{stderr} = new IO::Handle();

	    DEBUG "[DEBUG] open3($remote_connection_cmd)";
	    $self->{pid} = open3($self->{writer}, $self->{reader}, $self->{stderr}, $remote_connection_cmd);
            ERROR "Failed to connect to node $self->{address} : $!" unless $self->{pid};
    } elsif ($uri->scheme eq "cmd") {
        # local commands should ignore the username, url and host
        my $local_cmd = $uri->path;
        my $local_pipe_cmd = "$local_cmd $params";

	    # Open a triple pipe
   	    use IPC::Open3;

	    # PATH has to be clean
	    local $ENV{PATH} = '/usr/sbin:/usr/bin:/sbin:/bin';

	    $self->{reader} = new IO::Handle();
	    $self->{writer} = new IO::Handle();
	    $self->{stderr} = new IO::Handle();

	    DEBUG "[DEBUG] open3($local_pipe_cmd)";
	    $self->{pid} = open3($self->{writer}, $self->{reader}, $self->{stderr}, $local_pipe_cmd);
            ERROR "Failed to execute local command: $!" unless $self->{pid};
    } else {
	    ERROR "Unknown scheme : " . $uri->scheme;
	    return 0;
    }

    # check all the lines until we find one that matches the expected
    # greeting; ignore anything that doesn't look like it as long as
    # there is output. This allows one to accept SSH connections where
    # lastlog or motd is used.
    until(defined($self->{node_name})) {
	my $greeting = $self->_node_read_single();
	if (!$greeting) {
	    die "[ERROR] Got unknown reply from node ".$self->{host}."\n";
	}

	$self->_extract_name_from_greeting($greeting);
    };

    INFO "[INFO] node $self->{host} advertised itself as $self->{node_name} instead." if $self->{node_name} && $self->{node_name} ne $self->{host};

    return 1;
}

sub _extract_name_from_greeting {
    my ($self, $greeting) = @_;
    if ($greeting =~ /\#.*(?:lrrd|munin) (?:client|node) at (\S+)/i) {
	$self->{node_name} = $1;
    }
 }


sub _get_node_or_global_setting {
    my ($self, $key) = @_;
    return defined($self->{configref}->{$key}) ? $self->{configref}->{$key} : $config->{$key};
}


sub _run_starttls_if_required {
    my ($self) = @_;

    # TLS should only be attempted if explicitly enabled. The default
    # value is therefore "disabled" (and not "auto" as before).
    my $tls_requirement = $self->_get_node_or_global_setting("tls");
    DEBUG "TLS set to \"$tls_requirement\".";
    return if $tls_requirement eq 'disabled';
    $self->{tls} = Munin::Common::TLSClient->new({
        DEBUG        => $config->{debug},
        read_fd      => fileno($self->{reader}),
        read_func    => sub { _node_read_single($self) },
        tls_ca_cert  => $self->_get_node_or_global_setting("tls_ca_certificate"),
        tls_cert     => $self->_get_node_or_global_setting("tls_certificate"),
        tls_paranoia => $tls_requirement,
        tls_priv     => $self->_get_node_or_global_setting("tls_private_key"),
        tls_vdepth   => $self->_get_node_or_global_setting("tls_verify_depth"),
        tls_verify   => $self->_get_node_or_global_setting("tls_verify_certificate"),
        tls_match    => $self->_get_node_or_global_setting("tls_match"),
        write_fd     => fileno($self->{writer}),
        write_func   => sub { _node_write_single($self, @_) },
    });

    if (!$self->{tls}->start_tls()) {
        $self->{tls} = undef;
        if ($tls_requirement eq "paranoid" or $tls_requirement eq "enabled") {
	    die "[ERROR] Could not establish TLS connection to '$self->{address}'. Skipping.\n";
        }
    }
}


sub _do_close {
    my ($self) = @_;

    close $self->{reader};
    close $self->{writer};
    $self->{reader} = undef;
    $self->{writer} = undef;

    # Close stderr if needed
    close $self->{stderr} if $self->{stderr};
    $self->{stderr} = undef if $self->{stderr};

    # Reap the underlying process
    waitpid($self->{pid}, 0) if (defined $self->{pid});
}


sub negotiate_capabilities {
    my ($self) = @_;
    # Please note: Sone of the capabilities are asymmetrical.  Each
    # side simply announces which capabilities they have, and then the
    # other takes advantage of the capabilities it understands (or
    # dumbs itself down to the counterparts level of sophistication).

    DEBUG "[DEBUG] Negotiating capabilities\n";

    $self->_node_write_single("cap $self->{master_capabilities}\n");
    my $cap = $self->_node_read_single();

    if (index($cap, 'cap ') == -1) {
        return ('NA');
    }

    my @node_capabilities = split(/\s+/,$cap);
    shift @node_capabilities ; # Get rid of leading "cap".

    DEBUG "[DEBUG] Node says /$cap/\n";

    return @node_capabilities;
}


sub list_plugins {
    my ($self) = @_;

    # Check for one on this node- if not, use the global one
    my $use_node_name = defined($self->{configref}{use_node_name})
        ? $self->{configref}{use_node_name}
        : $config->{use_node_name};
    my $host = Munin::Master::Config->_parse_bool($use_node_name, 0)
        ? $self->{node_name}
        : $self->{host};

    my $use_default_node = defined($self->{configref}{use_default_node})
        ? $self->{configref}{use_default_node}
        : $config->{use_default_node};

    if (! $use_default_node && ! $host) {
	die "[ERROR] Couldn't find out which host to list on $host.\n";
    }

    my $host_list = ($use_node_name && $use_node_name eq "ignore") ? "" : $host;
    $self->_node_write_single("list $host_list\n");
    my $list = $self->_node_read_single("true");

    if (not $list) {
        WARN "[WARNING] Config node $self->{host} listed no services for '$host_list'.  Please see http://munin-monitoring.org/wiki/FAQ_no_graphs for further information.";
    }

    return split / /, $list;
}



sub fetch_service_config {
	my ($self, $service, $uw_handle_config) = @_;

	my $t0 = [gettimeofday];

	my $now = time; # Using the time of the call for the timing

	DEBUG "[DEBUG] Fetching service configuration for '$service'";
	$self->_node_write_single("config $service\n");

	# The whole config in one fell swoop.
	my $lines = $self->_node_read();

	my $elapsed = tv_interval($t0);

	my $nodedesignation = $self->{host}."/".$self->{address}."/".$self->{port};
	INFO "config: $elapsed sec for '$service' on $nodedesignation, read ". (scalar @$lines) . " lines" ;

	$service = $self->_sanitise_plugin_name($service);

	# Calling back uw_handle_config() with each multigraph block
	my $lines_block = [];
	my $local_service_name = $service;

	my $last_timestamp = 0;
	for my $line (@$lines) {
		DEBUG "handle '$line'";
		if ($line =~ m{\A multigraph \s+ (.+) }xms) {
			if (@$lines_block) {
				# Flush the previous block
				$last_timestamp = $uw_handle_config->($local_service_name, $now, $lines_block, $last_timestamp);
				$lines_block = [];
			}
			# Now we are in the new block
			$local_service_name = $1;
			$local_service_name = $self->_sanitise_plugin_name($local_service_name);

			next;
		}

		push @$lines_block, $line;
	}

	# This is the last multigraph, or the whole plugin if not multigraph
	$last_timestamp = $uw_handle_config->($local_service_name, $now, $lines_block, $last_timestamp);

	return $last_timestamp;
}

sub spoolfetch {
    my ($self, $timestamp, $uw_handle_config) = @_;

    DEBUG "[DEBUG] Fetching spooled services since $timestamp (" . localtime($timestamp) . ")";
    $self->_node_write_single("spoolfetch $timestamp\n");

    # The whole stuff in one fell swoop.
    my $now = time;
    my $last_timestamp = $timestamp;
    my $callback = sub {
	    my ($plugin, $data) = @_;
	    $last_timestamp = $uw_handle_config->($plugin, $now, $data, $last_timestamp)
    };
    my $lines = $self->_node_read($callback);

    # using the multigraph parsing.
    # Using "__root__" as a special plugin name.
    return $last_timestamp;
}

sub fetch_service_data {
    my ($self, $plugin, $uw_handle_data) = @_;

    my $t0 = [gettimeofday];

    $self->_node_write_single("fetch $plugin\n");

    my $lines = $self->_node_read($uw_handle_data);

    my $elapsed = tv_interval($t0);
    my $nodedesignation = $self->{host}."/".$self->{address}."/".$self->{port};
    INFO "data: $elapsed sec for '$plugin' on $nodedesignation";

    $plugin = $self->_sanitise_fieldname($plugin);
    return $uw_handle_data->($plugin, $lines);
}

sub quit {
    my ($self) = @_;

    my $t0 = [gettimeofday];
    $self->_node_write_single("quit \n");
    my $elapsed = tv_interval($t0);
    my $nodedesignation = $self->{host}."/".$self->{address}."/".$self->{port};
    INFO "quit: $elapsed sec on $nodedesignation";

    return 1;
}


sub _sanitise_plugin_name {
    my ($self, $name) = @_;

    $name =~ s/[^_A-Za-z0-9]/_/g;

    return $name;
}


sub _sanitise_fieldname {
    # http://munin-monitoring.org/wiki/notes_on_datasource_names
    my ($self, $name) = @_;

    $name =~ s/^[^A-Za-z_]/_/;
    $name =~ s/[^A-Za-z0-9_]/_/g;

    return $name;
}


sub _node_write_single {
    my ($self, $text) = @_;

    DEBUG "[DEBUG] Writing to socket: \"$text\".";
    my $timed_out = !do_with_timeout($self->{io_timeout}, sub {
        if ($self->{tls} && $self->{tls}->session_started()) {
            $self->{tls}->write($text) or exit 9;
        } else {
            print { $self->{writer} } $text;
        }
	return 1;
    });
    if ($timed_out) {
        LOGCROAK "[FATAL] Socket write timed out to ".$self->{host}.
	    ".  Terminating process.";
    }
    return 1;
}


sub _node_read_single {
    my ($self, $ignore_empty) = @_;

RESTART:

    my $res;
    my $tls = $self->{tls};
    if ($tls && $tls->session_started()) {
        $res = $tls->read();
    } else {
          $res = readline $self->{reader};
    }

    if (!defined($res)) {
	# Probable socket not open.  Why are we here again then?
	LOGCROAK "[FATAL] Socket read from ".$self->{host}." failed.  Terminating process.";
    }

    # Remove \r *and* \n
    # Normally only one, since we read line per line.
    # .. It has to be done in reverse order as we remove \n first, then \r.
    $res =~ s/\n$// if defined $res;
    $res =~ s/\r$// if defined $res;

    # Trim all whitespace
    if (defined $res) {
	$res =~ s/^\s+//;
	$res =~ s/\s+$//;
    }

    # If the line is empty, just read another line
    goto RESTART unless $res || $ignore_empty;

    DEBUG "[DEBUG] Reading from socket to ".$self->{host}.": \"$res\".";

    return $res;
}

sub _node_read {
    my ($self, $callback) = @_;

    my $current_plugin;
    my @array = ();

    while(my $line = $self->_node_read_single()) {
	DEBUG "_node_read(): $line";
	last if $line eq ".";

	# The trigger is always "multigraph ..."
	# We do callback the callback if defined
	unless ($callback && $line =~ m{\A multigraph \s+ (.+) }xms) {
		# Regular line
		push @array, $line;
	} else {
		my $new_plugin = $1;

		# Callback is called with ($plugin, $data) to flush the previous plugins
		# ... if there's already a plugin
		if ($current_plugin) {
			DEBUG "callback->($current_plugin, " . Dumper(\@array) . ")";
			$callback->($current_plugin, \@array);
		}

		# Handled the old one. Moving to the new one.
		$new_plugin = $self->_sanitise_plugin_name($new_plugin);
		$current_plugin = $new_plugin;
		@array = ();
	}
    }

    # Handle the multigraph one last time
    if ($callback && $current_plugin) {
	DEBUG "last callback->($current_plugin, " . Dumper(\@array) . ")";
	$callback->($current_plugin, \@array);
	@array = ();
    }

    # Return the remaining @array
    return \@array;
}

# Defines the URL::scheme for munin
package URI::munin;

# We are like a generic server
require URI::_server;
@URI::munin::ISA=qw(URI::_server);

# munin://HOST[:PORT]

sub default_port { return 4949; }

1;

__END__

=head1 NAME

Munin::Master::Node - Provides easy access to the munin node

=head1 SYNOPSIS

 use Munin::Master::Node;
 my $node = Munin::Master::Node->new('localhost', '4949', 'foo');
 $node->do_in_session(sub{
     ... # Call misc. methods on $node
 });

=head1 METHODS

=over

=item B<new>

FIX

=item B<do_in_session>

FIX

=item B<negotiate_capabilities>

FIX

=item B<list_services>

FIX

=item B<fetch_service_config>

FIX

=item B<fetch_service_data>

FIX

=back

