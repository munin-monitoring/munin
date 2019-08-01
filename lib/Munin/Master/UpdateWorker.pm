package Munin::Master::UpdateWorker;
use base qw(Munin::Master::Worker);


use warnings;
use strict;

use Carp;
use English qw(-no_match_vars);
use Munin::Common::Logger;

use File::Basename;
use File::Path;
use File::Spec;
use IO::Socket::INET;
use Munin::Master::Config;
use Munin::Master::Node;
use Munin::Master::Utils;
use RRDs;
use Time::HiRes;
use Data::Dumper;
use Scalar::Util qw(weaken);

use List::Util qw(max shuffle);

my $config = Munin::Master::Config->instance()->{config};

# Flags that have RRD autotuning enabled.
my $rrd_tune_flags = {
	type => '--data-source-type',
	max => '--maximum',
	min => '--minimum',
};

sub new {
    my ($class, $host, $worker) = @_;

    my $self = $class->SUPER::new($host->get_full_path);
    $self->{host} = $host;

    # node addresses are optional, defaulting to node name
    # More infos in #972 & D:592213
    $host->{address} = _get_default_address($host) unless defined $host->{address};

    $self->{node} = Munin::Master::Node->new($host->{address},
                                             $host->{port},
                                             $host->{host_name},
					     $host);
    # $worker already has a ref to $self, so avoid mem leak
    $self->{worker} = $worker;
    weaken($self->{worker});

    DEBUG "created $self";

    return $self;
}


sub do_work {
    my ($self) = @_;

    my $update_time = Time::HiRes::time;
    my $host = $self->{host}{host_name};
    my $group = $self->{host}{group};
    my $path = $self->{host}->get_full_path;
    $path =~ s{[:;]}{-}g;

    my $nodedesignation = $host."/".
	$self->{host}{address}.":".$self->{host}{port};

    local $0 = "$0 [$nodedesignation]";

    # No need to lock for the node. We'll use per plugin locking, and it will be
    # handled directly in SQL. This will enable node-pushed updates.

    my %all_service_configs = (
		data_source => {},
		global => {},
	);

	# Connecting to carbon isn't maintained with the new SQL metadata, so removing it.
	# We should provide a generic way to hook into the data updating part
	WARN "Connecting to a Carbon Server isn't supported anymore." if $config->{carbon_server};

	# Having a local handle looks easier
	my $node = $self->{node};

    INFO "[INFO] starting work in $$ for $nodedesignation.\n";
    my $done = $node->do_in_session(sub {

	# A I/O timeout results in a violent exit.  Catch and handle.
	eval {
		# Create the group path
		my $grp_id = $self->_db_mkgrp($group);

		# Fetch the node name
		my $node_name = $self->{node_name} || $self->{host}->{host_name};

		# Create the node
		my $node_id = $self->_db_node($grp_id, $node_name);
		$self->{node_id} = $node_id;

		my @node_capabilities = $node->negotiate_capabilities();


		$self->{dbh}->begin_work() if $self->{dbh}->{AutoCommit};

		my $dbh = $self->{dbh};

		# Handle spoolfetch, one call to retrieve everything
		if (grep /^spool$/, @node_capabilities) {
		my $spoolfetch_last_timestamp = $self->get_spoolfetch_timestamp();
		local $0 = "$0 s($spoolfetch_last_timestamp)";

		# We do inject the update handling, in order to have on-the-fly
		# updates, as we don't want to slurp the whole spoolfetched output
		# and process it later. It will surely timeout, and use a truckload
		# of RSS.
		my $timestamp = $node->spoolfetch($spoolfetch_last_timestamp, sub {
				my ($plugin, $now, $data, $last_timestamp, $update_rate_ptr) = @_;
				INFO "spoolfetch config ($plugin, $now)";
				local $0 = "$0 t($now) c($plugin)";
				$self->uw_handle_config( @_ );
		} );

		# update the timestamp if we spoolfetched something
		$self->set_spoolfetch_timestamp($timestamp) if $timestamp;

		# Note that spoolfetching hosts is always a success. BY DESIGN.
		# Since, if we cannot connect, or whatever else, it is NOT an issue.

		# No need to do more than that on this node
		goto NODE_END;
	}

	# Note: A multigraph plugin can present multiple services.
	my @plugins = $node->list_plugins();

	# We are not spoolfetching, so we should protect ourselves against
	# plugin redef. Note that we should declare 2 different HASHREF,
	# otherwise it is _shared_ which isn't what we want.
	$self->{__SEEN_PLUGINS__} = {};

	# Shuffle @plugins to avoid always having the same ordering
	# XXX - It might be best to preorder them on the TIMETAKEN ASC
	#       in order that statisticall fast plugins are done first to increase
	#       the global throughtput
	@plugins = shuffle(@plugins);

	for my $plugin (@plugins) {
		DEBUG "[DEBUG] for my $plugin (@plugins)";
		if (defined $config->{limit_services} && %{$config->{limit_services}}) {
		    next unless $config->{limit_services}{$plugin};
		}

		DEBUG "[DEBUG] config $plugin";

		local $0 = "$0 c($plugin)";
		my $update_rate = "300"; # Default
		my $last_timestamp = $node->fetch_service_config($plugin, sub { $self->uw_handle_config( @_, \$update_rate); });

		# Ignoring if $last_timestamp is undef, as we don't have config
		if (! defined ($last_timestamp)) {
			INFO "[INFO] $plugin did emit no proper config, ignoring";
			next;
		}

		if ($update_rate ne "300") {
			INFO "[INFO] $plugin did change update_rate to $update_rate";
		}

		# Done with this plugin on dirty config (we already have a timestamp for data)
		# --> Note that dirtyconfig plugin are always polled every run,
		#     as we don't have a way to know yet.
		next if ($last_timestamp);


		my $now = time;
		my $is_fresh_enough = $self->is_fresh_enough($update_rate, $last_timestamp, $now);

		next if ($is_fresh_enough);

		DEBUG "[DEBUG] fetch $plugin";
		local $0 = "$0 f($plugin)";

		$last_timestamp = $node->fetch_service_data($plugin,
			sub {
				# First argument is the plugin name to be overridden when multigraphing
				my $plugin_name = shift;

				$self->uw_handle_fetch($plugin_name, $now, $update_rate, @_);
			}
		);
	    } # for @plugins
NODE_END:
	    # Send "quit" to node
	    $node->quit();

	    # We want to commit to avoid leaking transactions
	    $dbh->commit() unless $dbh->{AutoCommit};
	}; # eval

	# kill the remaining process if needed
	# (useful if we spawned an helper, as for cmd:// or ssh://)
	# XXX - investigate why this leaks here. It should be handled directly by Node.pm
	my $node_pid = $node->{pid};
	if ($node_pid && kill(0, $node_pid)) {
		INFO "[INFO] Killing subprocess $node_pid";
		kill 'KILL', $node_pid; # Using SIGKILL, since normal termination didn't happen
	}

	if ($@ =~ m/^NO_SPOOLFETCH_DATA /) {
	    INFO "[INFO] No spoofetch data for $nodedesignation";
	    return;
	} elsif ($@) {
	    ERROR "[ERROR] Error in node communication with $nodedesignation: "
		.$@;
	    return;
	}

FETCH_OK:
	# Everything went smoothly.
	DEBUG "[DEBUG] Everything went smoothly.";
	return 1;

    }); # do_in_session

    # This handles failure in do_in_session,
    return if ! $done || ! $done->{exit_value};

    return {
        time_used => Time::HiRes::time - $update_time,
    }
}

