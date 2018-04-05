package Munin::Master::LimitsOld;

=begin comment

This is Munin::Master::LimitsOld, a minimal package shell to make
munin-limits modular (so it can be loaded persistently in a daemon for
example) without making it object oriented yet.  The non-'old' module
will feature proper object orientation like munin-update and will
have to wait until later.


Copyright (C) 2004-2009 Jimmy Olsen

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; version 2 dated June,
1991.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.


=end comment

=cut

use warnings;
use strict;

use Exporter;

our (@ISA, @EXPORT);
@ISA    = qw ( Exporter );
@EXPORT = qw ( limits_startup limits_main );

use POSIX qw ( strftime );
use Getopt::Long;
use Time::HiRes;
use Text::Balanced qw ( extract_bracketed );
use Scalar::Util qw( looks_like_number );
use Munin::Common::Logger;

use Munin::Master::Utils;
use Munin::Common::Defaults;

my $DEBUG          = 0;
my $VERBOSE        = 0;
my $conffile       = "$Munin::Common::Defaults::MUNIN_CONFDIR/munin.conf";
my $do_usage       = 0;
my $do_version     = 0;
my @limit_hosts    = ();
my @limit_services = ();
my @limit_contacts = ();
my @always_send    = ();
my $screen         = 0;
my $force          = 0;
my $verbose        = 0;
my $force_run_as_root = 0;
my %notes          = ();
my $config;
my $modified     = 0;
my %default_text = (
    "default" =>
        '${var:group} :: ${var:host} :: ${var:graph_title}${if:cfields \n\tCRITICALs:${loop<,>:cfields  ${var:label} is ${var:value} (outside range [${var:crange}])${if:extinfo : ${var:extinfo}}}.}${if:wfields \n\tWARNINGs:${loop<,>:wfields  ${var:label} is ${var:value} (outside range [${var:wrange}])${if:extinfo : ${var:extinfo}}}.}${if:ufields \n\tUNKNOWNs:${loop<,>:ufields  ${var:label} is ${var:value}${if:extinfo : ${var:extinfo}}}.}${if:fofields \n\tOKs:${loop<,>:fofields  ${var:label} is ${var:value}${if:extinfo : ${var:extinfo}}}.}\n',
    "nagios" =>
        '${var:host}\t${var:graph_title}\t${var:worstid}\t${strtrunc:350 ${if:cfields CRITICALs:${loop<,>:cfields  ${var:label} is ${var:value} (outside range [${var:crange}])${if:extinfo : ${var:extinfo}}}.}${if:wfields WARNINGs:${loop<,>:wfields  ${var:label} is ${var:value} (outside range [${var:wrange}])${if:extinfo : ${var:extinfo}}}.}${if:ufields UNKNOWNs:${loop<,>:ufields  ${var:label} is ${var:value}${if:extinfo : ${var:extinfo}}}.}${if:fofields OKs:${loop<,>:fofields  ${var:label} is ${var:value}${if:extinfo : ${var:extinfo}}}.}}',
    "old-nagios" =>
        '${var:host}\t${var:plugin}\t${var:worstid}\t${strtrunc:350 ${var:graph_title}:${if:cfields CRITICALs:${loop<,>:cfields  ${var:label} is ${var:value} (outside range [${var:crange}])${if:extinfo : ${var:extinfo}}}.}${if:wfields WARNINGs:${loop<,>:wfields  ${var:label} is ${var:value} (outside range [${var:wrange}])${if:extinfo : ${var:extinfo}}}.}${if:ufields UNKNOWNs:${loop<,>:ufields  ${var:label} is ${var:value}${if:extinfo : ${var:extinfo}}}.}${if:fofields OKs:${loop<,>:fofields  ${var:label} is ${var:value}${if:extinfo : ${var:extinfo}}}.}}'
);

