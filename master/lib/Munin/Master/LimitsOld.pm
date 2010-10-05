package Munin::Master::LimitsOld;
# -*- perl  -*-

=begin comment

This is Munin::Master::LimitsOld, a minimal package shell to make
munin-limits modular (so it can be loaded persistently in a daemon for
example) without making it object oriented yet.  The non-'old' module
will feature propper object orientation like munin-update and will
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

$Id: LimitsOld.pm 3400 2010-03-02 20:06:03Z mha $

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
use Text::Balanced qw ( extract_multiple extract_delimited
    extract_quotelike extract_bracketed );
use Log::Log4perl qw ( :easy );

use Munin::Master::Logger;
use Munin::Master::Utils;
use Munin::Common::Defaults;

my $DEBUG          = 0;
my $conffile       = "$Munin::Common::Defaults::MUNIN_CONFDIR/munin.conf";
my $do_usage       = 0;
my $do_version     = 0;
my @limit_hosts    = ();
my @limit_services = ();
my @limit_contacts = ();
my $stdout         = 0;
my %notes          = ();
my $force          = 0;
my $config;
my $oldnotes;
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
        "debug!"    => \$DEBUG,
        "stdout!"   => \$stdout,
        "force!"    => \$force,
        "version!"  => \$do_version,
        "help"      => \$do_usage
        );

    print_usage_and_exit()   if $do_usage;
    print_version_and_exit() if $do_version;

    exit_if_run_by_super_user();

    $config = &munin_config($conffile);

    logger_open($config->{'logdir'});
    logger_debug() if $DEBUG;
}


sub limits_main {
    my $update_time = Time::HiRes::time;

    my $lockfile = "$config->{rundir}/munin-limits.lock";

    INFO "[INFO] Starting munin-limits, getting lock $lockfile";

    munin_runlock("$config->{rundir}/munin-limits.lock");

    $oldnotes = &munin_readconfig($config->{'dbdir'} . "/limits", 1, 1);

    initialize_for_nagios();

    initialize_contacts();

    process_limits();

    &munin_writeconfig("$config->{dbdir}/limits", \%notes);

    $update_time = sprintf("%.2f", (Time::HiRes::time - $update_time));

    munin_removelock("$config->{rundir}/munin-limits.lock");

    INFO "[INFO] munin-limits finished ($update_time sec)";
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
        $config->{'contact'}->{'old-nagios'}->{'always_send'}
            = "critical warning";
    }
    if (!defined $config->{'contact'}->{'nagios'}->{'always_send'}) {
        $config->{'contact'}->{'nagios'}->{'always_send'} = "critical warning";
    }
}


sub print_usage_and_exit {
    print "Usage: $0 [options]

Options:
    --help		View this message.
    --debug		View debug messages.
    --stdout		Log to stdout as well as the log file.
    --force		Send messages even if they shouldn't normally be sent.
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
	return (get_full_group_path($parent) . " :: " . $name);
    } else {
	return $name;
    }
}

