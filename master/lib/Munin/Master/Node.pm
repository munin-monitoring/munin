package Munin::Master::Node;

# $Id$

# This module is used by UpdateWorker to keep in touch with a node and
# parse some of the output.

use warnings;
use strict;

use Carp;
use Munin::Master::Config;
use Munin::Common::Timeout;
use Munin::Common::TLSClient;
use Data::Dumper;
use Log::Log4perl qw( :easy );

my $config = Munin::Master::Config->instance()->{config};

# Note: This timeout governs both small commands and waiting for the total
# output of a plugin.  It is reset for each read.

sub new {
    my ($class, $address, $port, $host, $configref) = @_;

    my $self = {
        address => $address,
        port    => $port,
        host    => $host,
        tls     => undef,
        socket  => undef,
        master_capabilities => qw(multigraph),
        io_timeout => 120,
	configref => $configref,
    };

    return bless $self, $class;
}


sub do_in_session {
    my ($self, $block) = @_;

    if ($self->_do_connect()) {
	$self->_run_starttls_if_required();
	$block->();
	$self->_do_close();
	return 1; # If we're still here
    }
    return 0;  # _do_connect failed.
}


sub _do_connect {
    # Connect to a munin node.  Return false if not, true otherwise.
    my ($self) = @_;

    LOGCROAK("[FATAL] No address!  Did you forget to set 'update no' or to set 'address <IP>' ?")
	if !defined($self->{address});

    if (! ( $self->{socket} = IO::Socket::INET->new(
		PeerAddr  => $self->{address},
		PeerPort  => $self->{port},
		LocalAddr => $config->{local_address},
		Proto     => 'tcp', 
		Timeout   => $config->{timeout}) ) ) {
	ERROR "Failed to connect to node $self->{address}:$self->{port}/tcp : $!";
	return 0;
    }

    my $greeting = $self->_node_read_single();
    $self->{node_name} = $self->_extract_name_from_greeting($greeting);
    return 1;
}


sub _extract_name_from_greeting {
    my ($self, $greeting) = @_;
    if (!$greeting) {
	die "[ERROR] Got no reply from node ".$self->{host}."\n";
    }
    if ($greeting !~ /\#.*(?:lrrd|munin) (?:client|node) at (\S+)/) {
	die "[ERROR] Got unknown reply from node ".$self->{host}."\n";
    }
    return $1;
}