sub limits_startup {

    # Get options
    my ($args) = @_;
    local @ARGV = @{$args};
    $do_usage = 1
        unless GetOptions(
        "host=s"    => \@limit_hosts,
        "service=s" => \@limit_services,
        "contact=s" => \@limit_contacts,
        "config=s"  => \$conffile,
        "debug"     => \$DEBUG,
        "verbose"   => \$VERBOSE,
        "screen"    => \$screen,
        "force!"    => \$force,
        "always-send=s" => \@always_send,
        "force-run-as-root!" => \$force_run_as_root,
        "version!"  => \$do_version,
        "help"      => \$do_usage
        );

    print_usage_and_exit()   if $do_usage;
    print_version_and_exit() if $do_version;

    if ( $DEBUG || $screen ) {
        my %log;
        $log{output} = 'screen' if $screen;
        $log{level}  = 'debug'  if $DEBUG;
        Munin::Common::Logger::configure(%log);
    }

    exit_if_run_by_super_user() unless $force_run_as_root;

    @always_send = qw{ok warning critical unknown} if $force;
}


sub limits_main {
    # We're liable to receive SIGPIPEs if the given commands don't work
    $SIG{PIPE} = 'IGNORE';

    my $update_time = Time::HiRes::time;

    my $lockfile = "$config->{rundir}/munin-limits.lock";

    INFO "[INFO] Starting munin-limits, getting lock $lockfile";

    munin_runlock("$config->{rundir}/munin-limits.lock");

    initialize_for_nagios();

    initialize_contacts();

    process_limits();

    close_pipes();

    $update_time = sprintf("%.2f", (Time::HiRes::time - $update_time));

    munin_removelock("$config->{rundir}/munin-limits.lock");

    INFO "[INFO] munin-limits finished ($update_time sec)";
}

sub close_pipes {
    foreach my $cont (@{munin_get_children($config->{"contact"})}) {
        if($cont->{pipe}) {
            my $c = munin_get_node_name($cont);

            DEBUG "[DEBUG] Closing pipe for contact $c";
            close $cont->{pipe} or WARN "[WARNING] Failed to close pipe for contact $c: $!";
        }
    }
}

sub process_limits {

    # Make array of what needs to be checked
    my %work_hash_tmp;
    my $work_array = [];
    foreach my $workfield (
        @{munin_find_field_for_limits($config, qr/^(critical|warning)/)}) {
        my $parent = munin_get_parent($workfield);
        if (!defined $work_hash_tmp{$parent}) {
	    $work_hash_tmp{$parent} = 1;
	    push @$work_array, $parent;
        }
    }

    # Process array containing services we need to check
    foreach my $workservice (@$work_array) {
        process_service($workservice);
    }

}


sub initialize_contacts {
    my $defaultcontacts = munin_get($config, "contacts", "");
    if (!length $defaultcontacts) {
        my @tmpcontacts = ();
        foreach my $cont (@{munin_get_children($config->{"contact"})}) {
            if (munin_get($cont, "command")) {
                push @tmpcontacts, munin_get_node_name($cont);
            }
        }
        $defaultcontacts = join(' ', @tmpcontacts);
    }
    munin_set_var_loc($config, ["contacts"], $defaultcontacts);

    DEBUG "[DEBUG] Set default \"contacts\" to \"$defaultcontacts\"";
}


sub initialize_for_nagios {
    if (   !defined $config->{'contact'}->{'nagios'}->{'command'}
        and defined $config->{'nsca'}) {
        $config->{'contact'}->{'old-nagios'}->{'command'}
            = "$config->{nsca} $config->{nsca_server} -c $config->{nsca_config} -to 60";
    }
}


sub print_usage_and_exit {
    print "Usage: $0 [options]

Options:
    --help		View this message.
    --debug		View debug messages.
    --screen		Send log messages to the screen (STDERR).
    --always-send <severity list>
                        Send messages to contacts even if state has
                        not changed since the last run. The list is a
                        space or comma separated list of severities.
                        Choose from one or more of \"critical\",
                        \"warning\", \"unknown\" and \"ok\".
    --force		Alias for \"--always-send ok,warning,critical,unknown\".
                        Overrides --always-send command line, as well as the
                        always_send contact configuration options.
    --service <service>	Limit notified services to <service>. Multiple 
    			--service options may be supplied.
    --host <host>	Limit notified hosts to <host>. Multiple --host 
    			options may be supplied.
    --contact <contact>	Limit notified contacts to <contact>. Multiple 
    			--contact options may be supplied.
    --config <file>	Use <file> as configuration file. 
    			[/etc/munin/munin.conf]

";
    exit 0;
}


