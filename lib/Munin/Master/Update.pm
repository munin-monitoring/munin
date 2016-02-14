package Munin::Master::Update;


use warnings;
use strict;

use English qw(-no_match_vars);
use Carp;

use Time::HiRes;
use Munin::Common::Logger;
use List::Util qw( shuffle );

use Munin::Common::Defaults;
use Munin::Master::Config;
use Munin::Master::UpdateWorker;
use Munin::Master::ProcessManager;
use Munin::Master::Utils;

my $config = Munin::Master::Config->instance()->{config};

sub new {
    my ($class) = @_;

    # This steals the groups from the master instance of the config.
    my $gah = $config->get_groups_and_hosts();

    my $self = bless {
        STATS               => undef,
        old_service_configs => {},
        old_version         => undef,
        service_configs     => {},
        workers             => [],
        failed_workers      => [],
        group_repository    => Munin::Master::GroupRepository->new($gah),
        config_dump_file    => "$config->{dbdir}/datafile",
    }, $class;
}


sub run {
    my ($self) = @_;

    $self->_create_rundir_if_missing();

    $self->_do_with_lock_and_timing(sub {
        INFO "[INFO]: Starting munin-update";

        $self->{old_service_configs} = $self->_read_old_service_configs();

        $self->{workers} = $self->_create_workers();
        $self->_run_workers();

	# I wonder if the following should really be done with timing. - janl
        $self->_write_new_service_configs();
    });
}


sub _read_old_service_configs {

    # Read the datafile containing old configurations.  This should
    # not fail in case of problems with the file.  In such a case the
    # file should simply be ingored and a new one written.  Lets hope
    # it does not repeat itself then.

    my ($self) = @_;

    # Get old service configuration from the config instance since the
    # syntaxes are identical.
    my $oldconfig = Munin::Master::Config->instance()->{oldconfig};

    my $datafile = $oldconfig->{config_file} = $config->{dbdir}.'/datafile';

    $oldconfig = bless( munin_read_storable("$datafile.storable", $oldconfig), "Munin::Master::Config");

    return $oldconfig;
}


sub _create_rundir_if_missing {
    my ($self) = @_;

    unless (-d $config->{rundir}) {
	mkdir $config->{rundir}, oct(700)
            or croak "Failed to create rundir (".$config->{rundir}."): $!";

    }
}


sub _create_workers {
    my ($self) = @_;

    my @hosts = $self->{group_repository}->get_all_hosts();

    # Shuffle @hosts to avoid always having the same ordering
    # XXX - It might be best to preorder them on the TIMETAKEN ASC
    #       in order that statisticall fast hosts are done first to increase
    #       the global throughtput
    @hosts = shuffle(@hosts);

    if (%{$config->{limit_hosts}}) {
        @hosts = grep { $config->{limit_hosts}{$_->{host_name}} } @hosts
    }

    @hosts = grep { $_->{update} } @hosts;

    return [ map { Munin::Master::UpdateWorker->new($_) } @hosts ];
}


sub _do_with_lock_and_timing {
    my ($self, $block) = @_;

    my $lock = "$config->{rundir}/munin-update.lock";
    munin_runlock($lock);

    my $update_time = Time::HiRes::time;
    if (!open ($self->{STATS}, '>', "$config->{dbdir}/munin-update.stats.tmp")) {
        WARN "[WARNING] Could not open STATS to $config->{dbdir}/munin-update.stats.tmp: $!";
        # Use /dev/null instead - if the admin won't fix he won't care
        open($self->{STATS}, '>', "/dev/null") or 
	    LOGCROAK "[FATAL] Could not open STATS to /dev/null (fallback for not being able to open $config->{dbdir}/munin-update.stats.tmp): $!";
    }

    # Place global munin-update timeout here.
    my $retval = $block->();

    $update_time = sprintf("%.2f", (Time::HiRes::time - $update_time));
    print { $self->{STATS} } "UT|$update_time\n";
    close ($self->{STATS});
    $self->{STATS} = undef;
    rename ("$config->{dbdir}/munin-update.stats.tmp", "$config->{dbdir}/munin-update.stats");
    INFO "[INFO]: Munin-update finished ($update_time sec)";

    munin_removelock($lock);

    return $retval;
}