sub _run_starttls_if_required {
    my ($self) = @_;

    # TLS should only be attempted if explicitly enabled. The default
    # value is therefore "disabled" (and not "auto" as before).
    my $tls_requirement = $config->{tls};
    DEBUG "TLS set to \"$tls_requirement\".";
    return if $tls_requirement eq 'disabled';
    my $logger = Log::Log4perl->get_logger("Munin::Master");
    $self->{tls} = Munin::Common::TLSClient->new({
        DEBUG        => $config->{debug},
        logger       => sub { $logger->warn(@_) },
        read_fd      => fileno($self->{socket}),
        read_func    => sub { _node_read_single($self) },
        tls_ca_cert  => $config->{tls_ca_certificate},
        tls_cert     => $config->{tls_certificate},
        tls_paranoia => $tls_requirement, 
        tls_priv     => $config->{tls_private_key},
        tls_vdepth   => $config->{tls_verify_depth},
        tls_verify   => $config->{tls_verify_certificate},
        tls_match    => $config->{tls_match},
        write_fd     => fileno($self->{socket}),
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

    close $self->{socket};
    $self->{socket} = undef;
}


sub negotiate_capabilities {
    my ($self) = @_;
    # Please note: Sone of the capabilities are asymetrical.  Each
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

    my $host = $self->{configref}{use_node_name}
        ? $self->{node_name}
        : $self->{host};

    if (not $host) {
	die "[ERROR] Couldn't find out which host to list on $host.\n";
    }

    $self->_node_write_single("list $host\n");
    my $list = $self->_node_read_single();

    if (not $list) {
        WARN "[WARNING] Config node $self->{host} listed no services for $host.  Please see http://munin-monitoring.org/wiki/FAQ_no_graphs for further information.";
    }

    return split / /, $list;
}


sub parse_service_config {
    my ($self, $service, @lines) = @_;

    my $errors;
    my $correct;

    my $plugin = $service;

    my $nodedesignation = $self->{host}."/".$self->{address}."/".$self->{port};

    my $global_config = {
	multigraph => [],
    };
    my $data_source_config = {};
    my @graph_order = ( );

    # Pascal style nested subroutine
    local *new_service = sub {
	push @{$global_config->{multigraph}}, $service;
	$global_config->{$service} = [];
	$data_source_config->{$service} = {};
    };


    local *push_graphorder = sub {
	my ($oldservice) = @_;

	push( @{$global_config->{$oldservice}}, 
	      ['graph_order', join(' ', @graph_order)] )
	    unless !@graph_order || 
	           grep { $_->[0] eq 'graph_order' } @{$global_config->{$oldservice}};
	@graph_order = ( );
    };


    DEBUG "[DEBUG] Now parsing config output from plugin $plugin on "
	.$self->{host};

    new_service($service);

    for my $line (@lines) {

	DEBUG "[CONFIG from $plugin] $line";

	if ($line =~ /\# timeout/) {
	    die "[ERROR] Timeout error on $nodedesignation during fetch of $plugin. \n";
	}

        next unless $line;
        next if $line =~ /^\#/;

	if ($line =~ m{\A multigraph \s+ (.+) }xms) {
	    $correct++;

	    push_graphorder($service);

	    $service = $1;

	    if ($service eq 'multigraph') {
		die "[ERROR] SERVICE can't be named \"$service\" in plugin $plugin on ".$self->{host}."/".$self->{address}."/".$self->{port};
	    }
	    new_service($service);
	    DEBUG "[CONFIG multigraph $plugin] Service is now $service";
	}
	elsif ($line =~ m{\A ([^\s\.]+) \s+ (.+) }xms) {
	    $correct++;

	    my $label = $self->_sanitise_fieldname($1);

            push @{$global_config->{$service}}, [$label, $2];
            DEBUG "[CONFIG graph global $plugin] $service->$label = $2";
        }
	elsif ($line =~ m{\A ([^\.]+)\.([^\s]+) \s+ (.+) }xms) {
	    $correct++;
	    
            my ($ds_name, $ds_var, $ds_val) = ($1, $2, $3);
            $ds_name = $self->_sanitise_fieldname($ds_name);
            $data_source_config->{$service}{$ds_name} ||= {};
            $data_source_config->{$service}{$ds_name}{$ds_var} = $ds_val;
            DEBUG "[CONFIG dataseries $plugin] $service->$ds_name.$ds_var = $ds_val";
            push ( @graph_order, $ds_name ) if $ds_var eq 'label';
        }
	else {
	    $errors++;
	    DEBUG "[DEBUG] Protocol exception: unrecognized line '$line' from $plugin on $nodedesignation.\n";
        }
    }

    if ($errors) {
	WARN "[WARNING] $errors lines had errors while $correct lines were correct in data from 'config $plugin' on $nodedesignation";
    }

    $self->_validate_data_sources($data_source_config);

    push_graphorder($service);

    return (global => $global_config, data_source => $data_source_config);
}


sub fetch_service_config {
    my ($self, $service) = @_;

    DEBUG "[DEBUG] Fetching service configuration for '$service'";
    $self->_node_write_single("config $service\n");

    # The whole config in one fell swoop.
    my @lines = $self->_node_read();

    $service = $self->_sanitise_plugin_name($service);

    return $self->parse_service_config($service,@lines);
}


sub _validate_data_sources {
    my ($self, $all_data_source_config) = @_;

    my $nodedesignation = $self->{host}."/".$self->{address}.":".$self->{port};

    for my $service (keys %$all_data_source_config) {
	my $data_source_config = $all_data_source_config->{$service};

	for my $ds (keys %$data_source_config) {
	    if (!defined $data_source_config->{$ds}{label}) {
		ERROR "Missing required attribute 'label' for data source '$ds' in service $service on $nodedesignation";
		$data_source_config->{$ds}{label} = 'No .label provided';
		$data_source_config->{$ds}{extinfo} = "NOTE: The plugin did not provide any label for the data source $ds.  It is in need of fixing.";
	    }
	}
    }
}


sub parse_service_data {
    my ($self, $service, @lines) = @_;

    my $plugin = $service;
    my $errors = 0;
    my $correct = 0;

    my $nodedesignation = $self->{host}."/".$self->{address}.":".$self->{port};

    my %values = (
	$service => {},
    );

    DEBUG "[DEBUG] Now parsing fetch output from plugin $plugin on ".
	$nodedesignation;

    for my $line (@lines) {

	DEBUG "[FETCH from $plugin] $line";

	if ($line =~ /\# timeout/) {
	    die "[WARNING] Timeout in fetch from '$plugin' on ".
		$nodedesignation;
	}

        next unless $line;
        next if $line =~ /^\#/;

	if ($line =~ m{\A multigraph \s+ (.+) }xms) {
	    $correct++;

	    $service = $1;
	    $values{$service} = {};

	    if ($service eq 'multigraph') {
		ERROR "[ERROR] SERVICE can't be named \"$service\" in plugin $plugin on ".
		    $nodedesignation;
		croak("Plugin error.  Please consult the log.");
	    }
	}
	elsif ($line =~ m{\A ([^\.]+)\.value \s+ ([\S:]+) }xms) {
            my ($data_source, $value, $when) = ($1, $2, 'N');

	    $correct++;

            $data_source = $self->_sanitise_fieldname($data_source);

	    DEBUG "[FETCH from $plugin] Storing $value in $data_source";

	    if ($value =~ /^(\d+):(.+)$/) {
		$when = $1;
		$value = $2;
	    }

	    $values{$service}{$data_source} ||= {};

            $values{$service}{$data_source}{value} = $value;
            $values{$service}{$data_source}{when}  = $when;
        }
	elsif ($line =~ m{\A ([^\.]+)\.extinfo \s+ (.+) }xms) {
	    # Extinfo is used in munin-limits
            my ($data_source, $value) = ($1, $2);
	    
	    $correct++;

            $data_source = $self->_sanitise_fieldname($data_source);

	    $values{$service}{$data_source} ||= {};

	    $values{$service}{$data_source}{extinfo} = $value;

	}
        else {
	    $errors++;
            DEBUG "[DEBUG] Protocol exception while fetching '$service' from $plugin on $nodedesignation: unrecognized line '$line'";
	    next;
        }
    }
    if ($errors) {
	WARN "[WARNING] $errors lines had errors while $correct lines were correct in data from 'fetch $plugin' on $nodedesignation";
    }

    return %values;
}


sub fetch_service_data {
    my ($self, $plugin) = @_;

    $self->_node_write_single("fetch $plugin\n");

    my @lines = $self->_node_read();

    $plugin = $self->_sanitise_plugin_name($plugin);

    return $self->parse_service_data($plugin,@lines);
}


sub _sanitise_plugin_name {
    my ($self, $name) = @_;

    $name =~ s/[^_A-Za-z0-9]/_/g;
    
    return $name;
}


sub _sanitise_fieldname {
    # http://munin.projects.linpro.no/wiki/notes_on_datasource_names
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
            $self->{tls}->write($text)
                or exit 9;
        }
        else {
            print { $self->{socket} } $text;
        }
    });
    if ($timed_out) {
        LOGCROAK "[FATAL] Socket write timed out to ".$self->{host}.
	    ".  Terminating process.";
    }
    return 1;
}