# Get the host of the service in question
sub get_host_node {
    my $service = shift || return undef;
    my $parent  = munin_get_parent($service) || return undef;

    if (munin_has_subservices($parent)) {
	return get_host_node($parent);
    } else {
	return $parent;
    }
}

sub get_notify_name {
    my $hash = shift || return;

    if (defined $hash->{'notify_alias'}) {
	return $hash->{'notify_alias'};
    } elsif (defined $hash->{'graph_title'}) {
	return $hash->{'graph_title'};
    } else {
	return munin_get_node_name($hash);
    }
}

# Joined "sub-path" under host level
sub get_full_service_name {
    my $service    = shift || return undef;
    my $parent     = munin_get_parent($service);
    my $name       = get_notify_name($service);

    if (defined $parent and munin_has_subservices($parent)) {
	return (get_full_service_name($parent) . " :: " . $name);
    } else {
	return $name;
    }

}

# Joined group path above host level
sub get_full_group_path {
    my $group      = shift || return undef;
    my $parent     = munin_get_parent($group);
    my $name       = get_notify_name($group);

    if (defined $parent and munin_get_node_name($parent) ne "root") {
	return (get_full_group_path($parent) . "-" . $name);
    } else {
	return $name;
    }
}

sub process_service {
    my $hash       = shift || return;
    my $hobj       = get_host_node($hash);
    my $host       = munin_get_node_name($hobj);
    my $hostalias  = get_notify_name($hobj);
    my $service    = munin_get_node_name($hash);
    my $hparentobj = munin_get_parent($hobj);
    my $parent     = munin_get_node_name($hobj);
    my $gparent    = munin_get_node_name($hparentobj);
    my $children   = munin_get_children($hash);

    if (!ref $hash) {
	LOGCROAK("I was passed a non-hash!");
    }
    return if (@limit_hosts and !grep (/^$host$/, @limit_hosts));
    return if (@limit_services and !grep (/^$service$/, @limit_services));

    DEBUG "[DEBUG] processing service: $service";

    # Some fields that are nice to have in the plugin output
    $hash->{'fields'} = join(' ', map {munin_get_node_name($_)} @$children);
    $hash->{'plugin'} = $service;
    $hash->{'graph_title'} = get_full_service_name($hash);
    $hash->{'host'}  = $hostalias;
    $hash->{'group'} = get_full_group_path($hparentobj);
    $hash->{'worst'} = "ok";
    $hash->{'worstid'} = 0 unless defined $hash->{'worstid'};
    $hash->{'recovered'} = {};

    my $service_url = sprintf ('%s/%s', $hash->{group}, $host);
    DEBUG "[DEBUG] service_url: $service_url";

    use DBI;
    my $datafilename = $ENV{MUNIN_DBURL} || $config->{dbdir}."/datafile.sqlite";
    my $datafilename_state = $ENV{MUNIN_DBURL} || $config->{dbdir}."/datafile-state.sqlite";
    DEBUG "[DEBUG] opening sql $datafilename";
    my $dbh = DBI->connect("dbi:SQLite:dbname=$datafilename","","") or die $DBI::errstr;
    my $dbh_state = DBI->connect("dbi:SQLite:dbname=$datafilename","","") or die $DBI::errstr;
    my $sth_state = $dbh_state->prepare('SELECT last_epoch, last_value, prev_epoch, prev_value, alarm FROM state WHERE id = ? and type = ?');
    my $sth_state_upt = $dbh_state->prepare('UPDATE state SET alarm = ? WHERE id = ? and type = ?');
    my $sth_ds = $dbh->prepare('SELECT id FROM url WHERE path = ? and type = ?');

    foreach my $field (@$children) {
        next if (!defined $field or ref($field) ne "HASH");
        my $fname   = munin_get_node_name($field);
        my $fpath   = munin_get_node_loc($field);
        my $oldstate = 'ok';


	# Test directly here as get_limits is in truth recursive and
	# that fools us when processing multigraphs.
	next if (!defined($field->{warning}) and !defined($field->{critical}));

	# get the old state if there is one, or leave it empty.
	$sth_ds->execute("$service_url/$fname", "ds");
	my ($ds_id) = $sth_ds->fetchrow_array;

        my ($warn, $crit, $unknown_limit) = get_limits($field);

        # Skip fields without warning/critical definitions
        next if (!defined $warn and !defined $crit);

        DEBUG "[DEBUG] processing field: " . join('::', @$fpath);
        DEBUG "[DEBUG] field: " . munin_dumpconfig_as_str($field);
	my $value;
    	{
		$sth_state->execute($ds_id, "ds");
		my ($current_updated_timestamp, $current_updated_value,
			$previous_updated_timestamp, $previous_updated_value,
			$old_alarm, $num_unknowns) = $sth_state->fetchrow_array;

		my $oldstate = $old_alarm || 'ok';

		my $heartbeat = 600; # XXX - $heartbeat is a fixed 10 min (2 runs of 5 min).
		if (! $field->{type} || $field->{type} eq "GAUGE") {
			$value = $current_updated_value;
		} elsif (! defined $current_updated_value || ! defined $previous_updated_value || $current_updated_timestamp == $previous_updated_timestamp) {
			# No derive computing possible. Report unknown.
			$value = "U";
		} elsif (time > $current_updated_timestamp + $heartbeat) {
			# Current value is too old. Report unknown. 
			$value = "U";
		} elsif ($current_updated_timestamp > $previous_updated_timestamp + $heartbeat) {
			# Old value is too old. Report unknown. 
			$value = "U";
		} elsif ($field->{type} eq "COUNTER" && $current_updated_value < $previous_updated_value) {
			# COUNTER never decrease. Report unknown.
			$value = "U";
		} elsif ($current_updated_value eq "U") {
			# The current value is unknown. Report unknown.
			$value = "U";
		} elsif ($field->{type} eq "ABSOLUTE") {
			# The previous value is unimportant, as if ABSOLUTE, the counter is reset anytime the value is read
			$value = $current_updated_value / ($current_updated_timestamp - $previous_updated_timestamp);
		} elsif ($previous_updated_value eq "U") {
			# The previous value is unknown.
			# Report unknown, as we are not ABSOLUTE
			$value = "U";
		} else {
			# Everything is ok for DERIVE/COUNTER
			# compute the value per timeunit
			$value = ($current_updated_value - $previous_updated_value) / ($current_updated_timestamp - $previous_updated_timestamp);
		}
	}

    # De-taint.
    if ( !defined $value || $value eq "U" ) {
        $value = "unknown";
    }
    elsif ( looks_like_number($value) ) {
        $value = sprintf "%.6f", $value;
    }
    else {
        WARNING(  "Expected number, got \""
                . $value . "\":"
                . " group="
                . $hash->{group}
                . " host="
                . $hash->{host}
                . " plugin="
                . $hash->{plugin}
                . " field="
                . $fname );
        $value = "unknown";
    }

        # Some fields that are nice to have in the plugin output
        $field->{'value'} = $value;
        $field->{'crange'} = (defined $crit->[0] ? $crit->[0] : "") . ":"
            . (defined $crit->[1] ? $crit->[1] : "");
        $field->{'wrange'} = (defined $warn->[0] ? $warn->[0] : "") . ":"
            . (defined $warn->[1] ? $warn->[1] : "");
        DEBUG("[DEBUG] value: "
	      . join('::', @$fpath)
	      . ": $value (crit: "
	      . $field->{'crange'}
	      . ") (warn: "
	      . $field->{'wrange'}
	      . ")");

        if ($value eq "unknown") {
            $crit->[0] ||= "";
            $crit->[1] ||= "";

            my $state = "unknown";
            my $extinfo = defined $field->{"extinfo"}
                    ? "unknown: " . $field->{"extinfo"}
                    : "Value is unknown.";
            my $num_unknowns;

            if ( $oldstate ne "unknown") {
                $hash->{'state_changed'} = 1;
            }
            else {
                $hash->{'state_changed'} = 0;
            }

            # First we'll need to check whether the user wants to ignore
            # a few UNKNOWN values before actually changing the state to
            # UNKNOWN.
            if ($unknown_limit > 1) {
                if (defined $onfield and defined $onfield->{"state"}) {
                    if ($onfield->{"state"} ne "unknown") {
                        if (defined $onfield->{"num_unknowns"}) {
                            if ($onfield->{"num_unknowns"} < $unknown_limit) {
                                # Don't change the state to UNKNOWN yet.
                                $hash->{'state_changed'} = 0;
                                $state = $onfield->{"state"};
                                $extinfo = $onfield->{$state};

                                # Increment the number of UNKNOWN values seen.
                                $num_unknowns = $onfield->{"num_unknowns"} + 1;
                            }
                        }
                        else {
                            # Don't change the state to UNKNOWN yet.
                            $hash->{'state_changed'} = 0;
                            $state = $onfield->{"state"};
                            $extinfo = $onfield->{$state};
                            
                            # Start counting the number of consecutive UNKNOWN
                            # values seen.
                            $num_unknowns = 1;
                        }
                    }
                }
            }

            if ($state eq "unknown") {
                $hash->{'worst'} = "UNKNOWN" if $hash->{"worst"} eq "OK";
                $hash->{'worstid'} = 3 if $hash->{"worstid"} == 0;
            }
            elsif ($state eq "critical") {
                $hash->{'worst'} = "CRITICAL";
                $hash->{'worstid'} = 2;
            }
            elsif ($state eq "warning") {
                $hash->{'worst'} = "WARNING" if $hash->{"worst"} ne "CRITICAL";
                $hash->{'worstid'} = 1 if $hash->{"worstid"} != 2;
            }

            if (munin_get_bool($hobj, 'ignore_unknown', "false")) {
                DEBUG("[DEBUG] ignoring unknown value");
                $hash->{'state_changed'} = 0;
            }

            munin_set_var_loc(\%notes, [@$fpath, "state"], $state);
            munin_set_var_loc(\%notes, [@$fpath, $state], $extinfo);
            if (defined $num_unknowns) {
                munin_set_var_loc(\%notes, [@$fpath, "num_unknowns"],
                        $num_unknowns);
            }
        }

        elsif ((defined($crit->[0]) and $value < $crit->[0])
            or (defined($crit->[1]) and $value > $crit->[1])) {
            $crit->[0] ||= "";
            $crit->[1] ||= "";
            $hash->{'worst'}   = "CRITICAL";
            $hash->{'worstid'} = 2;
            munin_set_var_loc(\%notes, [@$fpath, "state"], "critical");
            munin_set_var_loc(
                \%notes,
                [@$fpath, "critical"], (
                    defined $field->{"extinfo"}
                    ? "$value (not in "
                        . $field->{'crange'} . "): "
                        . $field->{"extinfo"}
                    : "Value is $value. Critical range ("
                        . $field->{'crange'}
                        . ") exceeded"
                ));

            if ( $oldstate ne "critical") {
                $hash->{'state_changed'} = 1;
            }
        }
        elsif ((defined($warn->[0]) and $value < $warn->[0])
            or (defined($warn->[1]) and $value > $warn->[1])) {
            $warn->[0] ||= "";
            $warn->[1] ||= "";
            $hash->{'worst'} = "WARNING" if $hash->{"worst"} ne "CRITICAL";
            $hash->{'worstid'} = 1 if $hash->{"worstid"} != 2;
            munin_set_var_loc(\%notes, [@$fpath, "state"], "warning");
            munin_set_var_loc(
                \%notes,
                [@$fpath, "warning"], (
                    defined $field->{"extinfo"}
                    ? "$value (not in "
                        . $field->{'wrange'} . "): "
                        . $field->{"extinfo"}
                    : "Value is $value. Warning range ("
                        . $field->{'wrange'}
                        . ") exceeded"
                ));

            if ( $oldstate ne "warning") {
                $hash->{'state_changed'} = 1;
            }
        }
        else {
            munin_set_var_loc(\%notes, [@$fpath, "state"], "ok");
            munin_set_var_loc(\%notes, [@$fpath, "ok"],    "OK");

	    if ($oldstate ne 'ok') {
                if ($oldstate eq 'unknown' && munin_get_bool($hobj, 'ignore_unknown', 'false')) {
                    DEBUG("[DEBUG] ignoring transition from UNKNOWN to OK");
                } else {
		    $hash->{'state_changed'} = 1;
		    $hash->{'recovered'}{$fname} = 1;
                }
	    }
        }

	# Replicate the state into the SQL DB
	my $new_state = $onfield->{"state"};
	$sth_state_upt->execute($new_state, $ds_id, "ds");
    }
    generate_service_message($hash);
}


