package Munin::Master::UpdateWorker;
use base qw(Munin::Master::Worker);

# $Id$

use warnings;
use strict;

use Carp;
use English qw(-no_match_vars);
use Log::Log4perl qw( :easy );

use File::Basename;
use File::Path;
use File::Spec;
use Munin::Master::Config;
use Munin::Master::Node;
use Munin::Master::Utils;
use RRDs;
use Time::HiRes;
use Data::Dumper;
use List::Util qw(max);

my $config = Munin::Master::Config->instance()->{config};

sub new {
    my ($class, $host) = @_;

    my $self = $class->SUPER::new($host->get_full_path);
    $self->{host} = $host;
    $self->{node} = Munin::Master::Node->new($host->{address},
                                             $host->{port},
                                             $host->{host_name},
					     $host);

    return $self;
}


sub do_work {
    my ($self) = @_;

    my $update_time = Time::HiRes::time;

    my $host = $self->{host}{host_name};
    my $path = $self->{host}->get_full_path;
    $path =~ s{[:;]}{-}g;

    my $nodedesignation = $host."/".
	$self->{host}{address}.":".$self->{host}{port};

    my $lock_file = sprintf ('%s/munin-%s.lock',
			     $config->{rundir},
			     $path);

    if (!munin_getlock($lock_file)) {
	WARN "Could not get lock $lock_file for $nodedesignation. Skipping node.";
        die "Could not get lock $lock_file for $nodedesignation. Skipping node.\n";
    }

    my %all_service_configs = (
	data_source => {},
	global => {},
	);

    my $done = $self->{node}->do_in_session(sub {

	eval {
	    # A I/O timeout results in a violent exit.  Catch and handle.

	    my @node_capabilities = $self->{node}->negotiate_capabilities();

            # Handle spoolfetch, one call to retrieve everything
	    my %whole_config;
	    my @plugins;
	    if (grep /^spool$/, @node_capabilities) {
		    # XXX - use 5min, should keep a real spoolfetch timestamping
		    my $spoolfetch_last_timestamp = get_spoolfetch_timestamp($nodedesignation);
		    %whole_config = $self->uw_spoolfetch($spoolfetch_last_timestamp);

		    DEBUG "[DEBUG] whole_config:" . Dumper(\%whole_config);

		    # Gets the plugins from spoolfetch
		    # Only keep the first one, the others will be multigraph-fetched
		    @plugins = ( $whole_config{global}{multigraph}[0] ) ;
	    }

	    # Note: A multigraph plugin can present multiple services.
	    @plugins = $self->{node}->list_plugins() unless @plugins;

	    for my $plugin (@plugins) {
		if (%{$config->{limit_services}}) {
		    next unless $config->{limit_services}{$plugin};
		}

		DEBUG "[DEBUG] for my $plugin (@plugins)";

		# Ask for config only if spoolfetch didn't already send it
		my %service_config = %whole_config;
	        unless (%service_config) {
		       %service_config = $self->uw_fetch_service_config($plugin);
		}

		unless (%service_config) {
		    WARN "[WARNING] Service $plugin on $nodedesignation ".
			"returned no config";
		    next;
		}

		# Check if this plugin has already sent its data via a dirtyconfig
		# Note that spoolfetch also uses dirtyconfig
		my %service_data = $self->handle_dirty_config(\%service_config);
			
		# default is 0 sec : always update when asked
		my $update_rate = get_global_service_value(\%service_config, $plugin, "update_rate", 0); 
		my ($update_rate_in_seconds, $is_update_aligned) = parse_update_rate($update_rate);
		DEBUG "[DEBUG] update_rate $update_rate_in_seconds for $plugin on $nodedesignation";

		if (! %service_data) {
			# Check if this plugin has to be updated
			if ($update_rate_in_seconds 
				&& is_fresh_enough($nodedesignation, $plugin, $update_rate_in_seconds)) {
			    # It's fresh enough, skip this $service
			    DEBUG "[DEBUG] $plugin is fresh enough, not updating it";
			    next;
			}

			# __root__ is only a placeholder plugin for 
			# an empty spoolfetch so we should ignore it 
			# if asked to fetch it
			next if ($plugin eq "__root__");
			
			DEBUG "[DEBUG] No service data for $plugin, fetching it";
			%service_data = $self->{node}->fetch_service_data($plugin);
		}

		# If update_rate is aligned, round the "when" for alignement
		if ($is_update_aligned) {
			foreach my $service (keys %service_data) {
				my $current_service_data = $service_data{$service};
				foreach my $field (keys %$current_service_data) {
					my $whens = $current_service_data->{$field}->{when};
					for (my $i = 0; $i < scalar @$whens; $i ++) {
						my $when = $whens->[$i];
						my $rounded_when = round_to_granularity($when, $update_rate_in_seconds);
						$whens->[$i] = $rounded_when;
					}
				}
			}
		}


		# Since different plugins can populate multiple
		# positions in the service namespace we'll check for
		# collisions and warn of them.

		for my $service (keys %{$service_config{data_source}}) {
		    if (defined($all_service_configs{data_source}{$service})) {
			WARN "[WARNING] Service collision: plugin $plugin on "
			    ."$nodedesignation reports $service which already "
			    ."exists on that host.  Deleting new data.";
			delete($service_config{data_source}{$service});
		    delete($service_data{$service})
			if defined $service_data{$service};
		    }
		}

		# .extinfo fields come from "fetch" but must be saved
		# like "config".

		for my $service (keys %service_data) {
		    for my $ds (keys %{$service_data{$service}}) {
			my $extinfo = $service_data{$service}{$ds}{extinfo};
			if (defined $extinfo) {
			    $service_config{data_source}{$service}{$ds}{extinfo} =
				$extinfo;
			    DEBUG "[DEBUG] Copied extinfo $extinfo into "
				."service_config for $service / $ds on "
				.$nodedesignation;
			}
		    }
		}

		$self->_compare_and_act_on_config_changes(\%service_config);

		%{$all_service_configs{data_source}} = (
		    %{$all_service_configs{data_source}},
		    %{$service_config{data_source}});

		%{$all_service_configs{global}} = (
		    %{$all_service_configs{global}},
		    %{$service_config{global}});

		my $last_updated_timestamp = $self->_update_rrd_files(\%service_config, \%service_data);
          	set_spoolfetch_timestamp($nodedesignation, $last_updated_timestamp);
	    } # for @plugins
	}; # eval

	if ($EVAL_ERROR) {
	    ERROR "[ERROR] Error in node communication with $nodedesignation: "
		.$EVAL_ERROR;
	}

    }); # do_in_session

    munin_removelock($lock_file);

    # This handles failure in do_in_session,
    return undef if !$done;

    return {
        time_used => Time::HiRes::time - $update_time,
        service_configs => \%all_service_configs,
    }
}