sub _node_read_single {
    my ($self) = @_;
    my $res = undef;

    my $timed_out = !do_with_timeout($self->{io_timeout}, sub {
      if ($self->{tls} && $self->{tls}->session_started()) {
          $res = $self->{tls}->read();
      }
      else {
          $res = readline $self->{socket};
      }
      chomp $res if defined $res;
    });
    if ($timed_out) {
        LOGCROAK "[FATAL] Socket read timed out to ".$self->{host}.
	    ".  Terminating process.";
    }
    if (!defined($res)) {
	# Probable socket not open.  Why are we here again then?
	# aren't we supposed to be in "do in session"?
	LOGCROAK "[FATAL] Socket read from ".$self->{host}." failed.  Terminating process.";
    }
    DEBUG "[DEBUG] Reading from socket to ".$self->{host}.": \"$res\".";
    return $res;
}


sub _node_read {
    my ($self) = @_;
    my @array = (); 

    my $timed_out = !do_with_timeout($self->{io_timeout}, sub {
        while (1) {
            my $line = $self->{tls} && $self->{tls}->session_started()
                ? $self->{tls}->read()
                : readline $self->{socket};
            last unless defined $line;
            last if $line =~ /^\.\n$/;
            chomp $line;
            push @array, $line;
        }
    });
    if ($timed_out) {
        LOGCROAK "[FATAL] Socket read timed out to ".$self->{host}.": $@\n";
    }
    DEBUG "[DEBUG] Reading from socket: \"".(join ("\\n",@array))."\".";
    return @array;
}

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