sub _db_url {
	my ($self, $type, $id, $path, $p_type, $p_id) = @_;
	my $dbh = $self->{dbh};

	if ($p_type) {
		my $sth_g_url = $dbh->prepare_cached("SELECT path FROM url WHERE type = ? AND id = ?");
		$sth_g_url->execute($p_type, $p_id);
		my ($p_path) = $sth_g_url->fetchrow_array();
		$sth_g_url->finish();

		# prefix with the parent URL if provided
		$path = "$p_path/$path" if $p_path;
	}

	my $sth_u_url = $dbh->prepare_cached("UPDATE url SET path = ? WHERE type = ? AND id = ?");
	my $nb_rows_affected = $sth_u_url->execute($path, $type, $id);
	unless ($nb_rows_affected > 0) {
		my $sth_url = $dbh->prepare_cached('INSERT INTO url (type, id, path) VALUES (?, ?, ?)');
		$sth_url->execute($type, $id, $path);
	}
}

sub _db_mkgrp {
	my ($self, $group) = @_;
	my $dbh = $self->{dbh};

	DEBUG "group:".Dumper($group);

	# Recursively creates the group path
	my $p_id = 0; # XXX - 0 is a magic number that says NO_PARENT, as the == NULL doesn't work

	$p_id = $self->_db_mkgrp($group->{group}) if defined $group->{group};

	my $grp_name = $group->{group_name};

	# Create the group if needed
	my $sth_grp_id;
	if (defined $p_id) {
		$sth_grp_id = $dbh->prepare_cached("SELECT id FROM grp WHERE name = ? AND p_id = ?");
		$sth_grp_id->execute($grp_name, $p_id);
	} else {
		$sth_grp_id = $dbh->prepare_cached("SELECT id FROM grp WHERE name = ? AND p_id IS NULL");
		$sth_grp_id->execute($grp_name);
	}
	my ($grp_id) = $sth_grp_id->fetchrow_array();
	$sth_grp_id->finish();

	if (! defined $grp_id) {
		# Create the Group
		my $sth_grp = $dbh->prepare_cached('INSERT INTO grp (name, p_id, path) VALUES (?, ?, ?)');
		my $path = "";
		$sth_grp->execute($grp_name, $p_id, $path);
		$grp_id = _get_last_insert_id($dbh, "grp");
	} else {
		# Nothing to do, the grp doesn't need any updates anyway.
		# Removal of grp is *unsupported* yet.
	}

	$self->_db_url("group", $grp_id, $grp_name);

	return $grp_id;
}