sub get_limits {
    my $hash = shift || return;

    # This hash will have values that we can look up such as these:
    my @critical = (undef, undef);
    my @warning  = (undef, undef);
    my $crit          = munin_get($hash, "critical",      undef);
    my $warn          = munin_get($hash, "warning",       undef);
    my $unknown_limit = munin_get($hash, "unknown_limit", 3);

    my $name = munin_get_node_name($hash);

    if (defined $crit and $crit =~ /^\s*([-+\d.]*):([-+\d.]*)\s*$/) {
        $critical[0] = $1 if length $1;
        $critical[1] = $2 if length $2;
    }
    elsif (defined $crit and $crit =~ /^\s*([-+\d.]+)\s*$/) {
        $critical[1] = $1;
    }
    elsif (defined $crit) {
        @critical = (0, 0);
    }
    if(defined $crit) {
        DEBUG "[DEBUG] processing critical: $name -> "
                . (defined $critical[0]? $critical[0] : "")
                .  " : "
                . (defined $critical[1]? $critical[1] : "");
    }   

    if (defined $warn and $warn =~ /^\s*([-+\d.]*):([-+\d.]*)\s*$/) {
        $warning[0] = $1 if length $1;
        $warning[1] = $2 if length $2;
    }
    elsif (defined $warn and $warn =~ /^\s*([-+\d.]+)\s*$/) {
        $warning[1] = $1;
    }
    elsif (defined $warn) {
        @warning = (0, 0);
    }
    if(defined $warn) {
        DEBUG "[DEBUG] processing warning: $name -> "
                . (defined $warning[0]? $warning[0] : "")
                .  " : "
                . (defined $warning[1]? $warning[1] : "");
    }

    if ($unknown_limit =~ /^\s*(\d+)\s*$/) {
        $unknown_limit = $1 if defined $1;
        if (defined $unknown_limit) {
            if ($unknown_limit < 1) {
                # Zero and negative numbers are not valid.  
                $unknown_limit = 1;
            }
        }
        DEBUG "[DEBUG] processing unknown_limit: $name -> $unknown_limit";
    }

    return (\@warning, \@critical, $unknown_limit);
}