sub get_global_service_value {
	my ($service_config, $service, $conf_field_name, $default) = @_;
	foreach my $array (@{$service_config->{global}{$service}}) {
		my ($field_name, $field_value) = @$array;
		if ($field_name eq $conf_field_name) {
			return $field_value;
		}
	}

	return $default;
}

sub is_fresh_enough {
	my ($nodedesignation, $service, $update_rate_in_seconds) = @_;

	my $key = "$nodedesignation/$service";
	DEBUG "is_fresh_enough asked for $key with a rate of $update_rate_in_seconds";

	my $db_file = $config->{dbdir} . "/last_updated.dic.txt";

	my %last_updated;

   	use Munin::Common::SyncDictFile;
   	tie(%last_updated, 'Munin::Common::SyncDictFile', $db_file) or ERROR "$!";

	my $last_updated_key = $last_updated{$key} || "0 0";
	DEBUG "last_updated{$key}: " . $last_updated_key;
	my @last = split(/ /, $last_updated_key);
   
	use Time::HiRes qw(gettimeofday tv_interval);	
	my $now = [ gettimeofday ];

	my $age = tv_interval(\@last, $now); 	
	DEBUG "last: " . Dumper(\@last) . ", now: " . Dumper($now) . ", age: $age";
	my $is_fresh_enough = ($age < $update_rate_in_seconds) ? 1 : 0;
	DEBUG "is_fresh_enough  $is_fresh_enough";

	if (! $is_fresh_enough) {
		DEBUG "new value: " . join(" ", @$now);
		$last_updated{$key} = join(" ", @$now);
	}

   	untie(%last_updated);

	return $is_fresh_enough;
}

