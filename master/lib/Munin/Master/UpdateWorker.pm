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

	    $self->{node}->negotiate_capabilities();
	    # Note: A multigraph plugin can present multiple services.
	    my @plugins =  $self->{node}->list_plugins();

	    for my $plugin (@plugins) {
		if (%{$config->{limit_services}}) {
		    next unless $config->{limit_services}{$plugin};
		}

		my %service_config = $self->uw_fetch_service_config($plugin);
		unless (%service_config) {
		    WARN "[WARNING] Service $plugin on $nodedesignation ".
			"returned no config";
		    next;
		}

		my %service_data = $self->{node}->fetch_service_data($plugin);

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

		$self->_update_rrd_files(\%service_config, \%service_data);

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


sub uw_fetch_service_config {
    my ($self, $plugin) = @_;

    # Note, this can die for several reasons.  Caller must eval us.
    my %service_config = $self->{node}->fetch_service_config($plugin);

    if ($self->{host}{service_config} && 
	$self->{host}{service_config}{$plugin}) {

        %service_config
            = (%service_config, %{$self->{host}{service_config}{$plugin}});

    }

    return %service_config;
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

    for my $service (keys %{$nested_service_config->{data_source}}) {

	my $service_config = $nested_service_config->{data_source}{$service};
	my $service_data   = $nested_service_data->{$service};

	for my $ds_name (keys %{$service_config}) {
	    $self->_set_rrd_data_source_defaults($service_config->{$ds_name});

	    unless (defined($service_config->{$ds_name}{label})) {
		ERROR "[ERROR] Unable to update $service on $nodedesignation -> $ds_name: Missing data source configuration attribute: label";
		next;
	    }

	    my $rrd_file 
		= $self->_create_rrd_file_if_needed($service, $ds_name, 
						    $service_config->{$ds_name});

	    if (defined($service_data) and defined($service_data->{$ds_name})) {
		$self->_update_rrd_file($rrd_file, $ds_name, $service_data->{$ds_name});
	    }
	    else {
		WARN "[WARNING] Service $service on $nodedesignation returned no data for label $ds_name";
	    }
	}
    }
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
	
    DEBUG "[DEBUG] Made rrd filename: $file\n";

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
            
    my $resolution = $config->{graph_data_size};
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
    }
    RRDs::create @args;
    if (my $ERROR = RRDs::error) {
        ERROR "[ERROR] Unable to create '$rrd_file': $ERROR";
    }
}


sub _update_rrd_file {
    my ($self, $rrd_file, $ds_name, $ds_values) = @_;

    my $value = $ds_values->{value};

    # Some kind of mismatch between fetch and config can cause this.
    return if !defined($value);  

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

    DEBUG "[DEBUG] Updating $rrd_file with ".$ds_values->{when}.":$value";
    RRDs::update($rrd_file, "$ds_values->{when}:$value");
    if (my $ERROR = RRDs::error) {
	#confess Dumper @_;
        ERROR "[ERROR] In RRD: Error updating $rrd_file: $ERROR";
    }
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