sub _run_workers {
    my ($self) = @_;

    if ($config->{fork}) {
        my $pm = Munin::Master::ProcessManager
            ->new($self->_create_self_aware_worker_result_handler(),
                  $self->_create_self_aware_worker_exception_handler());
        $pm->add_workers(@{$self->{workers}});
        $pm->start_work();
    }
    else {
        for my $worker (@{$self->{workers}}) {

	    my $res ;

	    eval {
		# do_work fails hard on a number of conditions
		$res = $worker->do_work();
	    };

	    $res=undef if $EVAL_ERROR;

	    my $worker_id = $worker->{ID};
	    if (defined($res)) {
		$self->_handle_worker_result([$worker_id, $res]);
	    } else {
		# Need to handle connection failure same as other
		# failures.  do_connect fails softly.
		WARN "[WARNING] Failed worker ".$worker_id."\n";
		push @{$self->{failed_workers}}, $worker_id;
	    }
        }
    }
}


sub _create_self_aware_worker_result_handler {
    my ($self) = @_;

    return sub { $self->_handle_worker_result(@_); };
}


sub _handle_worker_result {
    my ($self, $res) = @_;

    if (!defined($res)) {
	# no result? problem
	LOGCROAK("[FATAL] Handle_worker_result got handed a failed worker result");
    }

    my ($worker_id, $time_used, $service_configs) 
        = ($res->[0], $res->[1]{time_used}, $res->[1]{service_configs});

    my $update_time = sprintf("%.2f", $time_used);
    INFO "[INFO]: Munin-update finished for node $worker_id ($update_time sec)";
    if (! defined $self->{STATS} ) {
	# This is may only be the case when we get connection refused
	ERROR "[BUG!] Did not collect any stats for $worker_id.  If this message appears in your logs a lot please email munin-users.  Thanks.";
    } else {
	printf { $self->{STATS} } "UD|%s|%.2f\n", $worker_id, $time_used;
    }

    $self->{service_configs}{$worker_id} = $service_configs;
}


sub _create_self_aware_worker_exception_handler {
    my ($self) = @_;

    return sub {
        my ($worker, $reason) = @_;
	my $worker_id = $worker->{ID};
	DEBUG "[DEBUG] In exception handler for failed worker $worker_id";
        push @{$self->{failed_workers}}, $worker_id;
    };
}

sub _get_order {
	my ($key, $array_as_string) = @_;
	my @array = split(/ +/, $array_as_string);
	for(my $idx = 0; $idx < scalar @array; $idx++) {
		my ($a, $b) = split(/=/, $array[$idx], 2);
		if ($a eq $key) { return $idx; }
	}

	# Not found
	return scalar @array;
}

sub _get_alias {
	my ($key, $array_as_string) = @_;
	my @array = split(/ +/, $array_as_string);
	for(my $idx = 0; $idx < scalar @array; $idx++) {
		my ($a, $b) = split(/=/, $array[$idx], 2);
		if ($a eq $key) { return $b; }
	}

	# Not found
	return undef;
}

sub _get_last_insert_id {
	my ($dbh) = @_;
	return $dbh->last_insert_id("", "", "", "");
}

sub _get_url_from_path {
	my ($path) = @_;
	$path =~ tr,;:,//,;
	return $path;
}