sub get_spoolfetch_timestamp {
	my ($nodedesignation) = @_;

	my $key = "$nodedesignation/__spoolfetch__";
	my $db_file = $config->{dbdir} . "/last_updated.dic.txt";

	my %last_updated;

   	use Munin::Common::SyncDictFile;
   	tie(%last_updated, 'Munin::Common::SyncDictFile', $db_file) or ERROR "$!";

	my $last_updated_value = $last_updated{$key} || "0";

   	untie(%last_updated);

	return $last_updated_value;
}

sub set_spoolfetch_timestamp {
	my ($nodedesignation, $timestamp) = @_;

	my $key = "$nodedesignation/__spoolfetch__";
	my $db_file = $config->{dbdir} . "/last_updated.dic.txt";

	my %last_updated;

   	use Munin::Common::SyncDictFile;
   	tie(%last_updated, 'Munin::Common::SyncDictFile', $db_file) or ERROR "$!";

	$last_updated{$key} = time;

   	untie(%last_updated);
}

sub parse_update_rate {
	my ($update_rate_config) = @_;

	my ($is_update_aligned, $update_rate_in_sec);
	if ($update_rate_config =~ m/(\d+[a-z]?)( aligned)?/) {
		$update_rate_in_sec = to_sec($1);
		$is_update_aligned = $2;
	} else {
		return (0, 0);
	}

	return ($update_rate_in_sec, $is_update_aligned);
}

sub round_to_granularity {
	my ($when, $granularity_in_sec) = @_;
	$when = time if ($when eq "N"); # N means "now"

	my $rounded_when = $when - ($when % $granularity_in_sec);
	return $rounded_when;
}

sub handle_dirty_config {
	my ($self, $service_config) = @_;
	
	my %service_data;

	my $services = $service_config->{global}{multigraph};
	foreach my $service (@$services) {
		my $service_data_source = $service_config->{data_source}->{$service};
		foreach my $field (keys %$service_data_source) {
			my $field_value = $service_data_source->{$field}->{value};
			my $field_when = $service_data_source->{$field}->{when};

			# If value not present, this field is not dirty fetched
			next if (! defined $field_value);

			DEBUG "[DEBUG] handle_dirty_config:$service, $field, @$field_when";
			# Moves the "value" to the service_data
			$service_data{$service}->{$field} ||= { when => [], value => [], };
	                push @{$service_data{$service}{$field}{value}}, @$field_value;
			push @{$service_data{$service}{$field}{when}}, @$field_when;

			delete($service_data_source->{$field}{value});
			delete($service_data_source->{$field}{when});
		}
	}

	return %service_data;
}


sub uw_spoolfetch {
    my ($self, $timestamp) = @_;

    my %whole_config = $self->{node}->spoolfetch($timestamp);

    # munin.conf might override stuff
    foreach my $plugin (keys %whole_config) {
	    my $merged_config = $self->uw_override_with_conf($plugin, $whole_config{$plugin});
	    $whole_config{$plugin} = $merged_config;
    }

    return %whole_config;
}

sub uw_fetch_service_config {
    my ($self, $plugin) = @_;

    # Note, this can die for several reasons.  Caller must eval us.
    my %service_config = $self->{node}->fetch_service_config($plugin);
    my $merged_config = $self->uw_override_with_conf($plugin, \%service_config);

    return %$merged_config;
}

sub uw_override_with_conf {
    my ($self, $plugin, $service_config) = @_;

    if ($self->{host}{service_config} && 
	$self->{host}{service_config}{$plugin}) {

        my %merged_config = (%$service_config, %{$self->{host}{service_config}{$plugin}});
	$service_config = \%merged_config;
    }

    return $service_config;
}