# This should go in a generic DB.pm
sub _get_last_insert_id {
	my ($dbh, $tablename) = @_;
	return $dbh->last_insert_id("", "", $tablename, "");
}

sub _db_node {
	my ($self, $grp_id, $node_name) = @_;
	my $dbh = $self->{dbh};

	DEBUG "_db_node($grp_id, $node_name)";

	my $sth_node_id = $dbh->prepare_cached("SELECT id FROM node WHERE grp_id = ? AND name = ?");
	$sth_node_id->execute($grp_id, $node_name);
	my ($node_id) = $sth_node_id->fetchrow_array();
	$sth_node_id->finish();

	if (! defined $node_id) {
		# Create the node
		my $sth_node = $dbh->prepare_cached('INSERT INTO node (grp_id, name, path) VALUES (?, ?, ?)');
		my $path = "";
		$sth_node->execute($grp_id, $node_name, $path);
		$node_id = _get_last_insert_id($dbh, "node");
	} else {
		# Nothing to do, the node doesn't need any updates anyway.
		# Removal of nodes is *unsupported* yet.
	}

	$self->_db_url("node", $node_id, $node_name, "group", $grp_id);

	DEBUG "_db_node() = $node_id";
	return $node_id;
}

sub _db_service {
	my ($self, $plugin, $service_attr, $fields) = @_;
	my $dbh = $self->{dbh};
	my $node_id = $self->{node_id};

	DEBUG "_db_service($node_id, $plugin)";
	DEBUG "_db_service.service_attr:".Dumper($service_attr);
	DEBUG "_db_service.fields:".Dumper($fields);

	# Save the whole service config, and drop it.
	my $sth_service_id = $dbh->prepare_cached("SELECT id FROM service WHERE node_id = ? AND name = ?");
	$sth_service_id->execute($node_id, $plugin);
	my ($service_id) = $sth_service_id->fetchrow_array();
	$sth_service_id->finish();

	if (! defined $service_id) {
		# Doesn't exist yet, create it
		my $sth_service = $dbh->prepare_cached("INSERT INTO service (node_id, name) VALUES (?, ?)");
		$sth_service->execute($node_id, $plugin);
		$service_id = _get_last_insert_id($dbh, "service");
	}

	DEBUG "_db_service.service_id:$service_id";

	# Save the existing values
	my (%service_attrs_old, %fields_old);
	{
		my $sth_service_attrs = $dbh->prepare_cached("SELECT name, value FROM service_attr WHERE id = ?");
		$sth_service_attrs->execute($service_id);

		while (my ($_name, $_value) = $sth_service_attrs->fetchrow_array()) {
			$service_attrs_old{$_name} = $_value;
		}
		$sth_service_attrs->finish();

		my $sth_fields_attr = $dbh->prepare_cached("SELECT ds.name as field, ds_attr.name as attr, ds_attr.value FROM ds
			LEFT OUTER JOIN ds_attr ON ds.id = ds_attr.id WHERE ds.service_id = ?");
		$sth_fields_attr->execute($service_id);

		my %fields_old;
		while (my ($_field, $_name, $_value) = $sth_fields_attr->fetchrow_array()) {
			$fields_old{$_field}{$_name} = $_value;
		}
		$sth_fields_attr->finish();
	}

	DEBUG "_db_service.%service_attrs_old:" . Dumper(\%service_attrs_old);
	DEBUG "_db_service.%fields_old:" . Dumper(\%fields_old);

	# Leave room for refresh
	# XXX - we might only update DB with diff.
	my $sth_service_attrs_del = $dbh->prepare_cached("DELETE FROM service_attr WHERE id = ?");
	$sth_service_attrs_del->execute($service_id);

	for my $attr (keys %$service_attr) {
		my $_service_value = $service_attr->{$attr};
		$self->_db_service_attr($service_id, $attr, $_service_value);
	}

	# Update the ordering of fields
	{
		my @graph_order = split(/ /, $service_attr->{graph_order});
		DEBUG "_db_service.graph_order: @graph_order";
		my $ordr = 0;
		for my $_name (@graph_order) {
			my $sth_update_ordr = $dbh->prepare_cached("UPDATE ds SET ordr = ? WHERE ds.service_id = ? AND ds.name = ?");
			$sth_update_ordr->execute($ordr, $service_id, $_name);
			DEBUG "_db_service.update_order($ordr, $service_id, $_name)";
			$ordr ++;
		}
	}

	# Handle the service_category
	{
		my $category = $service_attr->{graph_category} || "other";

		# XXX - might only INSERT IT IF NOT PRESENT
		my $sth_service_cat_del = $dbh->prepare_cached("DELETE FROM service_categories WHERE id = ? and category = ?");
		$sth_service_cat_del->execute($service_id, $category);

		my $sth_service_cat = $dbh->prepare_cached("INSERT INTO service_categories (id, category) VALUES (?, ?)");
		$sth_service_cat->execute($service_id, $category);
	}

	# Handle the fields

	# Remove the ds_attr rows
	{
		my $sth_del_attr = $dbh->prepare_cached('DELETE FROM ds_attr WHERE id IN (SELECT id FROM ds WHERE service_id = ?)');
		$sth_del_attr->execute($service_id);
	}

	my %ds_ids;
	for my $field_name (keys %$fields) {
		my $_field_attrs = $fields->{$field_name};


		my $ds_id = $self->_db_ds_update($service_id, $field_name, $_field_attrs);
		$ds_ids{$field_name} = $ds_id;
	}

	# Purge the ds that have no attributes, as they are not relevant anymore
	{
		my $sth_del_ds = $dbh->prepare_cached('DELETE FROM ds WHERE service_id = ? AND NOT EXISTS (SELECT * FROM ds_attr WHERE ds_attr.id = ds.id)');
		$sth_del_ds->execute($service_id);
	}

	$self->_db_url("service", $service_id, $plugin, "node", $node_id);

	DEBUG "_db_service() = $service_id";

	return ($service_id, \%service_attrs_old, \%fields_old, \%ds_ids);
}

sub _db_service_attr {
	my ($self, $service_id, $name, $value) = @_;
	my $dbh = $self->{dbh};

	DEBUG "_db_service_attr($service_id, $name, $value)";

	# Save the whole service config, and drop it.
	my $sth_service_attr = $dbh->prepare_cached("INSERT INTO service_attr (id, name, value) VALUES (?, ?, ?)");
	$sth_service_attr->execute($service_id, $name, $value);
}

sub _db_ds_update {
	my ($self, $service_id, $field_name, $attrs) = @_;
	my $dbh = $self->{dbh};

	DEBUG "_db_ds_update($service_id, $field_name, $attrs)";

	my $sth_id = $dbh->prepare_cached("SELECT id FROM ds WHERE service_id = ? AND name = ?");
	$sth_id->execute($service_id, $field_name);

	my ($ds_id) = $sth_id->fetchrow_array();
	$sth_id->finish();

	if (! defined $ds_id) {
		# Doesn't exist yet, create it
		my $sth_ds = $dbh->prepare_cached("INSERT INTO ds (service_id, name) VALUES (?, ?)");
		$sth_ds->execute($service_id, $field_name);
		$ds_id = _get_last_insert_id($dbh, "ds");
	}

	# Reinsert the other rows
	my $sth_ds_attr = $dbh->prepare_cached('INSERT INTO ds_attr (id, name, value) VALUES (?, ?, ?)');
	for my $field_attr (keys %$attrs) {
		my $_value = $attrs->{$field_attr};
		$sth_ds_attr->execute($ds_id, $field_attr, $_value);
	}

	return $ds_id;
}

sub _db_state_update {
	my ($self, $plugin, $field, $when, $value) = @_;
	my $dbh = $self->{dbh};
	my $node_id = $self->{node_id};

	DEBUG "_db_state_update($plugin, $field, $when, $value)";
	DEBUG "_db_state_update.node_id:$node_id";
	my $sth_ds = $dbh->prepare_cached("
		SELECT ds.id FROM ds
		JOIN service s ON ds.service_id = s.id AND s.node_id = ? AND s.name = ?
		WHERE ds.name = ?");
	$sth_ds->execute($node_id, $plugin, $field);
	my ($ds_id) = $sth_ds->fetchrow_array();
	DEBUG "_db_state_update.ds_id:$ds_id";
	$sth_ds->finish();

	# Update the state with the new values
	my $sth_state_u = $dbh->prepare_cached("UPDATE state SET prev_epoch = last_epoch, prev_value = last_value, last_epoch = ?, last_value = ? WHERE id = ? AND type = ?");
	my $rows_u = $sth_state_u->execute($when, $value, $ds_id, "ds");
	if ($rows_u eq "0E0") {
		# No line exists yet. Create It.
		my $sth_state_i = $dbh->prepare_cached("INSERT INTO state (id, type) VALUES (?, ?)");
		$sth_state_i->execute($ds_id, "ds");
	}

	return $ds_id;
}


sub is_fresh_enough {
	my ($self, $update_rate, $last_timestamp, $now) = @_;

	DEBUG "is_fresh_enough($update_rate, $last_timestamp, $now)";

	my ($update_rate_in_sec, $is_update_aligned) = parse_update_rate($update_rate);

	DEBUG "update_rate_in_sec:$update_rate_in_sec";

	my $age = $now - $last_timestamp;

	DEBUG "now:$now, age:$age";

	my $is_fresh_enough = ($age < $update_rate_in_sec) ? 1 : 0;
	DEBUG "is_fresh_enough  $is_fresh_enough";

	return $is_fresh_enough;
}

sub get_spoolfetch_timestamp {
	my ($self) = @_;
	my $dbh = $self->{dbh};
	my $node_id = $self->{node_id};

	my $sth_spoolfetch = $dbh->prepare_cached("SELECT spoolepoch FROM node WHERE id = ?");
	$sth_spoolfetch->execute($node_id);
	my ($last_updated_value) = $sth_spoolfetch->fetchrow_array();
	$sth_spoolfetch->finish();

	# 0 if unset
	$last_updated_value = 0 unless $last_updated_value;

	DEBUG "[DEBUG] get_spoolfetch_timestamp($node_id) = $last_updated_value";
	return $last_updated_value;
}

sub set_spoolfetch_timestamp {
	my ($self, $timestamp) = @_;
	my $dbh = $self->{dbh};
	my $node_id = $self->{node_id};
	DEBUG "[DEBUG] set_spoolfetch_timestamp($node_id, $timestamp)";

	my $sth_spoolfetch = $dbh->prepare_cached("UPDATE node SET spoolepoch = ? WHERE id = ?");
	$sth_spoolfetch->execute($timestamp, $node_id);
	$sth_spoolfetch->finish();
}

sub parse_update_rate {
	my ($update_rate_config) = @_;

	my ($update_rate_in_sec, $is_update_aligned);
	if ($update_rate_config =~ m/(\d+[a-z]?)( aligned)?/) {
		$update_rate_in_sec = to_sec($1);
		$is_update_aligned = ($2 || 0);
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


# For the uw_handle_* :
# The $data has been already sanitized :
# * chomp()
# * comments are removed
# * empty lines are removed

# This handles one config part.
# - It will automatically call uw_handle_fetch to handle dirty_config
# - In case of multigraph (or spoolfetch) the caller has to call this for every multigraph part
# - It handles empty $data, and just does nothing
#
# Returns the last updated timestamp
sub uw_handle_config {
	my ($self, $plugin, $now, $data, $last_timestamp, $update_rate_ptr) = @_;

	# Protect oneself against multiple, conflicting multigraphs
	if (defined $self->{__SEEN_PLUGINS__} && $self->{__SEEN_PLUGINS__}{$plugin} ++) {
		WARN "uw_handle_config: $plugin is already configured, skipping";
		return $last_timestamp;
	}

	# Begin transaction if not already in a transaction
	$self->{dbh}->begin_work() if $self->{dbh}->{AutoCommit};

	# Build FETCH data, just in case of dirty_config.
	my @fetch_data;

	# Parse the output to a simple HASH
	my %service_attr = ();
	my %fields = ();
	my @field_order = ();
	for my $line (@$data) {
		DEBUG "uw_handle_config: $line";
		# Barbaric regex to parse the output of the config
		# graph_title hymir : Sea giant ===> $arg1: "graph_title", $arg2: undef, $value: "hymir : Sea giant"
		next unless ($line =~ m{^([^\.\s]+)(?:\.(\S+))?\s+?(.+)$});
		my ($arg1, $arg2, $value) = ($1, $2, $3);

		if (! $arg2) {
			# This is a service config line
			$service_attr{$arg1} = $value;
			next; # Handled
		}

		# Handle dirty_config
		if ($arg2 && $arg2 eq "value") {
			push @fetch_data, $line;
			next; # Handled
		}

		$fields{$arg1}{$arg2} = $value;

		# Adding the $field if not present.
		# Using an array since, obviously, the order is important.
		push @field_order, $arg1;
	}

	$$update_rate_ptr = $service_attr{"update_rate"} if $service_attr{"update_rate"};

	# Merging graph_order & field_order
	{
		my @graph_order = split(/ /, $service_attr{"graph_order"} || "");
		for my $field (@field_order) {
			push @graph_order, $field unless grep { $field } @graph_order;
		}

		$service_attr{"graph_order"} = join(" ", @graph_order);
	}

	# Always provide a default graph_title
	$service_attr{graph_title} = $plugin unless defined $service_attr{graph_title};

	# Sync to database
	# Create/Update the service
	my ($service_id, $service_attrs_old, $fields_old, $ds_ids) = $self->_db_service($plugin, \%service_attr, \%fields);

	# Create the RRDs
	for my $ds_name (keys %fields) {
		my $ds_config = $fields{$ds_name};
		my $ds_id = $ds_ids->{$ds_name};

		my $first_epoch = time - (12 * 3600); # XXX - we should be able to have some delay in the past for spoolfetched plugins
		my $rrd_file = $self->_create_rrd_file_if_needed($plugin, $ds_name, $ds_config, $first_epoch);

		# Update the RRD file
		# XXX - Should be handled in a stateful way, as now it is reconstructed every time
		my $dbh = $self->{dbh};
		my $sth_ds_attr = $dbh->prepare_cached('INSERT INTO ds_attr (id, name, value) VALUES (?, ?, ?)');
		$sth_ds_attr->execute($ds_id, "rrd:file", $rrd_file);
		$sth_ds_attr->execute($ds_id, "rrd:field", "42");
	}

	# timestamp == 0 means "Nothing was updated". We only count on the
	# "fetch" part to provide us good timestamp info, as the "config" part
	# doesn't contain any, specially in case we are spoolfetching.
	#
	# Also, the caller can override the $last_timestamp, to be called in a loop
	$last_timestamp = 0 unless defined $last_timestamp;

	# Delegate the FETCH part
	my $update_rate = $service_attr{"update_rate"} || 300;
	my $timestamp;
	$timestamp = $self->uw_handle_fetch($plugin, $now, $update_rate, \@fetch_data) if (@fetch_data);
	$last_timestamp = $timestamp if $timestamp && $timestamp > $last_timestamp;

	$self->{dbh}->commit() unless $self->{dbh}->{AutoCommit};
	return $last_timestamp;
}

# This handles one fetch part.
# Returns the last updated timestamp
sub uw_handle_fetch {
	my ($self, $plugin, $now, $update_rate, $data) = @_;

	# timestamp == 0 means "Nothing was updated"
	my $last_timestamp = 0;

	$self->{dbh}->begin_work() if $self->{dbh}->{AutoCommit};

	my ($update_rate_in_seconds, $is_update_aligned) = parse_update_rate($update_rate);

	# Process all the data in-order
	for my $line (@$data) {
		next unless ($line =~ m{\A ([^\.]+)(?:\.(\S)+)? \s+ ([\S:]+) }xms);
		my ($field, $arg, $value) = ($1, $2, $3);

		my $when = $now; # Default is NOW, unless specified
		my $when_is_now = 1;
		if ($value =~ /^(\d+):(.+)$/) {
			$when = $1;
			$when_is_now = 0;
			$value = $2;
		}

		use Scalar::Util qw(looks_like_number);
		WARN "asked to parse '$line' and got value=$value" unless looks_like_number($value) || $value eq "U";

		# Always round the $when if plugin asks for. Rounding the plugin-provided
		# time is weird, but we are doing it to follow the "least surprise principle".
		$when = round_to_granularity($when, $update_rate_in_seconds) if $is_update_aligned;

		# Update last_timestamp if the current update is more recent
		$last_timestamp = $when if (!$when_is_now && $when > $last_timestamp);

		# Update all data-driven components: State, RRD, Graphite
		my $ds_id = $self->_db_state_update($plugin, $field, $when, $value);
	        DEBUG "[DEBUG] ds_id($plugin, $field, $when, $value) = $ds_id";

		my ($rrd_file, $rrd_field);
		{
			# XXX - Quite inefficient, but works
			my $dbh = $self->{dbh};
			my $sth_rrdinfos = $dbh->prepare_cached(
				"SELECT name, value FROM ds_attr WHERE id = ? AND name in (
					'rrd:file',
					'rrd:field'
				)"
			);
			$sth_rrdinfos->execute($ds_id);
			while ( my @row = $sth_rrdinfos->fetchrow_array ) {
				$rrd_file  = $row[1] if $row[0] eq "rrd:file";
				$rrd_field = $row[1] if $row[0] eq "rrd:field";
			}
			$sth_rrdinfos->finish();
		}

		# This is a little convoluted but is needed as the API permits
		# vectorized updates
		my $ds_values = {
			"value" => [ $value, ],
			"when" => [ $when, ],
		};
		DEBUG "[DEBUG] self->_update_rrd_file($rrd_file, $field, $ds_values";
		$self->_update_rrd_file($rrd_file, $field, $ds_values);

	}

	$self->{dbh}->commit() unless $self->{dbh}->{AutoCommit};

	return $last_timestamp;
}

sub _get_rrd_data_source_with_defaults {
    my ($self, $data_source) = @_;

    # Copy it into a new hash, we don't want to alter the $data_source
    # and anything already defined should not be overridden by defaults
    my $ds_with_defaults = {
	    type => 'GAUGE',
	    min => 'U',
	    max => 'U',

	    update_rate => ($config->{update_rate} || 300),
	    graph_data_size => ($config->{graph_data_size} || "normal"),
    };
    for my $key (keys %$data_source) {
	    $ds_with_defaults->{$key} = $data_source->{$key};
    }

    return $ds_with_defaults;
}


sub _create_rrd_file_if_needed {
    my ($self, $service, $ds_name, $ds_config, $first_epoch) = @_;

    my $rrd_file = $self->_get_rrd_file_name($service, $ds_name, $ds_config);
    unless (-f $rrd_file) {
        $self->_create_rrd_file($rrd_file, $service, $ds_name, $ds_config, $first_epoch);
    }

    return $rrd_file;
}


sub _get_rrd_file_name {
    my ($self, $service, $ds_name, $ds_config) = @_;

    $ds_config = $self->_get_rrd_data_source_with_defaults($ds_config);
    my $type_id = lc(substr(($ds_config->{type}), 0, 1));

    my $path = $self->{host}->get_full_path;
    $path =~ s{[;:]}{/}g;

    # Multigraph/nested services will have . in the service name in this function.
    $service =~ s{\.}{-}g;

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
    my ($self, $rrd_file, $service, $ds_name, $ds_config, $first_epoch) = @_;

    INFO "[INFO] creating rrd-file for $service->$ds_name: '$rrd_file'";

    munin_mkdir_p(dirname($rrd_file), oct(777));

    my @args;

    $ds_config = $self->_get_rrd_data_source_with_defaults($ds_config);
    my $resolution = $ds_config->{graph_data_size};
    my $update_rate = $ds_config->{update_rate};
    if ($resolution eq 'normal') {
	$update_rate = 300; # 'normal' means hard coded RRD $update_rate
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
    } elsif ($resolution eq 'huge') {
	$update_rate = 300; # 'huge' means hard coded RRD $update_rate
        push (@args,
              "RRA:AVERAGE:0.5:1:115200",  # resolution 5 minutes, for 400 days
              "RRA:MIN:0.5:1:115200",
              "RRA:MAX:0.5:1:115200");
    } elsif ($resolution eq 'debug') {
	$update_rate = 300; # 'debug' means hard coded RRD $update_rate
        push (@args,
              "RRA:AVERAGE:0.5:1:42",  # resolution 5 minutes, for 42 steps
              "RRA:MIN:0.5:1:42",
              "RRA:MAX:0.5:1:42");
    } elsif ($resolution =~ /^custom (.+)/) {
        # Parsing resolution to achieve computer format as defined on the RFC :
        # FULL_NB, MULTIPLIER_1 MULTIPLIER_1_NB, ... MULTIPLIER_NMULTIPLIER_N_NB
        my @resolutions_computer = parse_custom_resolution($1, $update_rate);
        my @enlarged_resolutions = enlarge_custom_resolution(@resolutions_computer);
        foreach my $resolution_computer(@resolutions_computer) {
            my ($multiplier, $multiplier_nb) = @{$resolution_computer};
            push (@args,
                "RRA:AVERAGE:0.5:$multiplier:$multiplier_nb",
                "RRA:MIN:0.5:$multiplier:$multiplier_nb",
                "RRA:MAX:0.5:$multiplier:$multiplier_nb"
            );
        }
    }

    # Add the RRD::create prefix (filename & RRD params)
    my $heartbeat = $update_rate * 2;
    unshift (@args,
        $rrd_file,
        "--start", ($first_epoch - $update_rate),
	"-s", $update_rate,
        sprintf('DS:42:%s:%s:%s:%s',
                $ds_config->{type}, $heartbeat, $ds_config->{min}, $ds_config->{max}),
    );

    INFO "[INFO] RRDs::create @args";
    RRDs::create @args;
    if (my $ERROR = RRDs::error) {
        ERROR "[ERROR] Unable to create '$rrd_file': $ERROR";
    }
}

sub enlarge_custom_resolution {
	my @enlarged_resolutions;
        foreach my $resolution_computer(@_) {
            my ($multiplier, $multiplier_nb) = @{$resolution_computer};
	    # Always add 10% to the RRA size, as specified in
	    # http://munin-monitoring.org/wiki/format-graph_data_size
	    $multiplier_nb += int ($multiplier_nb / 10) || 1;

	    push @enlarged_resolutions, [
		$multiplier,
		$multiplier_nb,
	    ];
	}

	return @enlarged_resolutions;
}

sub parse_custom_resolution {
	my @elems = split(',\s*', shift);
	my $update_rate = shift;

	DEBUG "[DEBUG] update_rate: $update_rate";

        my @computer_format;

	# First element is always the full resolution
	my $full_res = shift @elems;
	if ($full_res =~ m/^\d+$/) {
		# Only numeric, computer format
		unshift @elems, "1 $full_res";
	} else {
		# Human readable. Adding $update_rate in front of
		unshift @elems, "$update_rate for $full_res";
	}

        foreach my $elem (@elems) {
                if ($elem =~ m/(\d+) (\d+)/) {
                        # nothing to do, already in computer format
                        push @computer_format, [$1, $2];
                } elsif ($elem =~ m/(\w+) for (\w+)/) {
                        my $nb_sec = to_sec($1);
                        my $for_sec = to_sec($2);

			my $multiplier = int ($nb_sec / $update_rate);
                        my $multiplier_nb = int ($for_sec / $nb_sec);

			# Log & ignore if having a 0
			unless ($multiplier && $multiplier_nb) {
				ERROR "$elem"
					. " -> nb_sec:$nb_sec, for_sec:$for_sec"
					. " -> multiplier:$multiplier, multiplier_nb:$multiplier_nb";
				next;
			}

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
	return unless defined($values);

	if ($config->{"rrdcached_socket"}) {
		if (! -e $config->{"rrdcached_socket"} || ! -w $config->{"rrdcached_socket"}) {
			WARN "[WARN] RRDCached feature ignored: rrdcached socket not writable";
		} elsif($RRDs::VERSION < 1.3){
			WARN "[WARN] RRDCached feature ignored: perl RRDs lib version must be at least 1.3. Version found: " . $RRDs::VERSION;
		} else {
			# Using the RRDCACHED_ADDRESS environment variable, as
			# it is way less intrusive than the command line args.
			$ENV{RRDCACHED_ADDRESS} = $config->{"rrdcached_socket"};
		}
	}

	my @update_rrd_data;

	my ($current_updated_timestamp, $current_updated_value);
	for (my $i = 0; $i < scalar @$values; $i++) {
		my $value = $values->[$i];
		my $when = $ds_values->{when}[$i];

		# Ignore values that are not in monotonic increasing timestamp for the RRD.
		# Otherwise it will reject the whole update
		next if ($current_updated_timestamp && $when <= $current_updated_timestamp);

		# RRDtool does not like scientific format so we convert it.
		$value = convert_to_float($value);

		# Schedule for addition
		push @update_rrd_data, "$when:$value";

		$current_updated_timestamp = $when;
		$current_updated_value = $value;
	}

	DEBUG "[DEBUG] Updating $rrd_file with @update_rrd_data";
	if ($ENV{RRDCACHED_ADDRESS} && (scalar @update_rrd_data > 32) ) {
		# RRDCACHED only takes about 4K worth of commands. If the commands is
		# too large, we have to break it in smaller calls.
		#
		# Note that 32 is just an arbitrary chosen number. It might be tweaked.
		#
		# For simplicity we only call it with 1 update each time, as RRDCACHED
		# will buffer for us as suggested on the rrd mailing-list.
		# https://lists.oetiker.ch/pipermail/rrd-users/2011-October/018196.html
		for my $update_rrd_data (@update_rrd_data) {
			DEBUG "RRDs::update($rrd_file, $update_rrd_data)";
			RRDs::update($rrd_file, $update_rrd_data);
			# Break on error.
			last if RRDs::error;
		}
	} else {
		# normal vector-update the RRD
		DEBUG "RRDs::update($rrd_file, @update_rrd_data)";
		RRDs::update($rrd_file, @update_rrd_data);
	}

	if (my $ERROR = RRDs::error) {
		#confess Dumper @_;
		ERROR "[ERROR] In RRD: Error updating $rrd_file: $ERROR";
	}

	return $current_updated_timestamp;
}

sub convert_to_float
{
	my $value = shift;

	# Only convert if it looks like scientific format
	return $value unless ($value =~ /\d[Ee]([+-]?\d+)$/);

	my $magnitude = $1;
	if ($magnitude < 0) {
		# Preserve at least 4 significant digits
		$magnitude = abs($magnitude) + 4;
		$value = sprintf("%.*f", $magnitude, $value);
	} else {
		$value = sprintf("%.4f", $value);
	}

	return $value
}

sub _get_default_address
{
	my ($host) = @_;

	# As suggested by madduck in D:592213
	#
	# Might I suggest that the address parameter became optional and that
	# in its absence, the node's name is treated as a FQDN?
	#
	# If the node is specified with a group name, then one could use the
	# following heuristics : $node, $group.$node
	#
	# relative names might well work but should be tried last

	my $host_name = $host->{host_name};
	my $group_name = $host->{group}->{group_name};
	if ($host_name =~ m/\./ && _does_resolve($host_name)) {
		return $host_name;
	}

	if ($group_name =~ m/\./ && _does_resolve("$group_name.$host_name")) {
		return "$group_name.$host_name";
	}

	# Note that we do NOT care if relative names resolves or not, as it is
	# our LAST chance anyway
	return $host_name;
}

sub _does_resolve
{
	my ($name) = @_;

	use Socket;

	# evaluates to "True" if it resolves
	return gethostbyname($name);
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

  Copyright (C) 2010-2018 Steve Schnepp
  Copyright (C) 2009-2013 Nicolai Langfeldt
  Copyright (C) 2009 Kjell-Magne Øierud
  Copyright (C) 2002-2009 Jimmy Olsen

  This program is free software; you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation; version 2 dated June, 1991.

  This program is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License along
  with this program; if not, write to the Free Software Foundation, Inc.,
  51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.