sub _dump_conf_node_into_sql {
	my ($node, $grp_id, $path, $dbh, $sth_node, $sth_node_attr,
		$sth_service, $sth_service_attr,
		$sth_service_category,
		$sth_ds, $sth_ds_attr,
		$sth_url) = @_;

	my $node_name = $node->{host_name};
	my $node_path = "$path;$node_name";
	$sth_node->execute($grp_id, $node_name, $node_path);

	my $node_id = _get_last_insert_id($dbh);

	$sth_url->execute($node_id, "node", _get_url_from_path($node_path));

	# Save the ID inside the datastructure.
	# It is used to attach the node w/o doing an extra select
	$node->{ID} = $node_id;

	# Look for custom graphs
	# XXX Hopefully no one overrides the graph titles of plugins
	my @services = grep { /\.graph_title$/ } keys %$node;
	for my $service (@services) {
		$service = substr $service, 0, -12;

		# Insert graph
		$sth_service->execute($node_id, $service, "$node_path:$service");
		my $service_id = _get_last_insert_id($dbh);

		# Replace '.' delimiter in graph name to '/' for URLs
		# See comments in _dump_into_sql for why
		(my $_service = $service) =~ tr!.!/!;
		$sth_url->execute($service_id, "service", _get_url_from_path("$node_path:$_service"));

		# Keep track of field ids
		my %ds_ids;

		# Look for matching graph settings
		for my $attr (grep { /^$service\./ } keys %$node) {
			my $value = $node->{$attr};
			my $field = substr $attr, length($service) + 1;
			my @args = split /\./, $field;

			if (1 == scalar @args) {
				# graph config

				# Category names should not be case sensitive. Store them all in lowercase.
				if ($attr->[0] eq 'graph_category') {
						$attr->[1] = lc($attr->[1]);
						$sth_service_category->execute($service_id, $attr->[1]);
				} else {
						$sth_service_attr->execute($service_id, $args[0], $value);
				}
			} elsif (2 == scalar @args) {
				# field config
				my $data_source = $args[0];
				my $ds_id = $ds_ids{$data_source};

				if (!defined $ds_id) {
					$sth_ds->execute($service_id, $data_source, "$node_path:$service.$data_source");
					$ds_id = _get_last_insert_id($dbh);
					$ds_ids{$data_source} = $ds_id;
					$sth_url->execute($ds_id, "ds", _get_url_from_path("$node_path:$_service:$data_source"));
				}

				$sth_ds_attr->execute($ds_id, $args[1], $value);
			} else {
				# XXX what's left?
			}
		}
	}
}

sub _dump_groups_into_sql {
	my ($groups, $p_id, $path, $dbh, $sth_grp,
		$sth_node, $sth_node_attr,
		$sth_service, $sth_service_attr,
		$sth_service_category,
		$sth_ds, $sth_ds_attr,
		$sth_url) = @_;

	for my $grp_name (keys %$groups) {
		my $grp_path = ($path eq "") ? $grp_name : "$path;$grp_name";
		$sth_grp->execute($grp_name, $p_id, $grp_path);

		my $id = _get_last_insert_id($dbh);

		# Save the ID inside the datastructure.
		# It is used to attach the node w/o doing an extra select
		$groups->{$grp_name}{ID} = $id;

		my $url = _get_url_from_path($grp_path);
		$sth_url->execute($id, "group", $url);

		for my $node (values %{$groups->{$grp_name}{hosts}}) {
			_dump_conf_node_into_sql($node, $id, $grp_path, $dbh,
				$sth_node, $sth_node_attr,
				$sth_service, $sth_service_attr,
				$sth_service_category,
				$sth_ds, $sth_ds_attr,
				$sth_url);
		}

		_dump_groups_into_sql($groups->{$grp_name}{groups}, $id, $grp_path, $dbh,
			$sth_grp,
			$sth_node, $sth_node_attr,
			$sth_service, $sth_service_attr,
			$sth_service_category,
			$sth_ds, $sth_ds_attr,
			$sth_url);
	}
}