sub _compare_and_act_on_config_changes {
    my ($self, $nested_service_config) = @_;

    # Kjellm: Why do we need to tune RRD files after upgrade?
    # Shouldn't we create a upgrade script or something instead?
    #
    # janl: Upgrade script sucks.  This way it's inline in munin and
    #  no need to remember anything or anything.

    my $just_upgraded = 0;

    my $old_config = Munin::Master::Config->instance()->{oldconfig};

    if (not defined $old_config->{version}
        or ($old_config->{version}
            ne $Munin::Common::Defaults::MUNIN_VERSION)) {
        $just_upgraded = 1;
    }

    for my $service (keys %{$nested_service_config->{data_source}}) {

        my $service_config = $nested_service_config->{data_source}{$service};

	for my $data_source (keys %{$service_config}) {
	    my $old_data_source = $data_source;
	    my $ds_config = $service_config->{$data_source};
	    $self->_set_rrd_data_source_defaults($ds_config);

	    my $group = $self->{host}{group}{group_name};
	    my $host = $self->{host}{host_name};

	    my $old_host_config = $old_config->{groups}{$group}{hosts}{$host};
	    my $old_ds_config = undef;

	    if ($old_host_config) {
		$old_ds_config =
		    $old_host_config->get_canned_ds_config($service,
							   $data_source);
	    }

	    if (defined($old_ds_config)
		and %$old_ds_config
		and defined($ds_config->{oldname})
		and $ds_config->{oldname}) {

		$old_data_source = $ds_config->{oldname};
		$old_ds_config =
		    $old_host_config->get_canned_ds_config($service,
							   $old_data_source);
	    }

	    if (defined($old_ds_config)
		and %$old_ds_config
		and not $self->_ds_config_eq($old_ds_config, $ds_config)) {
		$self->_ensure_filename($service,
					$old_data_source, $data_source,
					$old_ds_config, $ds_config)
		    and $self->_ensure_tuning($service, $data_source,
					      $ds_config);
		# _ensure_filename prints helpfull warnings in the log
	    } elsif ($just_upgraded) {
		$self->_ensure_tuning($service, $data_source,
				      $ds_config);
	    }
	}
    }
}


sub _ds_config_eq {
    my ($self, $old_ds_config, $ds_config) = @_;

    if (%$old_ds_config ne %$ds_config) {
        # Config keys differ:
        return '';
    }

    for my $key (%$old_ds_config) {
        if ((not defined($old_ds_config->{$key}))
            and not defined($ds_config->{$key})) {
            # Both keys undefined, look further:
            next;
        }

        if ((not defined($old_ds_config->{$key}))
            or not defined($ds_config->{$key})) {
            # One key undefined, but not both:
            return '';
        }

        if ($old_ds_config->{$key} ne $ds_config->{$key}) {
            # Config content differs:
            return '';
        }
    }

    return 1;
}


sub _ensure_filename {
    my ($self, $service, $old_data_source, $data_source,
        $old_ds_config, $ds_config) = @_;

    my $rrd_file = $self->_get_rrd_file_name($service, $data_source,
                                             $ds_config);
    my $old_rrd_file = $self->_get_rrd_file_name($service, $old_data_source,
                                                 $old_ds_config);

    my $hostspec = $self->{node}{host}.'/'.$self->{node}{address}.':'.
	$self->{node}{port};

    if ($rrd_file ne $old_rrd_file) {
        if (-f $old_rrd_file and -f $rrd_file) {
            my $host = $self->{host}{host_name};
            WARN "[WARNING]: $hostspec $service $data_source config change "
		. "suggests moving '$old_rrd_file' to '$rrd_file' "
		. "but both exist; manually merge the data "
                . "or remove whichever file you care less about.\n";
	    return '';
        } elsif (-f $old_rrd_file) {
            INFO "[INFO]: Config update, changing name of '$old_rrd_file'"
                   . " to '$rrd_file' on $hostspec ";
            unless (rename ($old_rrd_file, $rrd_file)) {
                ERROR "[ERROR]: Could not rename '$old_rrd_file' to"
		    . " '$rrd_file' for $hostspec: $!\n";
                return '';
            }
        }
    }

    return 1;
}