sub process_service {
    my $hash       = shift || return;
    my $hobj       = get_host_node($hash);
    my $service    = munin_get_node_name($hash);
    my $hparentobj = munin_get_parent($hobj);
    my $parent     = munin_get_node_name($hobj);
    my $gparent    = munin_get_node_name($hparentobj);
    my $children   = munin_get_children($hash);

    if (!ref $hash) {
	LOGCROAK("I was passed a non-hash!");
    }

    return if (@limit_services and !grep (/^$service$/, @limit_services));

    DEBUG "[DEBUG] processing service: $service";

    # Some fields that are nice to have in the plugin output
    $hash->{'fields'} = join(' ', map {munin_get_node_name($_)} @$children);
    $hash->{'plugin'} = $service;
    $hash->{'graph_title'} = get_full_service_name($hash);
    $hash->{'host'}  = get_notify_name($hobj);
    $hash->{'group'} = get_full_group_path($hparentobj);
    $hash->{'worst'} = "ok";
    $hash->{'worstid'} = 0 unless defined $hash->{'worstid'};

    foreach my $field (@$children) {
        next if (!defined $field or ref($field) ne "HASH");
        my $fname   = munin_get_node_name($field);
        my $fpath   = munin_get_node_loc($field);
        my $onfield = munin_get_node($oldnotes, $fpath);

	# Test directly here as get_limits is in truth recursive and
	# that fools us when processing multigraphs.
	next if (!defined($field->{warning}) and !defined($field->{critical}));

        my ($warn, $crit, $unknown_limit) = get_limits($field);

        # Skip fields without warning/critical definitions
        next if (!defined $warn and !defined $crit);

        DEBUG "[DEBUG] processing field: " . join('::', @$fpath);

        my $filename = munin_get_rrd_filename($field);
        my $value    = munin_fetch("$filename");

	DEBUG "[DEBUG] rrd filename is: $filename";

        # De-taint.
        if (!defined $value) {
            $value = "unknown";
        }
        else {
            $value = sprintf "%.2f", $value;
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

            if (   !defined $onfield
                or !defined $onfield->{"state"}
                or $onfield->{"state"} ne "unknown") {
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

            if (   !defined $onfield
                or !defined $onfield->{"state"}
                or $onfield->{"state"} ne "critical") {

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

            if (   !defined $onfield
                or !defined $onfield->{"state"}
                or $onfield->{"state"} ne "warning") {

                $hash->{'state_changed'} = 1;

            }
        }
        elsif (defined $onfield and defined $onfield->{"state"} or $force) {
            munin_set_var_loc(\%notes, [@$fpath, "state"], "ok");
            munin_set_var_loc(\%notes, [@$fpath, "ok"],    "OK");

	    if ($onfield->{'state'} ne 'ok' or $force) {
		$hash->{'state_changed'} = 1;
	    }
        }
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
        DEBUG "[DEBUG] processing critical: $name -> $critical[0] : $critical[1]";
    }
    elsif (defined $crit and $crit =~ /^\s*([-+\d.]+)\s*$/) {
        $critical[1] = $1 if defined $1;
        DEBUG "[DEBUG] processing critical: $name -> : $critical[1]";
    }
    elsif (defined $crit) {
        @critical = (0, 0);
        DEBUG "[DEBUG] processing critical: $name -> $critical[0] : $critical[1]";
    }

    if (defined $warn and $warn =~ /^\s*([-+\d.]*):([-+\d.]*)\s*$/) {
        $warning[0] = $1 if length $1;
        $warning[1] = $2 if length $2;
        DEBUG "[DEBUG] processing warning: $name -> $warning[0] : $warning[1]";
    }
    elsif (defined $warn and $warn =~ /^\s*([-+\d.]+)\s*$/) {
        $warning[1] = $1 if defined $1;
        DEBUG "[DEBUG] processing warning: $name -> : $warning[1]";
    }
    elsif (defined $warn) {
        @warning = (0, 0);
        DEBUG "[DEBUG] processing warning: $name -> $warning[0] : $warning[1]";
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
		push @{$stats{$field->{"state"}}}, munin_get_node_name($field);
		if ($field->{"state"} eq "ok") {
		    push @{$stats{"foks"}}, munin_get_node_name($field);
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
        next unless defined $contactobj;
        next unless defined munin_get($contactobj, "command", undef);
        if (@limit_contacts and !grep (/^$c$/, @limit_contacts)) {
            next;
        }
        my $obsess = 0;
        my $cas = munin_get($contactobj, "always_send");
        if (defined $cas) {
            $obsess = grep {scalar(@{$stats{$_}})} (split(/\s+/, lc $cas));
        }
        if (!$hash->{'state_changed'} and !$obsess) {
            next;    # No need to send notification
        }
        DEBUG "state has changed, notifying $c";
        my $precmd = munin_get($contactobj, "command");
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

        # In some cases we want to reopen the command
        my $maxmess = munin_get($contactobj, "max_messages", 0);
        my $curmess = munin_get($contactobj, "num_messages", 0);
        my $curcmd  = munin_get($contactobj, "pipe_command", undef);
        my $pipe    = munin_get($contactobj, "pipe",         undef);
        if ($maxmess and $curmess >= $maxmess) {
            close($pipe);
            $pipe = undef;
            munin_set_var_loc($contactobj, ["pipe"], undef);
            DEBUG "[DEBUG] Closing \"$c\" -> command (max number of messages reached).";
        }
        elsif ($curcmd and $curcmd ne $cmd) {
            close($pipe);
            $pipe = undef;
            munin_set_var_loc($contactobj, ["pipe"], undef);
            DEBUG "[DEBUG] Closing \"$c\" -> command (command has changed).";
        }

        if (!defined $pipe) {
            my @cmd = extract_multiple(
                message_expand($hash, $cmd),
                [sub {extract_delimited($_[0], q{"'})}, qr/\S+/],
                undef, 1
            );
            @cmd = map {
                my $c = $_;
                $c =~ s/['"]$//;
                $c =~ s/^['"]//;
                $c;
            } @cmd;
            $contactobj->{"num_messages"} = 0;
            if ($cmd[0] eq "|") {
                $cmd[0] = "|-";
            }
            elsif ($cmd[0] !~ /^[|>]/) {
                unshift(@cmd, "|-");
            }
            DEBUG("[DEBUG] opening \"$c\" for writing: \""
		  . join('" "', @cmd)
		  . "\".");
            if ($cmd[0] eq ">") {
                ## no critic
                if (!open($pipe, join(' ', @cmd))) {
                    FATAL("[FATAL] Could not open "
			  . join(' ', @cmd[1 .. $#cmd])
			  . " for writing: $!");
                    exit 3;
                }
                ## critic
            }
            else {
                my $pid = open($pipe, "|-");
                if (!defined $pid) {
                    FATAL "Fatal: Unable to  fork: $!";
                    exit 3;
                }
                if (!$pid) {    # Child
                                # Fork of stdout-to-log filter
                    my $logstdout;
                    my $logstderr;
                    my $logpid = open($logstdout, "|-");
                    if (!defined $logpid) {
                        FATAL "Fatal: Unable to  fork: $!";
                        exit 3;
                    }
                    if (!$logpid) {    # Child
                        while (<STDIN>) {
                            chomp;
                            INFO "Command \"$c\" stdout: $_";
                        }
                        exit 0;
                    }
                    close(STDOUT);
                    *STDOUT = \$logstdout;
                    $logpid = open($logstderr, "|-");
                    if (!defined $logpid) {
                        FATAL "Fatal: Unable to  fork: $!";
                        exit 3;
                    }
                    if (!$logpid) {    # Child
                        while (<STDIN>) {
                            chomp;
                            FATAL "Command \"$c\" stderr: $_";
                        }
                        exit 0;
                    }
                    open(STDOUT, ">&", $logstdout);
                    open(STDERR, ">&", $logstderr);

                    exec(@cmd[1 .. $#cmd])
                        or WARN("[WARNING] Could not run command \""
                            . join(' ', @cmd[1 .. $#cmd])
                            . "\": $!");
                    exit 5;

                    # NOTREACHED
                }
            }
            munin_set_var_loc($contactobj, ["pipe_command"], $cmd);
            munin_set_var_loc($contactobj, ["pipe"],         $pipe);
        }
        DEBUG "[DEBUG] sending message: \"$txt\"";
        print $pipe $txt, "\n" if (defined $pipe);
        $contactobj->{"num_messages"}
            = 1 + munin_get($contactobj, "num_messages", 0);   # $num_messages++
    }
}


sub message_expand {
    my $hash = shift;
    my $text = shift;
    my @res  = ();


    while (length($text)) {
        if ($text =~ /^([^\$]+|)(?:\$(\{.*)|)$/) {
            push @res, $1;
            $text = $2;
        }
        my @a = extract_bracketed($text, '{}');
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
            my $check = ($field ne "0" and length($field));
            $check = (!length($field) or $field eq "0") if $n;

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

1;