sub _dump_into_sql {
	my ($self) = @_;

	my $datafilename = $ENV{MUNIN_DBURL} || $config->{dbdir}."/datafile.sqlite";
	my $datafilename_tmp = $datafilename . ".$$";
	DEBUG "[DEBUG] Writing sql to $datafilename_tmp";

	use DBI;
	my $dbh = DBI->connect("dbi:SQLite:dbname=$datafilename_tmp","","") or die $DBI::errstr;

	# We still use the temp file trick
	$dbh->do("PRAGMA synchronous = 0");
	$dbh->do("PRAGMA journal_mode = OFF");

	# Create DB
	$dbh->do("CREATE TABLE IF NOT EXISTS param (name VARCHAR PRIMARY KEY, value VARCHAR)");
	my $sth_param = $dbh->prepare('INSERT INTO param (name, value) VALUES (?, ?)');

	$dbh->do("CREATE TABLE IF NOT EXISTS grp (id INTEGER PRIMARY KEY, p_id INTEGER REFERENCES grp(id), name VARCHAR, path VARCHAR)");
	$dbh->do("CREATE INDEX IF NOT EXISTS r_g_grp ON grp (p_id)");
	my $sth_grp = $dbh->prepare('INSERT INTO grp (name, p_id, path) VALUES (?, ?, ?)');

	$dbh->do("CREATE TABLE IF NOT EXISTS node (id INTEGER PRIMARY KEY, grp_id INTEGER REFERENCES grp(id), name VARCHAR, path VARCHAR)");
	$dbh->do("CREATE TABLE IF NOT EXISTS node_attr (id INTEGER REFERENCES node(id), name VARCHAR, value VARCHAR)");
	$dbh->do("CREATE UNIQUE INDEX IF NOT EXISTS pk_node_attr ON node_attr (id, name)");
	$dbh->do("CREATE INDEX IF NOT EXISTS r_n_grp ON node (grp_id)");
	my $sth_node = $dbh->prepare('INSERT INTO node (grp_id, name, path) VALUES (?, ?, ?)');
	my $sth_node_attr = $dbh->prepare('INSERT INTO node_attr (id, name, value) VALUES (?, ?, ?)');

	$dbh->do("CREATE TABLE IF NOT EXISTS service (id INTEGER PRIMARY KEY, node_id INTEGER REFERENCES node(id), name VARCHAR, path VARCHAR, service_title VARCHAR, graph_info VARCHAR, subgraphs INTEGER)");
	$dbh->do("CREATE TABLE IF NOT EXISTS service_attr (id INTEGER REFERENCES service(id), name VARCHAR, value VARCHAR)");
	$dbh->do("CREATE UNIQUE INDEX IF NOT EXISTS pk_service_attr ON service_attr (id, name)");
	$dbh->do("CREATE INDEX IF NOT EXISTS r_s_node ON service (node_id)");
	my $sth_service = $dbh->prepare('INSERT INTO service (node_id, name, path, service_title, graph_info, subgraphs) VALUES (?, ?, ?, ?, ?, ?)');
	my $sth_service_attr = $dbh->prepare('INSERT INTO service_attr (id, name, value) VALUES (?, ?, ?)');
	$dbh->do("CREATE TABLE IF NOT EXISTS service_categories (id INTEGER REFERENCES service(id), category VARCHAR NOT NULL, PRIMARY KEY (id,category))");
	my $sth_service_category = $dbh->prepare('INSERT INTO service_categories (id, category) VALUES (?, ?)');

	$dbh->do("CREATE TABLE IF NOT EXISTS ds (id INTEGER PRIMARY KEY, service_id INTEGER REFERENCES service(id), name VARCHAR, path VARCHAR,
		type VARCHAR DEFAULT 'GAUGE',
		ordr INTEGER DEFAULT 0,
		unknown INTEGER DEFAULT 0, warning INTEGER DEFAULT 0, critical INTEGER DEFAULT 0)");
	$dbh->do("CREATE TABLE IF NOT EXISTS ds_attr (id INTEGER REFERENCES ds(id), name VARCHAR, value VARCHAR)");
	$dbh->do("CREATE UNIQUE INDEX IF NOT EXISTS pk_ds_attr ON ds_attr (id, name)");
	$dbh->do("CREATE INDEX IF NOT EXISTS r_d_service ON ds (service_id)");
	my $sth_ds = $dbh->prepare('INSERT INTO ds (service_id, name, path, ordr) VALUES (?, ?, ?, ?)');
	my $sth_ds_attr = $dbh->prepare('INSERT INTO ds_attr (id, name, value) VALUES (?, ?, ?)');
	my $sth_ds_type = $dbh->prepare('UPDATE ds SET type = ? where id = ?');

	# Table that contains all the URL paths, in order to have a very fast lookup
	$dbh->do("CREATE TABLE IF NOT EXISTS url (id INTEGER NOT NULL, type VARCHAR NOT NULL, path VARCHAR NOT NULL, PRIMARY KEY(id,type))");
	$dbh->do("CREATE UNIQUE INDEX IF NOT EXISTS u_url_path ON url (path)");
	my $sth_url = $dbh->prepare('INSERT INTO url (id, type, path) VALUES (?, ?, ?)');
	$sth_url->{RaiseError} = 1;

	# Table that contains all the states for the various plugins.
	# This is the table that should get queried for the last/previous
	# values, along with a precomputed alarm state (UNKNOWN, NORMAL,
	# WARNING, CRITICAL)
	#
	# Note, this table is referenced by composite key (type,id) in order to be
	# able to have any kind of states. Such as whole node states for example.
	$dbh->do("CREATE TABLE IF NOT EXISTS state (id INTEGER, type VARCHAR,
		last_epoch INTEGER, last_value VARCHAR,
		prev_epoch INTEGER, prev_value VARCHAR,
		alarm VARCHAR, num_unknowns INTEGER
		)");
	$dbh->do("CREATE UNIQUE INDEX IF NOT EXISTS pk_state ON state (type, id)");
	my $sth_state = $dbh->prepare('INSERT INTO state (id, type, last_epoch, last_value, prev_epoch, prev_value) VALUES (?, ?, ?, ?, ?, ?)');
	$sth_state->{RaiseError} = 1;


	# Configuration
	$config->{version} = $Munin::Common::Defaults::MUNIN_VERSION;
	for my $key (keys %$config) {
		next if ref $config->{$key};
		$sth_param->execute($key, $config->{$key});
	}

	# Recursively create groups
	_dump_groups_into_sql($self->{group_repository}{groups}, undef, "", $dbh,
		$sth_grp,
		$sth_node, $sth_node_attr,
		$sth_service, $sth_service_attr,
		$sth_service_category,
		$sth_ds, $sth_ds_attr,
		$sth_url);

	for my $worker (@{$self->{workers}}) {
		my $host = $worker->{ID};
		my $node = $worker->{node};
		my $grp_id = $worker->{host}->{group}->{ID};
		my $node_id = $worker->{host}->{ID};
		my $url = _get_url_from_path($host);

		if (!defined $node_id) {
			$sth_node->execute($grp_id, $node->{host}, $host);
			$node_id = _get_last_insert_id($dbh);
			$sth_url->execute($node_id, "node", $url);
		}

		for my $attr (keys %$node) {
			# Ignore the configref key, as it is redundant
			next if $attr eq "configref";

			$sth_node_attr->execute($node_id, $attr, munin_dumpconfig_as_str($node->{$attr}));
		}

		# Insert the state of each plugin
		# Reading the state file
		# Beware, that part is ugly, yet best is still coming.
		my $path = $url; $path =~ s/\.html$//; $path =~ s/\//-/g;
		my $state_file = sprintf ('%s/state-%s.storable', $config->{dbdir}, $path);
		DEBUG "[DEBUG] Reading state for $path in $state_file (Dumping)";
		my $state = munin_read_storable($state_file) || {};

		for my $service (keys %{$self->{service_configs}{$host}{data_source}}) {
			# Static HTML and graphs (both static and CGI) use forward slashes ('/')
			# as the separator for urls of multigraph graph nodes, like:
			#
			#    http://host/munin/DOMAIN/HOST/diskstats_iops/sda.html
			#
			# However the internal representation uses dots ('.'), like: diskstats_iops.sda
			# Here we map the names of the service or graph name to the correct url,
			# to make it easier for CGI html to work with.
			(my $_service = $service) =~ tr!.!/!;

			my $graph_title = _get_from_arrayref($self->{service_configs}{$host}{global}{$service}, "graph_title");
			my $graph_info = _get_from_arrayref($self->{service_configs}{$host}{global}{$service}, "graph_info");
			# Check for multigraphs
			my $subgraphs = scalar grep /^$service\..+/, keys %{$self->{service_configs}{$host}{data_source}};
			$sth_service->execute($node_id, $service, "$host:$service", $graph_title, $graph_info, $subgraphs);
			my $service_id = _get_last_insert_id($dbh);
			$sth_url->execute($service_id, "service", _get_url_from_path("$host:$_service"));

			my $is_category_set;
			my $graph_order;
			for my $attr (@{$self->{service_configs}{$host}{global}{$service}}) {
				my ($attr_key, $attr_value) = @$attr;
				# Category names should not be case sensitive. Store them all in lowercase.
				if ($attr_key eq 'graph_category') {
					$attr_value = lc($attr_value);
					$sth_service_category->execute($service_id, $attr_value);
					$is_category_set = 1;
				} else {
					$sth_service_attr->execute($service_id, $attr_key, $attr_value);
				}

				# Extract special vars
				if ($attr_key eq 'graph_order') {
					$graph_order = $attr_value;
				}
			}

			# Set the default category : "other"
			if ( ! $is_category_set ) {
				INFO "Setting $service with category 'other'";
				$sth_service_category->execute($service_id, "other") unless $is_category_set;
			}

			for my $data_source (keys %{$self->{service_configs}{$host}{data_source}{$service}}) {
				my $order = _get_order($data_source, $graph_order);
				$sth_ds->execute($service_id, $data_source, "$host:$service.$data_source", $order);
				my $ds_id = _get_last_insert_id($dbh);
				$sth_url->execute($ds_id, "ds", _get_url_from_path("$host:$_service:$data_source"));

				my $ds_type;
				my $gfx_color;
				my $cdef;
				for my $attr (keys %{$self->{service_configs}{$host}{data_source}{$service}{$data_source}}) {
					my $value = $self->{service_configs}{$host}{data_source}{$service}{$data_source}{$attr};
					$sth_ds_attr->execute($ds_id, $attr, $value);

					$ds_type = uc($value) if $attr eq "type";
					$gfx_color = $value if $attr eq "colour";
					$cdef = $value if $attr eq "cdef";
				}

				my $alias = _get_alias($data_source, $graph_order);

				# Clean ds_type
				$ds_type = "GAUGE" unless $ds_type && $ds_type =~ /^(DERIVE|COUNTER|ABSOLUTE)$/;

				# Update the DS type. Could be done beforehand,
				# but we don't really care about perf yet
				$sth_ds_type->execute($ds_type, $ds_id);

				my $service_filename = $service; $service_filename =~ s/\./-/g;
				my $rrdfile_prefix = $config->{dbdir} . "/$url-$service_filename-$data_source";

				my $rrd_file_type = lc(substr($ds_type, 0, 1));
				my $rrd_file = "$rrdfile_prefix-$rrd_file_type.rrd";
				my $rrd_field = "42"; # TODO - This could be overriden

				# Insert RRD specific attributes
				$sth_ds_attr->execute($ds_id, "rrd:file", $rrd_file);
				$sth_ds_attr->execute($ds_id, "rrd:field", $rrd_field);
				$sth_ds_attr->execute($ds_id, "rrd:cdef", $cdef) if $cdef;
				$sth_ds_attr->execute($ds_id, "rrd:alias", $alias) if $alias;

				$sth_ds_attr->execute($ds_id, "gfx:color", $gfx_color) if $gfx_color;

				# Get the states for the DS
				my $state_ds = $state->{value}{"$rrd_file:$rrd_field"};

				INFO "No state found for ds $ds_id ($rrdfile_prefix)" unless $state_ds;
				next unless $state_ds;

				$sth_state->execute($ds_id, "ds", @{ $state_ds->{current} }, @{ $state_ds->{previous} }, );
			}
		}
	}

	# Close DB
	$dbh->disconnect();

	# Move into place
	rename($datafilename_tmp, $datafilename);
}