sub _ensure_tuning {
    my ($self, $service, $data_source, $ds_config) = @_;
    my $success = 1;

    my $rrd_file =
        $self->_get_rrd_file_name($service, $data_source,
                                  $ds_config);

    my %tune_flags = (type => '--data-source-type',
                      max => '--maximum',
                      min => '--minimum');

    for my $rrd_prop (qw(type max min)) {
        INFO "[INFO]: Config update, ensuring $rrd_prop of"
	    . " '$rrd_file' is '$ds_config->{$rrd_prop}'.\n";
        RRDs::tune($rrd_file, $tune_flags{$rrd_prop},
                   "42:$ds_config->{$rrd_prop}");
        if (my $tune_error = RRDs::error()) {
            ERROR "[ERROR] Tuning $rrd_prop of '$rrd_file' to"
		. " '$ds_config->{$rrd_prop}' failed.\n";
            $success = '';
        }
    }

    return $success;
}


sub _update_rrd_files {
    my ($self, $nested_service_config, $nested_service_data) = @_;

    my $nodedesignation = $self->{host}{host_name}."/".
	$self->{host}{address}.":".$self->{host}{port};

    my $last_timestamp = 0;

    for my $service (keys %{$nested_service_config->{data_source}}) {

	my $service_config = $nested_service_config->{data_source}{$service};
	my $service_data   = $nested_service_data->{$service};

	for my $ds_name (keys %{$service_config}) {
	    $self->_set_rrd_data_source_defaults($service_config->{$ds_name});
	    my $ds_config = $service_config->{$ds_name};

	    unless (defined($ds_config->{label})) {
		ERROR "[ERROR] Unable to update $service on $nodedesignation -> $ds_name: Missing data source configuration attribute: label";
		next;
	    }
	    
	    # Sets the DS resolution, searching in that order : 
	    # - per field 
	    # - per plugin
	    # - globally
            my $configref = $self->{node}{configref};
	    $ds_config->{graph_data_size} ||= $configref->{"$service.$ds_name.graph_data_size"};
	    $ds_config->{graph_data_size} ||= $configref->{"$service.graph_data_size"};
	    $ds_config->{graph_data_size} ||= $config->{graph_data_size};
            
	    $ds_config->{update_rate} ||= $configref->{"$service.$ds_name.update_rate"};
	    $ds_config->{update_rate} ||= $configref->{"$service.update_rate"};
	    $ds_config->{update_rate} ||= $config->{update_rate};
	    $ds_config->{update_rate} ||= 300; # default is 5 min

	    DEBUG "[DEBUG] asking for a rrd of size : " . $ds_config->{graph_data_size};
	    my $rrd_file = $self->_create_rrd_file_if_needed($service, $ds_name, $ds_config);

	    if (defined($service_data) and defined($service_data->{$ds_name})) {
		$last_timestamp = max($last_timestamp, $self->_update_rrd_file($rrd_file, $ds_name, $service_data->{$ds_name}));
	    }
	    else {
		WARN "[WARNING] Service $service on $nodedesignation returned no data for label $ds_name";
	    }
	}
    }

    return $last_timestamp;
}


sub _set_rrd_data_source_defaults {
    my ($self, $data_source) = @_;

    # Test for definedness, anything defined should not be overridden
    # by defaults:
    $data_source->{type} = 'GAUGE' unless defined($data_source->{type});
    $data_source->{min}  = 'U'     unless defined($data_source->{min});
    $data_source->{max}  = 'U'     unless defined($data_source->{max});
}


sub _create_rrd_file_if_needed {
    my ($self, $service, $ds_name, $ds_config) = @_;

    my $rrd_file = $self->_get_rrd_file_name($service, $ds_name, $ds_config);
    unless (-f $rrd_file) {
        $self->_create_rrd_file($rrd_file, $service, $ds_name, $ds_config);
    }

    return $rrd_file;
}