sub generate_service_message {
    my $hash     = shift || return;
    my $critical = undef;
    my $worst    = $hash->{"worst"};
    my %stats    = (
        'critical' => [],
        'warning'  => [],
        'unknown'  => [],
        'foks'     => [],
        'ok'       => []);

    my $contacts = munin_get_children(munin_get_node($config, ["contact"]));

    DEBUG "[DEBUG] generating service message: "
	. join('::', @{munin_get_node_loc($hash)});

    my $children = 
	munin_get_children(
	    munin_get_node(\%notes, 
			   munin_get_node_loc($hash)));

    if ( defined($children) ) {
	foreach my $field (@$children) {
	    if (defined $field->{"state"}) {
                my $fname = munin_get_node_name($field);
                push @{$stats{$field->{'state'}}}, $fname;
                if ($field->{'state'} eq 'ok' and defined $hash->{'recovered'}{$fname}) {
                    push @{$stats{'foks'}}, $fname;
                }
	    }
	}
    }

    $hash->{'cfields'}  = join " ", @{$stats{'critical'}};
    $hash->{'wfields'}  = join " ", @{$stats{'warning'}};
    $hash->{'ufields'}  = join " ", @{$stats{'unknown'}};
    $hash->{'fofields'} = join " ", @{$stats{'foks'}};
    $hash->{'ofields'}  = join " ", @{$stats{'ok'}};
    $hash->{'numcfields'}  = scalar @{$stats{'critical'}};
    $hash->{'numwfields'}  = scalar @{$stats{'warning'}};
    $hash->{'numufields'}  = scalar @{$stats{'unknown'}};
    $hash->{'numfofields'} = scalar @{$stats{'foks'}};
    $hash->{'numofields'}  = scalar @{$stats{'ok'}};

    my $contactlist = munin_get($hash, "contacts", "");
    DEBUG("[DEBUG] Contact list for "
	  . join('::', @{munin_get_node_loc($hash)})
	  . ": $contactlist");

    foreach my $c (split(/\s+/, $contactlist)) {
        next if $c eq "none";
        my $contactobj = munin_get_node($config, ["contact", $c]);
        if(!defined $contactobj) {
            WARN("[WARNING] Missing configuration options for contact $c; skipping");
            next;
        }
        if (@limit_contacts and !grep (/^$c$/, @limit_contacts)) {
            next;
        }
        my $obsess = 0;
        my $always_send;

        if (@always_send) {
            # List of severities from command line argument
            $always_send = \@always_send;
        }
        else {
            # List of severities from contact configuration
            if (my $always_send_config = munin_get( $contactobj, "always_send" )) {
                my @always_send_config = ($always_send_config);
                $always_send = \@always_send_config;
            }
            else {
                $always_send = ['critical', 'warning'];
            }
        }

        $always_send = validate_severities($always_send);

        foreach my $status_level ( @{$always_send} ) {
	    if(defined($stats{$status_level})) {
		$obsess += scalar @{$stats{$status_level}};
	    }
	}
        if (!$hash->{'state_changed'} and !$obsess) {
            next;    # No need to send notification
        }
        INFO("[INFO] state has changed, notifying $c");
        my $precmd = munin_get($contactobj, "command", undef);
        if(!defined $precmd) {
            WARN("[WARNING] Missing command option for contact $c; skipping");
            next;
        }
        my $pretxt = munin_get(
            $contactobj,
            "text",
            munin_get(
                munin_get_node($config, ["contact", "default"]),
                "text",
                $default_text{$c} || $default_text{"default"}));
        my $txt = message_expand($hash, $pretxt, "");
        my $cmd = message_expand($hash, $precmd, "");
        $txt =~ s/\\n/\n/g;
        $txt =~ s/\\t/\t/g;

        if($cmd =~ /^\s*([|><]+)/) {
            WARN "[WARNING] Found \"$1\" at beginning of command.  This should no longer be necessary and will be removed from the command before execution";
            $cmd =~ s/^\s*[|><]+//;
        }

        my $maxmess = munin_get($contactobj, "max_messages", 0);
        my $curmess = munin_get($contactobj, "num_messages", 0);
        my $curcmd  = munin_get($contactobj, "pipe_command", undef);
        my $pipe    = munin_get($contactobj, "pipe",         undef);
        if ($maxmess and $curmess >= $maxmess) {
            DEBUG "[DEBUG] Resetting pipe for $c because max messages was reached";
            close($pipe) or WARN "[WARNING] Failed to close pipe for $c: $!";
            $pipe = undef;
            munin_set($contactobj, "pipe", undef);
        }
        elsif ($curcmd and $curcmd ne $cmd) {
            DEBUG "[DEBUG] Resetting pipe for $c because the command has changed";
            close($pipe) or WARN "[WARNING] Failed to close pipe for $c: $!";
            $pipe = undef;
            munin_set($contactobj, "pipe", undef);
        }

        if (!defined $pipe) {
            DEBUG "[DEBUG] Opening pipe for $c";
            pipe(my $r, my $w) or WARN "[WARNING] Failed to open pipe for $c: $!";
            my $pid = fork();
            defined($pid) or WARN "[WARNING] Failed fork for pipe for $c: $!";
            if($pid) { # parent
                DEBUG "[DEBUG] Opened pipe for $c as pid $pid";

                close $r;
                $pipe = $w;
                munin_set($contactobj, "pipe_command", $cmd);
                munin_set($contactobj, "pipe",         $pipe);
                munin_set($contactobj, "num_messages", 0);
                $curmess = 0;
            } else { # child
                close $w;
                open(STDIN, "<&", $r);
                # We want to close stdout before calling the send command. This prevents the
                # notification program (e.g. "send_nsca") to write irrelevant status messages
                # to stdout and thus trigger notification emails (e.g. via cron).
                # See https://github.com/munin-monitoring/munin/issues/382
                # and https://bugs.debian.org/cgi-bin/bugreport.cgi?bug=291168.
                close(STDOUT);
                exec($cmd) or WARN "[WARNING] Failed to exec for contact $c in pid $$";
                exit;
            }
        }

        DEBUG "[DEBUG] sending message to $c: \"$txt\"";
        if(defined $pipe and !print $pipe $txt, "\n") {
            WARN "[WARNING] Writing to pipe for $c failed: $!";
            close($pipe) or WARN "[WARNING] Failed to close pipe for $c: $!";
            $pipe = undef;
            munin_set($contactobj, "pipe", undef);
        }

        munin_set($contactobj, "num_messages", $curmess + 1);
    }
}