sub _write_new_service_configs {
    my ($self) = @_;
    my $datafile_hash = {};

    $datafile_hash->{version} = $Munin::Common::Defaults::MUNIN_VERSION;

    $self->_print_service_configs_for_not_updated_services($datafile_hash);
    $self->_print_old_service_configs_for_failed_workers($datafile_hash);

    $self->_dump_into_sql();

    for my $host (keys %{$self->{service_configs}}) {
        for my $service (keys %{$self->{service_configs}{$host}{data_source}}) {
            for my $attr (@{$self->{service_configs}{$host}{global}{$service}}) {
                munin_set_var_path($datafile_hash, "$host:$service.$attr->[0]", $attr->[1]);
            }
            for my $data_source (keys %{$self->{service_configs}{$host}{data_source}{$service}}) {
                for my $attr (keys %{$self->{service_configs}{$host}{data_source}{$service}{$data_source}}) {
                    munin_set_var_path($datafile_hash, "$host:$service.$data_source.$attr", $self->{service_configs}{$host}{data_source}{$service}{$data_source}{$attr});
                }
            }
        }
    }

    # Also write the binary (Storable) version
    munin_writeconfig_storable($config->{dbdir}.'/datafile.storable', $datafile_hash);
}


sub _print_service_configs_for_not_updated_services {
    my ($self, $datafile_hash) = @_;

    my @hosts = $self->{group_repository}->get_all_hosts();

    for my $workerdata (@hosts) {
        my $worker = $workerdata->get_full_path();

        my @data = grep { /\.update$/ and !$workerdata->{$_} } keys %$workerdata;
        for my $match (@data) {
            my $prefix = substr $match, 0, -6;

            for my $datum (grep { /^\Q$prefix\E/ } keys %$workerdata) {
                munin_set_var_path($datafile_hash, $worker . ":". $datum, $workerdata->{$datum});
            }

        }

    }
}


sub _print_old_service_configs_for_failed_workers {
    my ($self, $datafile_hash) = @_;

    for my $worker (@{$self->{failed_workers}}) {
	# The empty set contains "undef" it seems
	next if !defined($worker);  

	my $workerdata = $self->{old_service_configs}->look_up($worker);

	# No data available on the failed worker
	if (!defined($workerdata)) {
	    INFO "[INFO] No old data available for failed worker $worker.  This node will disappear from the html web page hierarchy\n";
	    next;
	}
	
	for my $datum (keys %$workerdata) {
	    # Skip some book-keeping
	    next if ($datum eq 'group')
		or ($datum eq 'host_name');

	    munin_set_var_path($datafile_hash, $worker . ":". $datum, $workerdata->{$datum});
	}
	
    }
}

sub _get_from_arrayref
{
	my ($aref, $key, $default) = @_;

	for my $item (@$aref) {
		my ($_key, $_value) = @$item;

		return $_value if ($_key eq $key);
	}

	# Not found
	return $default;
}


1;


__END__

=head1 NAME

Munin::Master::Update - Contacts Munin Nodes, gathers data from their
service data sources, and stores this information in RRD files.

=head1 SYNOPSIS

 my $update = Munin::Master::Update->new();
 $update->run();

=head1 METHODS

=over

=item B<new>

 my $update = Munin::Master::Update->new();

Constructor.

=item B<run>

 $update->run();

This is where all the work gets done.

=back