sub _get_rrd_file_name {
    my ($self, $service, $ds_name, $ds_config) = @_;
    
    my $type_id = lc(substr(($ds_config->{type}), 0, 1));

    my $path = $self->{host}->get_full_path;
    $path =~ s{[;:]}{/}g;

    # Multigraph/nested services will have . in the service name in this function.
    $service =~ s{\.}{-}g;

    # The following is rigged to match the corresponding function in
    # munin-graph/munin-html where it's less clear what are groups and
    # what are hosts and what are services, and they simply pop
    # elements off the end and so on.

    my $file = sprintf("%s-%s-%s-%s.rrd",
                       $path,
                       $service,
                       $ds_name,
                       $type_id);

    $file = File::Spec->catfile($config->{dbdir}, 
				$file);
	
    DEBUG "[DEBUG] rrd filename: $file\n";

    return $file;
}


sub _create_rrd_file {
    my ($self, $rrd_file, $service, $ds_name, $ds_config) = @_;

    INFO "[INFO] creating rrd-file for $service->$ds_name: '$rrd_file'";
    mkpath(dirname($rrd_file), {mode => oct(777)});
    my @args = (
        $rrd_file,
        sprintf('DS:42:%s:600:%s:%s', 
                $ds_config->{type}, $ds_config->{min}, $ds_config->{max}),
    );

    my $resolution = $ds_config->{graph_data_size};
    my $update_rate = $ds_config->{update_rate};
    if ($resolution eq 'normal') {
        push (@args,
              "RRA:AVERAGE:0.5:1:576",   # resolution 5 minutes
              "RRA:MIN:0.5:1:576",
              "RRA:MAX:0.5:1:576",
              "RRA:AVERAGE:0.5:6:432",   # 9 days, resolution 30 minutes
              "RRA:MIN:0.5:6:432",
              "RRA:MAX:0.5:6:432",
              "RRA:AVERAGE:0.5:24:540",  # 45 days, resolution 2 hours
              "RRA:MIN:0.5:24:540",
              "RRA:MAX:0.5:24:540",
              "RRA:AVERAGE:0.5:288:450", # 450 days, resolution 1 day
              "RRA:MIN:0.5:288:450",
              "RRA:MAX:0.5:288:450");
    } 
    elsif ($resolution eq 'huge') {
        push (@args, 
              "RRA:AVERAGE:0.5:1:115200",  # resolution 5 minutes, for 400 days
              "RRA:MIN:0.5:1:115200",
              "RRA:MAX:0.5:1:115200"); 
    } elsif ($resolution =~ /^custom (.+)/) {
        # Parsing resolution to achieve computer format as defined on the RFC :
        # FULL_NB, MULTIPLIER_1 MULTIPLIER_1_NB, ... MULTIPLIER_NMULTIPLIER_N_NB 
        my @resolutions_computer = parse_custom_resolution($1, $update_rate);
        foreach my $resolution_computer(@resolutions_computer) {
            my ($multiplier, $multiplier_nb) = @{$resolution_computer};
	    # Always add 10% to the RRA size, as specified in 
	    # http://munin.projects.linpro.no/wiki/format-graph_data_size
	    $multiplier_nb += int ($multiplier_nb / 10) || 1;
            push (@args, 
                "RRA:AVERAGE:0.5:$multiplier:$multiplier_nb",
                "RRA:MIN:0.5:$multiplier:$multiplier_nb",
                "RRA:MAX:0.5:$multiplier:$multiplier_nb"
            ); 
        }
    }
    DEBUG "[DEBUG] RRDs::create @args";
    RRDs::create @args;
    if (my $ERROR = RRDs::error) {
        ERROR "[ERROR] Unable to create '$rrd_file': $ERROR";
    }
}