# Homegrown templating engine.
# XXX - Not sure it's a very good idea
sub message_expand {
    my $hash = shift;
    my $text = shift;
    my @res  = ();


    while (defined($text) && length($text)) {
        if ($text =~ /^([^\$]+|)(?:\$(\{.*)|)$/) {
            push @res, $1;
            $text = $2;
        }

        my @a = extract_bracketed($text, '{}');
        if(!defined $a[0]) {
            $text = $a[1];
            next;
        }

        if ($a[0] =~ /^\{var:(\S+)\}$/) {
            $a[0] = munin_get($hash, $1, "");
        }
        elsif ($a[0] =~ /^\{loop<([^>]+)>:\s*(\S+)\s(.+)\}$/) {
            my $d      = $1;
            my $f      = $2;
            my $t      = $3;
            my $fields = munin_get($hash, $f, "");
            my @res    = ();
            if ($fields) {
                foreach my $sub (split /\s+/, $fields) {
                    if (defined $hash->{$sub}) {
                        push @res, message_expand($hash->{$sub}, $t);
                    }
                }
            }
            $a[0] = join($d, @res);
        }
        elsif ($a[0] =~ /^\{loop:\s*(\S+)\s(.+)\}$/) {
            my $f      = $1;
            my $t      = $2;
            my $fields = munin_get($hash, $f, "");
            my $res    = "";
            if ($fields) {
                foreach my $sub (split /\s+/, $fields) {
                    if (defined $hash->{$sub}) {
                        push @res, message_expand($hash->{$sub}, $t);
                    }
                }
            }
            $a[0] = $res;
        }
        elsif ($a[0] =~ /^\{strtrunc:\s*(\S+)\s(.+)\}$/) {
            my $f = "%." . $1 . "s";
            my $t = $2;
            $a[0] = sprintf($f, message_expand($hash, $t));
        }
        elsif ($a[0] =~ /^\{if:\s*(\!)?(\S+)\s(.+)\}$/) {
            my $n     = $1;
            my $f     = $2;
            my $t     = $3;
            my $res   = "";
            my $field = munin_get($hash, $f, 0);
            my $check = (defined $field and $field ne "0" and length($field));
            $check = (!$check) if $n;

            if ($check) {
                $res .= message_expand($hash, $t);
            }
            $a[0] = $res;
        }
        push @res, $a[0];
        $text = $a[1];
    }

    return join('', @res);
}

=pod

Get a list of severities, and return a sorted, lower cased, unique and
validated list of severities.

Expects and returns an array reference.

If none of the severities given are on the allowed_severities list, it
will return a reference to an empty array.

=cut

sub validate_severities {
    my $severities_ref = shift;
    my @severities     = grep { defined $_ }  @{$severities_ref};

    my @allowed_severities = qw{ok warning critical unknown};

    # Flatten, split on comma and whitespace, and lowercase
    my @expanded_severities =
      split( /[[:space:],]+/, lc( join( ',', @severities ) ) );

    # Remove duplicates
    my %seen;
    my @unique_severities = grep { !$seen{$_}++ } @expanded_severities;

    # Filter on allowed values
    my %count;
    my @validated_severities;
    foreach my $severity ( @unique_severities, @allowed_severities ) {
        $count{$severity}++;
    }

    foreach my $severity ( keys %count ) {
        if ( $count{$severity} == 2 ) {
            push @validated_severities, $severity;
        }
    }

    # Sort the final list
    my @sorted_severities = sort(@validated_severities);

    return \@sorted_severities;
}

1;