sub parse_custom_resolution {
	my @elems = split(',\s*', shift);
	my $update_rate = shift;

	DEBUG "[DEBUG] update_rate: $update_rate";

        my @computer_format;

	# First element is always the full resoltion, converting to computer format
	my $full_res = shift @elems; 
	unshift @elems, "$update_rate for $full_res";

        foreach my $elem (@elems) {
                if ($elem =~ m/(\d+) (\d+)/) {
                        # nothing to do, already in computer format
                        push @computer_format, [$1, $2];
                } elsif ($elem =~ m/(\w+) for (\w+)/) {
                        my $nb_sec = to_sec($1);
                        my $for_sec = to_sec($2);
                        
			my $multiplier = int ($nb_sec / $update_rate);
                        my $multiplier_nb = int ($for_sec / $nb_sec);

			DEBUG "[DEBUG] $elem"
				. " -> nb_sec:$nb_sec, for_sec:$for_sec"
				. " -> multiplier:$multiplier, multiplier_nb:$multiplier_nb"
			;
                        push @computer_format, [$multiplier, $multiplier_nb];
                }
	}

        return @computer_format;
}

# return the number of seconds 
# for the human readable format
# s : second,  m : minute, h : hour
# d : day, w : week, t : month, y : year
sub to_sec {
	my $secs_table = {
		"s" => 1,
		"m" => 60,
		"h" => 60 * 60,
		"d" => 60 * 60 * 24,
		"w" => 60 * 60 * 24 * 7,
		"t" => 60 * 60 * 24 * 31, # a month always has 31 days
		"y" => 60 * 60 * 24 * 365, # a year always has 365 days 
	};

	my ($target) = @_;
	if ($target =~ m/(\d+)([smhdwty])/i) {
		return $1 * $secs_table->{$2};	
	} else {
		# no recognised unit, return the int value as seconds
		return int $target;
	}
}

sub to_mul {
	my ($base, $target) = @_;
	my $target_sec = to_sec($target);
	if ($target %% $base != 0) {
		return 0;
	}

	return round($target / $base); 
}

sub to_mul_nb {
	my ($base, $target) = @_;
	my $target_sec = to_sec($target);
	if ($target %% $base != 0) {
		return 0;
	}
}

sub _update_rrd_file {
    my ($self, $rrd_file, $ds_name, $ds_values) = @_;

    my $values = $ds_values->{value};

    # Some kind of mismatch between fetch and config can cause this.
    return if !defined($values);  

    my $last_updated_timestamp = 0;
    my @update_rrd_data;
    for (my $i = 0; $i < scalar @$values; $i++) { 
        my $value = $values->[$i];
        my $when = $ds_values->{when}[$i];

        if ($value =~ /\d[Ee]([+-]?\d+)$/) {
            # Looks like scientific format.  RRDtool does not
            # like it so we convert it.
            my $magnitude = $1;
            if ($magnitude < 0) {
                # Preserve at least 4 significant digits
                $magnitude = abs($magnitude) + 4;
                $value = sprintf("%.*f", $magnitude, $value);
            } else {
                $value = sprintf("%.4f", $value);
            }
        }
        
        # Schedule for addition
        push @update_rrd_data, "$when:$value";

	$last_updated_timestamp = max($last_updated_timestamp, $when);
    }

    DEBUG "[DEBUG] Updating $rrd_file with @update_rrd_data";
    RRDs::update($rrd_file, @update_rrd_data);
    if (my $ERROR = RRDs::error) {
        #confess Dumper @_;
        ERROR "[ERROR] In RRD: Error updating $rrd_file: $ERROR";
    }

    return $last_updated_timestamp;
}

sub dump_to_file
{
	my ($filename, $obj) = @_;
	open(DUMPFILE, ">> $filename");

	use Data::Dumper;
	print DUMPFILE Dumper($obj);

	close(DUMPFILE);
}

1;


__END__

=head1 NAME

Munin::Master::UpdateWorker - FIX

=head1 SYNOPSIS

FIX

=head1 METHODS

=over

=item B<new>

FIX

=item B<do_work>

FIX

=back

=head1 COPYING

Copyright (C) 2002-2009  Jimmy Olsen, et al.

  This program is free software; you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation; version 2 dated June, 1991.

  This program is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with this program; if not, write to the Free Software
  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA


