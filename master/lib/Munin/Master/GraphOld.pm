package Munin::Master::GraphOld;

# -*- cperl -*-

=encoding utf-8

=begin comment

This is Munin::Master::GraphOld, a package shell to make munin-graph
modular (so it can loaded persistently in munin-cgi-graph for example)
without making it object oriented yet.  The non "old" module will
feature propper object orientation like munin-update and will have to
wait until later.

Copyright (C) 2002-2010 Jimmy Olsen, Audun Ytterdal, Kjell Magne
Øierud, Nicolai Langfeldt, Linpro AS, Redpill Linpro AS and others.

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; version 2 dated June,
1991.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.

$Id$

=end comment

=cut

use warnings;
use strict;

use Exporter;

our (@ISA, @EXPORT);
@ISA    = qw(Exporter);
@EXPORT = qw(graph_startup graph_check_cron graph_main graph_config);

use IO::Socket;
use IO::Handle;
use RRDs;
use POSIX qw(strftime);
use Digest::MD5;
use Getopt::Long;
use Time::HiRes;
use Text::ParseWords;

# For UTF-8 handling (plugins are assumed to use Latin 1)
if ($RRDs::VERSION >= 1.3) {
    use Encode;
    use Encode::Guess;
    Encode->import;
    Encode::Guess->import;
}

use Munin::Master::Logger;
use Munin::Master::Utils;
use Munin::Common::Defaults;

use Log::Log4perl qw( :easy );

# RRDtool 1.2 requires \\: in comments
my $RRDkludge = $RRDs::VERSION < 1.2 ? '' : '\\';

# And RRDtool 1.2.* draws lines with crayons so we hack
# the LINE* options a bit.
my $LINEkluge = 0;
if ($RRDs::VERSION >= 1.2 and $RRDs::VERSION < 1.3) {

    # Only kluge the line widths in RRD 1.2*
    $LINEkluge = 1;
}

# RRD 1.3 has a "ADDNAN" operator which evaluates n + NaN = n instead of = NaN.
my $AddNAN = '+';
if ($RRDs::VERSION >= 1.3) {
    $AddNAN = 'ADDNAN';
}

# the ":dashes" syntax for LINEs is supported since rrdtool 1.5.3
my $RRDLineThresholdAttribute = ($RRDs::VERSION < 1.50003) ? '' : ':dashes';

# Force drawing of "graph no".
my $force_graphing = 0;
my $force_lazy     = 1;
my $do_usage       = 0;
my $do_version     = 0;
my $cron           = 0;
my $list_images    = 0;
my $output_file    = undef;
my $log_file       = undef;
my $skip_locking   = 0;
my $skip_stats     = 0;
my $stdout         = 0;
my $force_run_as_root = 0;
my $conffile       = $Munin::Common::Defaults::MUNIN_CONFDIR . "/munin.conf";
my $libdir         = $Munin::Common::Defaults::MUNIN_LIBDIR;
# Note: Nothing by default is more convenient and elliminates code while
# for cgi graphing - but it breaks how munin-graph expected stuff to work.
# I think.
my %draw           = (
    'day'      => 0,
    'week'     => 0,
    'month'    => 0,
    'year'     => 0,
    'sumyear'  => 0,
    'sumweek'  => 0,
    'pinpoint' => 0,
);
my %init_draw = %draw;
my $pinpoint = {};

my ($size_x, $size_y, $full_size_mode, $only_graph);
my ($lower_limit, $upper_limit);

my %PALETTE;    # Hash of available palettes
my @COLOUR;     # Array of actuall colours to use

{
    no warnings;
    $PALETTE{'old'} = [    # This is the old munin palette.  It lacks contrast.
        qw(22ff22 0022ff ff0000 00aaaa ff00ff
            ffa500 cc0000 0000cc 0080C0 8080C0 FF0080
            800080 688e23 408080 808000 000000 00FF00
            0080FF FF8000 800000 FB31FB
            )];

    $PALETTE{'default'} = [   # New default palette.Better contrast,more colours
            #Greens Blues   Oranges Dk yel  Dk blu  Purple  lime    Reds    Gray
        qw(00CC00 0066B3 FF8000 FFCC00 330099 990099 CCFF00 FF0000 808080
            008F00 00487D B35A00 B38F00         6B006B 8FB300 B30000 BEBEBE
            80FF80 80C9FF FFC080 FFE680 AA80FF EE00CC FF8080
            666600 FFBFFF 00FFCC CC6699 999900
            )];      # Line variations: Pure, earthy, dark pastel, misc colours
}

my $range_colour  = "22ff22";
my $single_colour = "00aa00";

# Use 400 x RRA step, in order to have 1px per RRA sample.
my %times = (
    "day"   => "-2000m",  # (i.e. -33h20m)
    "week"  => "-12000m", # (i.e. -8d13h20m)
    "month" => "-48000m", # (i.e. -33d8h)
    "year"  => "-400d",
    "pinpoint"  => "dummy",
);

my %resolutions = (
    "day"   => "300",
    "week"  => "1500",
    "month" => "7200",
    "year"  => "86400"
);

my %sumtimes = (    # time => [ label, seconds-in-period ]
    "week" => ["hour", 12],
    "year" => ["day",  288]);

# Limit graphing to certain hosts and/or services
my @limit_hosts    = ();
my @limit_services = ();
my $only_fqn = '';

my $watermark = "Munin " . $Munin::Common::Defaults::MUNIN_VERSION;

# RRD param for RRDCACHED_ADDRESS
my @rrdcached_params;

my $running     = 0;
my $max_running = 6;
my $do_fork     = 1;

# "global" Configuration hash
my $config = undef;

# stats file handle
my $STATS;

my @init_limit_hosts = @limit_hosts;
my @init_limit_services = @limit_services;

sub process_pinpoint {
    my ($pinpoint, $arg_name, $arg_value) = @_;
    # XXX - Special hack^h^h^h^h treatment for --pinpoint
    if ($arg_value && $arg_value =~ m/^(\d+),(\d+)$/ ) {
	# "pinpoint" replaces all the other timing options
	$draw{'day'}=0;
	$draw{'week'}=0;
	$draw{'month'}=0;
	$draw{'year'}=0;
	$draw{'sumweek'}=0;
	$draw{'sumyear'}=0;
	$draw{'pinpoint'}=1;
	$$pinpoint->{'start'} = $1; # preparsed values
	$$pinpoint->{'end'} = $2;
    }
}


sub process_fqn {
    my ($fqn, $arg) = @_;

    # Reset what to draw whenever we specify a new fqn

    $draw{'day'} = $draw{'week'} = $draw{'month'} = $draw{'year'} =
      $draw{'sumweek'} = $draw{'sumyear'} = $draw{'pinpoint'} = 0;

    return $arg;
}


sub graph_startup {

    # Parse options and set up.  Stuff that is usually only needed once.
    #
    # Do once pr. run, pr possebly once pr. graph in the case of
    # munin-cgi-graph

    # Localise the stuff, overwise it will be stacked up with CGI
    %draw = %init_draw;
    @limit_hosts = @init_limit_hosts;
    @limit_services = @init_limit_services;

    $pinpoint       = undef;
    my $pinpointopt    = undef;

    $force_graphing = 0;
    $force_lazy     = 1;
    $do_usage       = 0;
    $do_version     = 0;
    $cron           = 0;
    $list_images    = 0;
    $output_file    = undef;
    $log_file       = undef;
    $skip_locking   = 0;
    $skip_stats     = 0;
    $stdout         = 0;

    $size_x 	    = undef;
    $size_y         = undef;
    $full_size_mode = undef;
    $only_graph     = undef;
    $lower_limit    = undef;
    $upper_limit    = undef;

    # Get options
    my ($args) = @_;
    local @ARGV = @{$args};

    # NOTE!  Some of these options are available in graph_main too
    # if you make changes here, make them there too.

    my $debug;
    &print_usage_and_exit
        unless GetOptions (
                "force!"        => \$force_graphing,
                "lazy!"         => \$force_lazy,
                "host=s"        => \@limit_hosts,
                "service=s"     => \@limit_services,
                "only-fqn=s"    => sub{ $only_fqn = process_fqn(@_); },
                "config=s"      => \$conffile,
                "stdout!"       => \$stdout,
                "force-run-as-root!" => \$force_run_as_root,
                "day!"          => \$draw{'day'},
                "week!"         => \$draw{'week'},
                "month!"        => \$draw{'month'},
                "year!"         => \$draw{'year'},
                "pinpoint=s"    => sub{ process_pinpoint(\$pinpoint,@_); },
                "sumweek!"      => \$draw{'sumweek'},
                "sumyear!"      => \$draw{'sumyear'},
		"size_x=i"      => \$size_x,
		"size_y=i"      => \$size_y,
		"full_size_mode!"=> \$full_size_mode,
		"only_graph!"=> \$only_graph,
		"upper_limit=s" => \$upper_limit,
		"lower_limit=s" => \$lower_limit,
                "list-images!"  => \$list_images,
                "o|output-file=s"  => \$output_file,
                "l|log-file=s"  => \$log_file,
                "skip-locking!" => \$skip_locking,
                "skip-stats!"   => \$skip_stats,
                "version!"      => \$do_version,
                "cron!"         => \$cron,
                "fork!"         => \$do_fork,
                "n=n"           => \$max_running,
                "help"          => \$do_usage,
                "debug!"        => \$debug,
        );

    if ($do_version) {
        print_version_and_exit();
    }

    if ($do_usage) {
      print_usage_and_exit();
    }

    exit_if_run_by_super_user() unless $force_run_as_root;

    # Only read $config once (thx Jani M.)
    #
    # FIXME - the loaded $config is stale within 5 minutes.
    # we either need to die or restart ourselves when this
    # happens.
    if (!defined($config)) {
	munin_readconfig_base($conffile);
	# XXX: check if it needs datafile at that point
	$config = munin_readconfig_part('datafile', 0);
    }

    $config->{debug} = $debug;

    my $palette = &munin_get($config, "palette", "default");

    $max_running = &munin_get($config, "max_graph_jobs", $max_running);

    if ($config->{"rrdcached_socket"}) {
	    if ($RRDs::VERSION >= 1.3){
		# Using the RRDCACHED_ADDRESS environnement variable, as
                # it is way less intrusive than the command line args.
                $ENV{RRDCACHED_ADDRESS} = $config->{"rrdcached_socket"};
	    } else {
		    ERROR "[ERROR] RRDCached feature ignored: RRD version must be at least 1.3. Version found: " . $RRDs::VERSION;
	    }
    }


    if ($max_running == 0) {
        $do_fork = 0;
    }

    if (defined($PALETTE{$palette})) {
        @COLOUR = @{$PALETTE{$palette}};
    }
    else {
        die "Unknown palette named by 'palette' keyword: $palette\n";
    }

    return $config;
}

sub graph_check_cron {

    # Are we running from cron and do we have matching graph_strategy
    if (&munin_get($config, "graph_strategy", "cron") ne "cron" and $cron) {

        # Strategy mismatch: We're run from cron, but munin.conf says
        # we use dynamic graph generation
        return 0;
    }

    # Strategy match:
    return 1;
}


sub graph_main {

    my ($args) = @_;
    local @ARGV = @{$args};

    # The loaded $config is stale within 5 minutes.
    # So, we need to reread it when this happens.
    $config = munin_readconfig_part('datafile');

    # Reset an eventual custom size
    $size_x 	    = undef;
    $size_y         = undef;
    $full_size_mode = undef;
    $only_graph     = undef;
    $lower_limit    = undef;
    $upper_limit    = undef;
    $pinpoint       = undef;

    # XXX [DEBUG]
    my $debug = undef;

    GetOptions (
                "host=s"        => \@limit_hosts,
                "only-fqn=s"    => sub { $only_fqn = process_fqn(@_); },
                "day!"          => \$draw{'day'},
                "week!"         => \$draw{'week'},
                "month!"        => \$draw{'month'},
                "year!"         => \$draw{'year'},
                "pinpoint=s"    => sub{ process_pinpoint(\$pinpoint,@_); },
                "sumweek!"      => \$draw{'sumweek'},
                "sumyear!"      => \$draw{'sumyear'},
                "o|output-file=s"  => \$output_file,

                # XXX [DEBUG]
                "debug!"  => \$debug,

		"size_x=i"      => \$size_x,
		"size_y=i"      => \$size_y,
		"full_size_mode!"=> \$full_size_mode,
		"only_graph!"   => \$only_graph,
		"upper_limit=s" => \$upper_limit,
		"lower_limit=s" => \$lower_limit,
	    );

    # XXX [DEBUG]
    logger_debug() if $debug;

    my $graph_time = Time::HiRes::time;

    munin_runlock("$config->{rundir}/munin-graph.lock") unless $skip_locking;

    unless ($skip_stats) {
        open($STATS, '>', "$config->{dbdir}/munin-graph.stats.tmp")
            or WARN "[WARNING] Unable to open $config->{dbdir}/munin-graph.stats.tmp";
        autoflush $STATS 1;
    }

    process_work(@limit_hosts);

    $graph_time = sprintf("%.2f", (Time::HiRes::time - $graph_time));

    rename(
        "$config->{dbdir}/munin-graph.stats.tmp",
        "$config->{dbdir}/munin-graph.stats"
    );
    close $STATS unless $skip_stats;

    munin_removelock("$config->{rundir}/munin-graph.lock") unless $skip_locking;

    $running = wait_for_remaining_children($running);
}


# --------------------------------------------------------------------------

sub get_title {
    my $service = shift;
    my $scale   = shift;

    my $scale_text;
    if ($pinpoint) {
	    my $start_text = localtime($pinpoint->{"start"});
	    my $end_text = localtime($pinpoint->{"end"});
	    $scale_text = "from $start_text to $end_text";
    } else {
        $scale_text = "by " . $scale;
    }

    my $title = munin_get($service, "graph_title", $service);

    # Substitute ${graph_period} in title
    my $period = munin_get($service, "graph_period", "second");
    $title =~ s/\$\{graph_period\}/$period/g;

    return ("$title - $scale_text");
}

sub get_custom_graph_args {
    my $service = shift;
    my $result  = [];

    my $args = munin_get($service, "graph_args");
    if (defined $args) {
        my $result = [ grep /\S/, &quotewords('\s+', 0, $args) ];
        return $result;
    }
    else {
        return;
    }
}

# insert these arguments after all others
# needed for your own VDEF/CDEF/DEF combinations
sub get_custom_graph_args_after {
    my $service = shift;
    my $result  = [];

    my $args = munin_get($service, "graph_args_after");
    if (defined $args) {
        my $result = [&quotewords('\s+', 0, $args)];
        return $result;
    }
    else {
        return;
    }
}

# set a graph end point in the future
# needed for CDEF TREND and PREDICT
sub get_end_offset {
    my $service = shift;

    # get number of seconds in future
    return munin_get($service, "graph_future", 0);
}

sub get_vlabel {
    my $service = shift;
    my $scale   = munin_get($service, "graph_period", "second");
    my $res     = munin_get($service, "graph_vlabel",
        munin_get($service, "graph_vtitle"));

    if (defined $res) {
        $res =~ s/\$\{graph_period\}/$scale/g;
    }
    return $res;
}

sub should_scale {
    my $service = shift;
    my $ret;

    if (!defined($ret = munin_get_bool($service, "graph_scale"))) {
        $ret = !munin_get_bool($service, "graph_noscale", 0);
    }

    return $ret;
}

sub get_header {
    my $service = shift;
    my $scale   = shift;
    my $sum     = shift;
    my $result  = [];
    my $tmp_field;

    # Picture filename
    push @$result, get_picture_filename($service, $scale, $sum || undef);

    # Title
    push @$result, ("--title", get_title($service, $scale));

    # When to start the graph
    if ($pinpoint) {
    	push @$result, "--start", $pinpoint->{start};
    	push @$result, "--end", $pinpoint->{end};
    } else {
    	push @$result, "--start", $times{$scale};
    }

    # Custom graph args, vlabel and graph title
    if (defined($tmp_field = get_custom_graph_args($service))) {
        push(@$result, @{$tmp_field});
    }
    if (defined($tmp_field = get_vlabel($service))) {
        push @$result, ("--vertical-label", $tmp_field);
    }

    push @$result, '--slope-mode' if $RRDs::VERSION >= 1.2;

    push @$result, "--height", ($size_y || munin_get($service, "graph_height", "175"));
    push @$result, "--width",  ($size_x || munin_get($service, "graph_width",  "400"));

    push @$result, "--full-size-mode" if ($full_size_mode);
    push @$result, "--only-graph" if ($only_graph);

    push @$result,"--rigid" if (defined $lower_limit || defined $upper_limit);

    push @$result, "--imgformat", "PNG";
    push @$result, "--lazy" if ($force_lazy);

    push(@$result, "--units-exponent", "0") if (!should_scale($service));

    return $result;
}

sub get_sum_command {
    my $field = shift;
    return munin_get($field, "sum");
}

sub get_stack_command {
    my $field = shift;
    return munin_get($field, "stack");
}

sub expand_specials {
    my $service = shift;
    my $order   = shift;

    my $preproc = [];
    my $single  ;

    # Test if already expanded
    {
        my $cached = $service->{"#%#expand_specials"};
	if (defined $cached) {
		DEBUG "[DEBUG] expand_specials(): already processed " . munin_dumpconfig_as_str($cached);
        	return $cached;
	}
	DEBUG "[DEBUG] expand_specials(): not processed, proceeding for " . munin_dumpconfig_as_str($service);
    }

    # we have to compute the result;
    my $result = [];

    my $fieldnum = 0;

    for my $field (@$order) {    # Search for 'specials'...
        my $tmp_field;

        if ($field =~ /^-(.+)$/) {    # Invisible field
            $field = $1;
            munin_set_var_loc($service, [$field, "graph"], "no");
        }

        $fieldnum++;
        if ($field =~ /^([^=]+)=(.+)$/) {    # Aliased in graph_order
            my $fname = $1;
            my $spath = $2;
            my $src   = munin_get_node_partialpath($service, $spath);
            my $sname = munin_get_node_name($src);

            if(!defined $src) {
	    	ERROR "[ERROR] Failed to find $fname source at $spath, skipping field";
		next;
	    }
            DEBUG "[DEBUG] Copying settings from $sname to $fname.";

            foreach my $foption ("draw", "type", "rrdfile", "fieldname", "info")
            {
                if (!defined $service->{$fname}->{$foption}) {
                    if (defined $src->{$foption}) {
                        munin_set_var_loc($service, [$fname, $foption],
                            $src->{$foption});
                    }
                }
            }

            if (!defined $service->{$fname}->{"label"}) {
                munin_set_var_loc($service, [$fname, "label"], $fname);
            }
            munin_set_var_loc(
                $service,
                [$fname, "filename"],
                munin_get_rrd_filename($src));

        }
        elsif (defined($tmp_field = get_stack_command($service->{$field}))) {
	    # Aliased with .stack
            DEBUG "[DEBUG] expand_specials ($tmp_field): Doing stack...";

            my @spc_stack = ();
            foreach my $pre (split(/\s+/, $tmp_field)) {
                (my $name = $pre) =~ s/=.+//;

                # Auto selects the .draw
                my $draw = (!@spc_stack) ? munin_get($service->{$field}, "draw", "LINE1") : "STACK";
                munin_set_var_loc($service, [$name, "draw"], $draw);

                # Don't process this field later
                munin_set_var_loc($service, [$field, "process"], "0");

                push(@spc_stack, $name);
                push(@$preproc,  $pre);
                push @$result, "$name.label";
                push @$result, "$name.draw";
                push @$result, "$name.cdef";

                munin_set_var_loc($service, [$name, "label"], $name);
                munin_set_var_loc($service, [$name, "cdef"], "$name,UN,0,$name,IF");
                if (munin_get($service->{$field}, "cdef")
                    and !munin_get_bool($service->{$name}, "onlynullcdef", 0)) {
                    DEBUG "[DEBUG] NotOnlynullcdef ($field)...";
                    $service->{$name}->{"cdef"} .= "," . $service->{$field}->{"cdef"};
                    $service->{$name}->{"cdef"} =~ s/\b$field\b/$name/g;
                }
                else {
                    DEBUG "[DEBUG] Onlynullcdef ($field)...";
                    munin_set_var_loc($service, [$name, "onlynullcdef"], 1);
                    push @$result, "$name.onlynullcdef";
                }
            }
        } # if get_stack_command
        elsif (defined($tmp_field = get_sum_command($service->{$field}))) {
            my @spc_stack = ();
            my $last_name = "";
            DEBUG "[DEBUG] expand_specials ($tmp_field): Doing sum...";

            if (@$order == 1
                or (@$order == 2 and munin_get($field, "negative", 0))) {
                $single = 1;
            }

            foreach my $pre (split(/\s+/, $tmp_field)) {
                (my $path = $pre) =~ s/.+=//;
                my $name = "z" . $fieldnum . "_" . scalar(@spc_stack);
                $last_name = $name;

                munin_set_var_loc($service, [$name, "cdef"],
                    "$name,UN,0,$name,IF");
                munin_set_var_loc($service, [$name, "graph"], "no");
                munin_set_var_loc($service, [$name, "label"], $name);
                push @$result, "$name.cdef";
                push @$result, "$name.graph";
                push @$result, "$name.label";

                push(@spc_stack, $name);
                push(@$preproc,  "$name=$pre");
            }
            $service->{$last_name}->{"cdef"} .=
		"," . join(",$AddNAN,", @spc_stack[0 .. @spc_stack - 2]) .
		",$AddNAN";

            if (my $tc = munin_get($service->{$field}, "cdef", 0))
            {    # Oh bugger...
                DEBUG "[DEBUG] Oh bugger...($field)...\n";
                $tc =~ s/\b$field\b/$service->{$last_name}->{"cdef"}/;
                $service->{$last_name}->{"cdef"} = $tc;
            }
            munin_set_var_loc($service, [$field, "process"], "0");
            munin_set_var_loc(
                $service,
                [$last_name, "draw"],
                munin_get($service->{$field}, "draw"));
            munin_set_var_loc(
                $service,
                [$last_name, "colour"],
                munin_get($service->{$field}, "colour"));
            munin_set_var_loc(
                $service,
                [$last_name, "label"],
                munin_get($service->{$field}, "label"));
            munin_set_var_loc(
                $service,
                [$last_name, "graph"],
                munin_get($service->{$field}, "graph", "yes"));

            if (my $tmp = munin_get($service->{$field}, "negative")) {
                munin_set_var_loc($service, [$last_name, "negative"], $tmp);
            }

            munin_set_var_loc($service, [$field, "realname"], $last_name);

        }
        elsif (my $nf = munin_get($service->{$field}, "negative", 0)) {
            if (  !munin_get_bool($service->{$nf}, "graph", 1)
                or munin_get_bool($service->{$nf}, "skipdraw", 0)) {
                munin_set_var_loc($service, [$nf, "graph"], "no");
            }
        }
    } # for (@$order)

    # Return & save it for future use
    $service->{"#%#expand_specials"} = {
	"added" => $result,
	"preprocess" => $preproc,
	"single" => $single,
    };
    return $service->{"#%#expand_specials"};
}


sub single_value {
    my $service = shift;

    my $graphable = munin_get($service, "graphable", 0);
    if (!$graphable) {
        foreach my $field (@{munin_get_field_order($service)}) {
            DEBUG "[DEBUG] single_value: Checking field \"$field\".";
            $graphable++ if munin_draw_field($service->{$field});
        }
        munin_set_var_loc($service, ["graphable"], $graphable);
    }
    DEBUG "[DEBUG] service "
      . join(' :: ', @{munin_get_node_loc($service)})
	. " has $graphable elements.";
    return ($graphable == 1);
}


sub get_field_name {
    my $name = shift;

    $name = substr(Digest::MD5::md5_hex($name), -15)
        if (length $name > 15);

    return $name;
}


sub process_work {
    my (@hosts) = @_;

    # Make array of what is probably needed to graph

    my $work_array = [];

    if ($only_fqn) {
	push @$work_array, munin_find_node_by_fqn($config,$only_fqn);
    } elsif (@hosts) {
        foreach my $nodename (@hosts) {
            push @$work_array,
                map {@{munin_find_field($_->{$nodename}, "graph_title")}}
                @{munin_find_field($config, $nodename)};
        }
    } else {
	FATAL "[FATAL] In process_work, no fqn and no hosts!";
    }

    # @$work_array contains copy of (or pointer to) each service to be graphed.
    for my $service (@$work_array) {

        # Want to avoid forking for that
        next if (skip_service($service));

        # Fork (or not) and run the anonymous sub afterwards.
        fork_and_work(sub {process_service($service);});
    }
}


sub process_field {
    my $field = shift;
    return munin_get_bool($field, "process", 1);
}


sub fork_and_work {
    my ($work) = @_;

    if (!$do_fork) {

        # We're not forking.  Do work and return.
        DEBUG "[DEBUG] Doing work synchronously";
        &$work;
        return;
    }

    # Make sure we don't fork too much
    while ($running >= $max_running) {
        DEBUG
            "[DEBUG] Too many forks ($running/$max_running), wait for something to get done";
        look_for_child("block");
        --$running;
    }

    my $pid = fork();

    if (!defined $pid) {
        ERROR "[ERROR] fork failed: $!";
        die "fork failed: $!";
    }

    if ($pid == 0) {

        # This block does the real work.  Since we're forking exit
        # afterwards.

        &$work;

        # See?!

        exit 0;

    }
    else {
        ++$running;
        DEBUG "[DEBUG] Forked: $pid. Now running $running/$max_running";
        while ($running and look_for_child()) {
            --$running;
        }
    }
}

sub remove_dups {
	my @ret;
	my %keys;
	for my $order (@_) {
                (my $name = $order) =~ s/=.+//;
		push @ret, $order unless ($keys{$name} ++);
	}

	return @ret;
}

sub process_service {
    my ($service) = @_;

    # See if we should skip the service
    return if (skip_service($service));

    # Make my graphs
    my $sname        = munin_get_node_name($service);
    my $skeypath     = munin_get_keypath($service);
    my $service_time = Time::HiRes::time;
    my $lastupdate   = 0;
    my $now          = time;
    my $fnum         = 0;
    my @rrd;

    DEBUG "[DEBUG] Node name: $sname\n";

    my $field_count   = 0;
    my $max_field_len = 0;
    my @field_order   = ();
    my $rrdname;

    @field_order = @{munin_get_field_order($service)};

    # Array to keep 'preprocess'ed fields.
    DEBUG "[DEBUG] Expanding specials for $sname: \""
        . join("\",\"", @field_order) . "\".";

    my $expanded_result = expand_specials($service, \@field_order);
    my $force_single_value = $expanded_result->{single};
    my @added =  @{ $expanded_result->{added} };

    # put preprocessed fields in front
    unshift @field_order, @{ $expanded_result->{preprocess} };

    # Remove duplicates, while retaining the order
    @field_order = remove_dups ( @field_order );

    # Get max label length
    DEBUG "[DEBUG] Checking field lengths for $sname: \"" . join('","', @field_order) . '".';
    $max_field_len = munin_get_max_label_length($service, \@field_order);

    # Global headers makes the value tables easier to read no matter how
    # wide the labels are.
    my $global_headers = 1;

    # Default format for printing under graph.
    my $avgformat;
    my $rrdformat = $avgformat = "%6.2lf";

    if (munin_get($service, "graph_args", "") =~ /--base\s+1024/) {

        # If the base unit is 1024 then 1012.56 is a valid
        # number to show.  That's 7 positions, not 6.
        $rrdformat = $avgformat = "%7.2lf";
    }

    # Plugin specified complete printf format
    $rrdformat = munin_get($service, "graph_printf", $rrdformat);

    my $rrdscale = '';
    if (munin_get_bool($service, "graph_scale", 1)) {
        $rrdscale = '%s';
    }

    # Array to keep negative data until we're finished with positive.
    my @rrd_negatives = ();

    my $filename;
    my %total_pos;
    my %total_neg;
    my $autostacking = 0;

    DEBUG "[DEBUG] Treating fields \"" . join("\",\"", @field_order) . "\".";
    for my $fname (@field_order) {
        my $path  = undef;
        my $field = undef;

        if ($fname =~ s/=(.+)//) {
            $path = $1;
        }
        $field = munin_get_node($service, [$fname]);

        next if (!defined $field or !$field or !process_field($field));
        DEBUG "[DEBUG] Processing field \"$fname\" ["
            . munin_get_node_name($field) . "].";

        my $fielddraw = munin_get($field, "draw", "LINE1");

        if ($field_count == 0 and $fielddraw eq 'STACK') {

            # Illegal -- first field is a STACK
            DEBUG "ERROR: First field (\"$fname\") of graph "
                . join(' :: ', munin_get_node_loc($service))
                . " is STACK. STACK can only be drawn after a LINEx or AREA.";
            $fielddraw = "LINE1";
        }

        if ($fielddraw eq 'AREASTACK') {
            if ($autostacking == 0) {
                $fielddraw    = 'AREA';
                $autostacking = 1;
            }
            else {
                $fielddraw = 'STACK';
            }
        }

        if ($fielddraw =~ /LINESTACK(\d+(?:.\d+)?)/) {
            if ($autostacking == 0) {
                $fielddraw    = "LINE$1";
                $autostacking = 1;
            }
            else {
                $fielddraw = 'STACK';
            }
        }

        # Getting name of rrd file
        $filename = munin_get_rrd_filename($field, $path);
	if (! $filename) {
		ERROR "[ERROR] filename is empty for " . munin_dumpconfig_as_str($field) . ", $path";
		# Ignore this field
		next;
	}

	if(!defined $filename) {
		ERROR "[ERROR] Failed getting filename for $path, skipping field";
		next;
	}
	# Here it is OK to flush the rrdcached, since we'll flush it anyway
	# with graph
        my $update = RRDs::last(@rrdcached_params, $filename);
        $update = 0 if !defined $update;
        if ($update > $lastupdate) {
            $lastupdate = $update;
        }

        # It does not look like $fieldname.rrdfield is possible to set
        my $rrdfield = munin_get($field, "rrdfield", "42");

        my $single_value = $force_single_value || single_value($service);
	
	# XXX - single_value is wrong for some multigraph, disabling it for now
	$single_value = 0;

        my $has_negative = munin_get($field, "negative");

        # Trim the fieldname to make room for other field names.
	
        $rrdname = &get_field_name($fname);

        reset_cdef($service, $rrdname);
        if ($rrdname ne $fname) {

            # A change was made
        	munin_set($field, "cdef_name", $rrdname);
        }

        # Push will place the DEF too far down for some CDEFs to work
        unshift(@rrd, "DEF:g$rrdname=" . $filename . ":" . $rrdfield . ":AVERAGE");
        unshift(@rrd, "DEF:i$rrdname=" . $filename . ":" . $rrdfield . ":MIN");
        unshift(@rrd, "DEF:a$rrdname=" . $filename . ":" . $rrdfield . ":MAX");

        if (munin_get_bool($field, "onlynullcdef", 0)) {
            push(@rrd,
                "CDEF:c$rrdname=g$rrdname"
                    . (($now - $update) > 900 ? ",POP,UNKN" : ""));
        }

        if (    munin_get($field, "type", "GAUGE") ne "GAUGE"
            and graph_by_minute($service)) {
            push(@rrd, expand_cdef($service, \$rrdname, "$fname,60,*"));
        }
        if (    munin_get($field, "type", "GAUGE") ne "GAUGE"
            and graph_by_hour($service)) {
            push(@rrd, expand_cdef($service, \$rrdname, "$fname,3600,*"));
        }

        if (my $tmpcdef = munin_get($field, "cdef")) {
            push(@rrd, expand_cdef($service, \$rrdname, $tmpcdef));
            push(@rrd, "CDEF:c$rrdname=g$rrdname");
            DEBUG "[DEBUG] Field name after cdef set to $rrdname";
        }
        elsif (!munin_get_bool($field, "onlynullcdef", 0)) {
            push(@rrd,
                "CDEF:c$rrdname=g$rrdname"
                    . (($now - $update) > 900 ? ",POP,UNKN" : ""));
        }

        next if !munin_draw_field($field);
        DEBUG "[DEBUG] Drawing field \"$fname\".";

        if ($single_value) {

            # Only one field. Do min/max range.
            push(@rrd, "CDEF:min_max_diff=a$rrdname,i$rrdname,-");
            push(@rrd, "CDEF:re_zero=min_max_diff,min_max_diff,-")
                if !munin_get($field, "negative");

            push(@rrd, "AREA:i$rrdname#ffffff");
            push(@rrd, "STACK:min_max_diff#$range_colour");
            push(@rrd, "LINE1:re_zero#000000")
                if !munin_get($field, "negative");
        }

        # Push "global" headers or not
        if ($has_negative and !@rrd_negatives and $global_headers < 2) {

            # Always for -/+ graphs
            push(@rrd, "COMMENT:" . (" " x $max_field_len));
            push(@rrd, "COMMENT:Cur (-/+)");
            push(@rrd, "COMMENT:Min (-/+)");
            push(@rrd, "COMMENT:Avg (-/+)");
            push(@rrd, "COMMENT:Max (-/+) \\j");
            $global_headers = 2;    # Avoid further headers/labels
        }
        elsif ($global_headers == 1) {

            # Or when we want to.
            push(@rrd, "COMMENT:" . (" " x $max_field_len));
            push(@rrd, "COMMENT: Cur$RRDkludge:");
            push(@rrd, "COMMENT:Min$RRDkludge:");
            push(@rrd, "COMMENT:Avg$RRDkludge:");
            push(@rrd, "COMMENT:Max$RRDkludge:  \\j");
            $global_headers = 2;    # Avoid further headers/labels
        }

        my $colour = munin_get($field, "colour");

	if ($colour && $colour =~ /^COLOUR(\d+)$/) {
		$colour = $COLOUR[$1 % @COLOUR];
	}
	
	# Select a default colour if no explict one
	$colour ||= ($single_value) ? $single_colour : $COLOUR[$field_count % @COLOUR];
        my $warn_colour = $single_value ? "ff0000" : $colour;

        # colour needed for transparent predictions and trends
        munin_set($field, "colour", $colour);
        $field_count++;

        my $tmplabel = munin_get($field, "label", $fname);

	# Substitute ${graph_period}
	my $period  = munin_get($service, "graph_period", "second");
	$tmplabel =~ s/\$\{graph_period\}/$period/g;

        push(@rrd,
                  $fielddraw
                . ":g$rrdname"
                . "#$colour" . ":"
                . escape($tmplabel)
                . (" " x ($max_field_len + 1 - length $tmplabel)));

        # Check for negative fields (typically network (or disk) traffic)
        if ($has_negative) {
            my $negfieldname
                = orig_to_cdef($service, munin_get($field, "negative"));
            my $negfield = $service->{$negfieldname};
            if (my $tmpneg = munin_get($negfield, "realname")) {
                $negfieldname = $tmpneg;
                $negfield     = $service->{$negfieldname};
            }

            if (!@rrd_negatives) {

                # zero-line, to redraw zero afterwards.
                push(@rrd_negatives, "CDEF:re_zero=g$negfieldname,UN,0,0,IF");
            }

            push(@rrd_negatives, "CDEF:ng$negfieldname=g$negfieldname,-1,*");

            if ($single_value) {

                # Only one field. Do min/max range.
                push(@rrd,
                    "CDEF:neg_min_max_diff=i$negfieldname,a$negfieldname,-");
                push(@rrd, "CDEF:ni$negfieldname=i$negfieldname,-1,*");
                push(@rrd, "AREA:ni$negfieldname#ffffff");
                push(@rrd, "STACK:neg_min_max_diff#$range_colour");
            }

            push(@rrd_negatives, $fielddraw . ":ng$negfieldname#$colour");

            # Draw HRULEs
            my $linedef = munin_get($negfield, "line");
            if ($linedef) {
                my ($number, $ldcolour, $label) = split(/:/, $linedef, 3);
                unshift(@rrd_negatives,
                    "HRULE:" . $number . ($ldcolour ? "#$ldcolour" : "#$colour"));
            }
            elsif (my $tmpwarn = munin_get($negfield, "warning")) {

                my ($warn_min, $warn_max) = split(':', $tmpwarn,2);

                if (defined($warn_min) and $warn_min ne '') {
                    unshift(@rrd, "HRULE:${warn_min}#${warn_colour}${RRDLineThresholdAttribute}");
                }
                if (defined($warn_max) and $warn_max ne '') {
                    unshift(@rrd, "HRULE:${warn_max}#${warn_colour}${RRDLineThresholdAttribute}");
                }
            }

            push(@rrd,
                "GPRINT:c$negfieldname:LAST:$rrdformat" . $rrdscale . "/\\g");
            push(@rrd, "GPRINT:c$rrdname:LAST:$rrdformat" . $rrdscale . "");
            push(@rrd,
                "GPRINT:i$negfieldname:MIN:$rrdformat" . $rrdscale . "/\\g");
            push(@rrd, "GPRINT:i$rrdname:MIN:$rrdformat" . $rrdscale . "");
            push(@rrd,
                      "GPRINT:g$negfieldname:AVERAGE:$avgformat"
                    . $rrdscale
                    . "/\\g");
            push(@rrd, "GPRINT:g$rrdname:AVERAGE:$avgformat" . $rrdscale . "");
            push(@rrd,
                "GPRINT:a$negfieldname:MAX:$rrdformat" . $rrdscale . "/\\g");
            push(@rrd, "GPRINT:a$rrdname:MAX:$rrdformat" . $rrdscale . "\\j");
            push(@{$total_pos{'min'}}, "i$rrdname");
            push(@{$total_pos{'avg'}}, "g$rrdname");
            push(@{$total_pos{'max'}}, "a$rrdname");
            push(@{$total_neg{'min'}}, "i$negfieldname");
            push(@{$total_neg{'avg'}}, "g$negfieldname");
            push(@{$total_neg{'max'}}, "a$negfieldname");
        }
        else {
            push(@rrd, "COMMENT: Cur$RRDkludge:") unless $global_headers;
            push(@rrd, "GPRINT:c$rrdname:LAST:$rrdformat" . $rrdscale . "");
            push(@rrd, "COMMENT: Min$RRDkludge:") unless $global_headers;
            push(@rrd, "GPRINT:i$rrdname:MIN:$rrdformat" . $rrdscale . "");
            push(@rrd, "COMMENT: Avg$RRDkludge:") unless $global_headers;
            push(@rrd, "GPRINT:g$rrdname:AVERAGE:$avgformat" . $rrdscale . "");
            push(@rrd, "COMMENT: Max$RRDkludge:") unless $global_headers;
            push(@rrd, "GPRINT:a$rrdname:MAX:$rrdformat" . $rrdscale . "\\j");
            push(@{$total_pos{'min'}}, "i$rrdname");
            push(@{$total_pos{'avg'}}, "g$rrdname");
            push(@{$total_pos{'max'}}, "a$rrdname");
        }

        # Draw HRULEs
        my $linedef = munin_get($field, "line");
        if ($linedef) {
            my ($number, $ldcolour, $label) = split(/:/, $linedef, 3);
            $label =~ s/:/\\:/g if defined $label;
            unshift(
                @rrd,
                "HRULE:"
                    . $number
                    . (
                    $ldcolour ? "#$ldcolour"
                    : ((defined $single_value and $single_value) ? "#ff0000"
                        : "#$colour"))
                    . ((defined $label and length($label)) ? ":$label" : ""),
                "COMMENT: \\j"
            );
        }
        elsif (my $tmpwarn = munin_get($field, "warning")) {

            my ($warn_min, $warn_max) = split(':', $tmpwarn,2);

            if (defined($warn_min) and $warn_min ne '') {
                unshift(@rrd, "HRULE:${warn_min}#${warn_colour}${RRDLineThresholdAttribute}");
            }
            if (defined($warn_max) and $warn_max ne '') {
                unshift(@rrd, "HRULE:${warn_max}#${warn_colour}${RRDLineThresholdAttribute}");
            }
        }
    }

    my $graphtotal = munin_get($service, "graph_total");
    if (@rrd_negatives) {
        push(@rrd, @rrd_negatives);
        push(@rrd, "LINE1:re_zero#000000");    # Redraw zero.
        if (    defined $graphtotal
            and exists $total_pos{'min'}
            and exists $total_neg{'min'}
            and @{$total_pos{'min'}}
            and @{$total_neg{'min'}}) {

            push(@rrd,
                      "CDEF:ipostotal="
                    . join(",", @{$total_pos{'min'}})
                    . (",$AddNAN" x (@{$total_pos{'min'}} - 1)));
            push(@rrd,
                      "CDEF:gpostotal="
                    . join(",", @{$total_pos{'avg'}})
                    . (",$AddNAN" x (@{$total_pos{'avg'}} - 1)));
            push(@rrd,
                      "CDEF:apostotal="
                    . join(",", @{$total_pos{'max'}})
                    . (",$AddNAN" x (@{$total_pos{'max'}} - 1)));
            push(@rrd,
                      "CDEF:inegtotal="
                    . join(",", @{$total_neg{'min'}})
                    . (",$AddNAN" x (@{$total_neg{'min'}} - 1)));
            push(@rrd,
                      "CDEF:gnegtotal="
                    . join(",", @{$total_neg{'avg'}})
                    . (",$AddNAN" x (@{$total_neg{'avg'}} - 1)));
            push(@rrd,
                      "CDEF:anegtotal="
                    . join(",", @{$total_neg{'max'}})
                    . (",$AddNAN" x (@{$total_neg{'max'}} - 1)));
            push(@rrd,
                "LINE1:gpostotal#000000:$graphtotal"
                    . (" " x ($max_field_len - length($graphtotal) + 1)));
            push(@rrd, "GPRINT:gnegtotal:LAST:$rrdformat" . $rrdscale . "/\\g");
            push(@rrd, "GPRINT:gpostotal:LAST:$rrdformat" . $rrdscale . "");
            push(@rrd, "GPRINT:inegtotal:MIN:$rrdformat" . $rrdscale . "/\\g");
            push(@rrd, "GPRINT:ipostotal:MIN:$rrdformat" . $rrdscale . "");
            push(@rrd,
                "GPRINT:gnegtotal:AVERAGE:$avgformat" . $rrdscale . "/\\g");
            push(@rrd, "GPRINT:gpostotal:AVERAGE:$avgformat" . $rrdscale . "");
            push(@rrd, "GPRINT:anegtotal:MAX:$rrdformat" . $rrdscale . "/\\g");
            push(@rrd, "GPRINT:apostotal:MAX:$rrdformat" . $rrdscale . "\\j");
        }
    }
    elsif ( defined $graphtotal
        and exists $total_pos{'min'}
        and @{$total_pos{'min'}}) {
        push(@rrd,
                  "CDEF:ipostotal="
                . join(",", @{$total_pos{'min'}})
                . (",$AddNAN" x (@{$total_pos{'min'}} - 1)));
        push(@rrd,
                  "CDEF:gpostotal="
                . join(",", @{$total_pos{'avg'}})
                . (",$AddNAN" x (@{$total_pos{'avg'}} - 1)));
        push(@rrd,
                  "CDEF:apostotal="
                . join(",", @{$total_pos{'max'}})
                . (",$AddNAN" x (@{$total_pos{'max'}} - 1)));

        push(@rrd,
            "LINE1:gpostotal#000000:$graphtotal"
                . (" " x ($max_field_len - length($graphtotal) + 1)));
        push(@rrd, "COMMENT: Cur$RRDkludge:") unless $global_headers;
        push(@rrd, "GPRINT:gpostotal:LAST:$rrdformat" . $rrdscale . "");
        push(@rrd, "COMMENT: Min$RRDkludge:") unless $global_headers;
        push(@rrd, "GPRINT:ipostotal:MIN:$rrdformat" . $rrdscale . "");
        push(@rrd, "COMMENT: Avg$RRDkludge:") unless $global_headers;
        push(@rrd, "GPRINT:gpostotal:AVERAGE:$avgformat" . $rrdscale . "");
        push(@rrd, "COMMENT: Max$RRDkludge:") unless $global_headers;
        push(@rrd, "GPRINT:apostotal:MAX:$rrdformat" . $rrdscale . "\\j");
    }
		
    # insert these graph args in the end
    if (defined(my $tmp_field = get_custom_graph_args_after($service))) {
        push(@rrd, @{$tmp_field});
    }



    my $nb_graphs_drawn = 0;
    for my $time (keys %times) {
        next unless ($draw{$time});
        my $picfilename = get_picture_filename($service, $time);
	DEBUG "[DEBUG] Looking into drawing $picfilename";
        (my $picdirname = $picfilename) =~ s/\/[^\/]+$//;

        DEBUG "[DEBUG] Picture filename: $picfilename";

        my @complete = get_fonts();

	# Watermarks introduced in RRD 1.2.13.
        push(@complete, '-W', $watermark) if $RRDs::VERSION >= 1.2013;

        # Do the header (title, vtitle, size, etc...), but IN THE BEGINNING
        unshift @complete, @{get_header($service, $time)};

        if ($LINEkluge) {
            @rrd = map {
                my $line = $_;
                $line =~ s/LINE3:/LINE2.2:/;
                $line =~ s/LINE2:/LINE1.6:/;

                # LINE1 is thin enough.
                $line;
            } @rrd;
        }
        push @complete, @rrd;

        # graph end in future
        push (@complete, handle_trends($time, $lastupdate, $pinpoint, $service, $RRDkludge, @added));

        # Make sure directory exists
        munin_mkdir_p($picdirname, oct(777));

        # Since version 1.3 rrdtool uses libpango which needs its input
        # as utf8 string. So we assume that every input is in latin1
        # and decode it to perl's internal representation and then to utf8.

        if ($RRDs::VERSION >= 1.3) {
            @complete = map {
                my $str = $_;
                my $utf8 = guess_encoding($str, 'utf8');
                ref $utf8 ? $str : encode("utf8", (decode("latin1", $_)));
            } @complete;
        }

	# Surcharging the graphing limits
	my ($upper_limit_overrided, $lower_limit_overrided);
	for (my $index = 0; $index <= $#complete; $index++) {
		if ($complete[$index] =~ /^(--upper-limit|-u)$/ && (defined $upper_limit)) {
			$upper_limit = get_scientific($upper_limit);
			$complete[$index + 1] = $upper_limit;
			$upper_limit_overrided = 1;
		}
		if ($complete[$index] =~ /^(--lower-limit|-l)$/ && (defined $lower_limit)) {
			$lower_limit = get_scientific($lower_limit);
			$complete[$index + 1] = $lower_limit;
			$lower_limit_overrided = 1;
		}
	}

	# Add the limit if not present
	if (defined $upper_limit && ! $upper_limit_overrided) {
		push @complete, "--upper-limit", $upper_limit;
	}
	if (defined $lower_limit && ! $lower_limit_overrided) {
		push @complete, "--lower-limit", $lower_limit;
	}

	DEBUG "\n\nrrdtool 'graph' '" . join("' \\\n\t'", @rrdcached_params, @complete) . "'\n";
	$nb_graphs_drawn ++;
        RRDs::graph(@rrdcached_params, @complete);
        if (my $ERROR = RRDs::error) {
            ERROR "[RRD ERROR] Unable to graph $picfilename : $ERROR";
            # ALWAYS dumps the cmd used when an error occurs.
            # Otherwise, it will be difficult to debug post-mortem
            ERROR "[RRD ERROR] rrdtool 'graph' '" . join("' \\\n\t'", @rrdcached_params, @complete) . "'\n";
        }
        elsif (!-f $picfilename) {
		ERROR "[RRD ERROR] rrdtool graph did not generate the image (make sure there are data to graph).\n";
        }
        else {

            # Set time of png file to the time of the last update of
            # the rrd file.  This makes http's If-Modified-Since more
            # reliable, esp. in combination with munin-*cgi-graph.

	    # Since this disrupts rrd's --lazy option we're disableing
	    # it unless we (munin-graph) were specially asked --lazy.
	    # This way --lazy continues to work as expected, and since
	    # CGI uses --nolazy, http IMS are also working as expected.
            if (! $force_lazy) {
                DEBUG "[DEBUG] setting time on $picfilename";
                utime $lastupdate, $lastupdate, $picfilename;
            }

            if ($list_images) {
                # Command-line option to list images created
                print $picfilename. "\n";
            }
        }
    }

    if (munin_get_bool($service, "graph_sums", 0)) {
        foreach my $time (keys %sumtimes) {
            my $picfilename = get_picture_filename($service, $time, 1);
	    DEBUG "Looking into drawing $picfilename";
            (my $picdirname = $picfilename) =~ s/\/[^\/]+$//;
            next unless ($draw{"sum" . $time});
            my @rrd_sum;
            push @rrd_sum, @{get_header($service, $time, 1)};

            # graph end in future
            push (@rrd_sum, handle_trends($time, $lastupdate, $pinpoint, $service, $RRDkludge, @added));

            push @rrd_sum, @rrd;

            my $labelled = 0;
            my @defined  = ();
            for (my $index = 0; $index <= $#rrd_sum; $index++) {
                if ($rrd_sum[$index] =~ /^(--vertical-label|-v)$/) {
                    (my $label = munin_get($service, "graph_vlabel"))
                        =~ s/\$\{graph_period\}/$sumtimes{$time}[0]/g;
                    splice(@rrd_sum, $index, 2, ("--vertical-label", $label));
                    $index++;
                    $labelled++;
                }
                elsif ($rrd_sum[$index]
                    =~ /^(LINE[123]|STACK|AREA|GPRINT):([^#:]+)([#:].+)$/) {
                    my ($pre, $fname, $post) = ($1, $2, $3);
                    next if $fname eq "re_zero";
                    if ($post =~ /^:AVERAGE/) {
                        splice(@rrd_sum, $index, 1, $pre . ":x$fname" . $post);
                        $index++;
                        next;
                    }
                    next if grep /^x$fname$/, @defined;
                    push @defined, "x$fname";
                    my @replace;

                    if (munin_get($service->{$fname}, "type", "GAUGE") ne
                        "GAUGE") {
                        if ($time eq "week") {

                            # Every plot is half an hour. Add two plots and multiply, to get per hour
                            if (graph_by_minute($service)) {

                                # Already multiplied by 60
                                push @replace,
                                    "CDEF:x$fname=PREV($fname),UN,0,PREV($fname),IF,$fname,+,5,*,6,*";
                            } elsif (graph_by_hour($service)) {
                                # Already multiplied by 3600, have to *divide* by 12
                                push @replace,
                                    "CDEF:x$fname=PREV($fname),UN,0,PREV($fname),IF,$fname,+,12,/,6,*";
                            }
                            else {
                                push @replace,
                                    "CDEF:x$fname=PREV($fname),UN,0,PREV($fname),IF,$fname,+,300,*,6,*";
                            }
                        }
                        else {

                            # Every plot is one day exactly. Just multiply.
                            if (graph_by_minute($service)) {

                                # Already multiplied by 60
                                push @replace, "CDEF:x$fname=$fname,5,*,288,*";
                            } elsif (graph_by_hour($service)) {
                                # Already multiplied by 3600, have to *divide* by 12
                                push @replace, "CDEF:x$fname=$fname,12,/,288,*";
                            }
                            else {
                                push @replace,
                                    "CDEF:x$fname=$fname,300,*,288,*";
                            }
                        }
                    }
                    push @replace, $pre . ":x$fname" . $post;
                    splice(@rrd_sum, $index, 1, @replace);
                    $index++;
                }
                elsif (
                    $rrd_sum[$index] =~ /^(--lower-limit|--upper-limit|-l|-u)$/)
                {
                    $index++;
                    $rrd_sum[$index]
                        = $rrd_sum[$index] * 300 * $sumtimes{$time}->[1];
                }
            }


            unless ($labelled) {
                my $label = munin_get($service, "graph_vlabel_sum_$time",
                    $sumtimes{$time}->[0]);
                unshift @rrd_sum, "--vertical-label", $label;
            }

	    DEBUG "[DEBUG] \n\nrrdtool graph '" . join("' \\\n\t'", @rrd_sum) . "'\n";

            # Make sure directory exists
            munin_mkdir_p($picdirname, oct(777));

	    $nb_graphs_drawn ++;
            RRDs::graph(@rrdcached_params, @rrd_sum);

            if (my $ERROR = RRDs::error) {
                ERROR "[RRD ERROR(sum)] Unable to graph "
                    . get_picture_filename($service, $time)
                    . ": $ERROR";
            }
            elsif ($list_images) {
                # Command-line option to list images created
                print get_picture_filename ($service, $time, 1), "\n";
            }
        } # foreach (keys %sumtimes)
    } # if graph_sums

    $service_time = sprintf("%.2f", (Time::HiRes::time - $service_time));
    DEBUG "[DEBUG] Graphed service $skeypath ($service_time sec for $nb_graphs_drawn graphs)";
    print $STATS "GS|$service_time\n" unless $skip_stats;

    foreach (@added) {
        delete $service->{$_} if exists $service->{$_};
    }
    @added = ();
}

# sets enddate --end and draws a vertical ruler if enddate is in the future
# future trends are also added to the graph here
sub handle_trends {
    my $time = shift;
    my $lastupdate = shift;
    my $pinpoint = shift;
    my $service = shift;
    my $RRDkludge = shift;
    my @added = @_;
    my @complete;

    # enddate possibly in future
    my $futuretime = $pinpoint ? 0 : $resolutions{$time} * get_end_offset($service);
    my $enddate = time + ($futuretime);
    DEBUG "[DEBUG] lastupdate: $lastupdate, enddate: $enddate\n";

    # future begins at this horizontal ruler
    if ($enddate > $lastupdate) {
        push(@complete, "VRULE:$lastupdate#999999");
    }

    # create trends/predictions
    foreach my $field (@{munin_find_field($service, "label")}) {
        my $fieldname = munin_get_node_name($field);
	my $colour = $single_colour;

	# Skip virtual fieldnames, otherwise beware of $hash->{foo}{bar}.
	#
	# On a sidenote, what's the output of the following code ?
	# perl -e '$a = {}; if ($a->{foo}{bar}) { print "Found Foo/Bar\n"; } \
	#        if ($a->{foo}) { print "Found Foo\n"; }'
	next if ! defined $service->{$fieldname};

        if (defined $service->{$fieldname}{'colour'}) {
            $colour = "$service->{$fieldname}{'colour'}66";
        }

        my $rrd_fieldname = get_field_name($fieldname);

        my $cdef = "";
        if (defined $service->{$fieldname}{'cdef'}) {
            $cdef = "cdef";
        }

        #trends
        if (defined $service->{$fieldname}{'trend'} and $service->{$fieldname}{'trend'} eq 'yes') {
            push (@complete, "CDEF:t$rrd_fieldname=c$cdef$rrd_fieldname,$futuretime,TRENDNAN");
            push (@complete, "LINE1:t$rrd_fieldname#$colour:$service->{$fieldname}->{'label'} trend\\l");
            DEBUG "[DEBUG] set trend for $fieldname\n";
        }

        #predictions
        if (defined $service->{$fieldname}{'predict'}) {
            #arguments: pattern length (e.g. 1 day), smoothing (multiplied with timeresolution)
            my @predict = split(",", $service->{$fieldname}{'predict'});
            my $predictiontime = int ($futuretime / $predict[0]) + 2; #2 needed for 1 day
            my $smooth = $predict[1]*$resolutions{$time};
            push (@complete, "CDEF:p$rrd_fieldname=$predict[0],-$predictiontime,$smooth,c$cdef$rrd_fieldname,PREDICT");
            push (@complete, "LINE1:p$rrd_fieldname#$colour:$service->{$fieldname}->{'label'} prediction\\l");
            DEBUG "[DEBUG] set prediction for $fieldname\n";
        }
    }


    push(@complete,
        "COMMENT:Last update$RRDkludge: "
        . RRDescape(scalar localtime($lastupdate))
        . "\\r");

    # If pinpointing, --end should *NOT* be changed
    if (! $pinpoint) {
            if (@added) { # stop one period earlier if it's a .sum or .stack
                push @complete, "--end",
                    (int(($enddate-$resolutions{$time}) / $resolutions{$time})) * $resolutions{$time};
            } else {
                push @complete, "--end",
                    (int($enddate / $resolutions{$time})) * $resolutions{$time};
            }
    }

    return @complete;
}

sub get_fonts {
    # Set up rrdtool graph font options according to RRD version.
    my @options;

    if ($RRDs::VERSION < 1.2) {
	# RRD before 1.2, no font options
    } elsif ($RRDs::VERSION < 1.3) {
	# RRD 1.2
	# The RRD 1.2 documentation says you can identify font family
	# names but I never got that to work, but full font path worked
	@options = (
		'--font', "LEGEND:7:$libdir/DejaVuSansMono.ttf",
		'--font', "UNIT:7:$libdir/DejaVuSans.ttf",
		'--font', "AXIS:7:$libdir/DejaVuSans.ttf",
	       );
    } else {
	# At least 1.3
	@options = (
		'--font', 'DEFAULT:0:DejaVuSans,DejaVu Sans,DejaVu LGC Sans,Bitstream Vera Sans',
		'--font', 'LEGEND:7:DejaVuSansMono,DejaVu Sans Mono,DejaVu LGC Sans Mono,Bitstream Vera Sans Mono,monospace',
		# Colors coordinated with CSS.
		'--color',  'BACK#F0F0F0',   # Area around the graph
		'--color',  'FRAME#F0F0F0',  # Line around legend spot
		'--color',  'CANVAS#FFFFFF', # Graph background, max contrast
		'--color',  'FONT#666666',   # Some kind of gray
		'--color',  'AXIS#CFD6F8',   # And axis like html boxes
		'--color',  'ARROW#CFD6F8',  # And arrow, ditto.
	       );
    }

    if ($RRDs::VERSION >= 1.4) {
	# RRD 1.4 has border, adding it
	push @options, (
		'--border',  '0',
	       );
    }

    return @options;
};


sub graph_by_minute {
    my $service = shift;

    return (munin_get($service, "graph_period", "second") eq "minute");
}

sub graph_by_hour {
    my $service = shift;

    return (munin_get($service, "graph_period", "second") eq "hour");
}

sub orig_to_cdef {
    my $service   = shift;
    my $fieldname = shift;

    return unless ref($service) eq "HASH";

    if (defined $service->{$fieldname} && defined $service->{$fieldname}->{"cdef_name"}) {
        return orig_to_cdef($service, $service->{$fieldname}->{"cdef_name"});
    }
    return $fieldname;
}

sub reset_cdef {
	my $service = shift;
	my $fieldname = shift;
	return unless ref($service) eq "HASH";
	if (defined $service->{$fieldname} && defined $service->{$fieldname}->{"cdef_name"}) {
		reset_cdef($service, $service->{$fieldname}->{"cdef_name"});
		delete $service->{$fieldname}->{"cdef_name"};
	}
}

sub ends_with {
    my ($src, $searched) = @_;

    my $is_ending = (substr($src, - length($searched)) eq $searched);
    return $is_ending;
}


sub skip_service {
    my $service = shift;
    my $fqn   = munin_get_node_fqn($service);

    # Skip if we've limited services with the omnipotent cli option only-fqn
    return 1 if ($only_fqn and ! ends_with($fqn, $only_fqn));
    DEBUG "[DEBUG] $fqn is in ($only_fqn)\n";

    # Skip if we've limited services with cli options
    return 1
      if (@limit_services and
	  ! (grep { ends_with($fqn, $_) } @limit_services));

    DEBUG "[DEBUG] $fqn is in (" . join(",", @limit_services) . ")\n";

    # Always graph if --force is present
    return 0 if $force_graphing;

    # See if we should skip it because of conf-options
    return 1
        if (munin_get($service, "graph", "yes") eq "on-demand"
        or !munin_get_bool($service, "graph", 1));

    # Don't skip
    return 0;
}


sub expand_cdef {
    my $service    = shift;
    my $cfield_ref = shift;
    my $cdef       = shift;

    my $new_field = &get_field_name("cdef$$cfield_ref");

    my ($max, $min, $avg) = (
        "CDEF:a$new_field=$cdef", "CDEF:i$new_field=$cdef",
        "CDEF:g$new_field=$cdef"
    );

    foreach my $field (@{munin_find_field($service, "label")}) {
        my $fieldname = munin_get_node_name($field);
        my $rrdname = &orig_to_cdef($service, $fieldname);
        if ($cdef =~ /\b$fieldname\b/) {
            $max =~ s/(?<=[,=(])$fieldname(?=[,=)]|$)/a$rrdname/g;
            $min =~ s/(?<=[,=(])$fieldname(?=[,=)]|$)/i$rrdname/g;
            $avg =~ s/(?<=[,=(])$fieldname(?=[,=)]|$)/g$rrdname/g;
        }
    }

    munin_set_var_loc($service, [$$cfield_ref, "cdef_name"], $new_field);
    $$cfield_ref = $new_field;

    return ($max, $min, $avg);
}

sub parse_path {
    my ($path, $domain, $node, $service, $field) = @_;
    my $filename = "unknown";

    if ($path =~ /^\s*([^:]*):([^:]*):([^:]*):([^:]*)\s*$/) {
        $filename = munin_get_filename($config, $1, $2, $3, $4);
    }
    elsif ($path =~ /^\s*([^:]*):([^:]*):([^:]*)\s*$/) {
        $filename = munin_get_filename($config, $domain, $1, $2, $3);
    }
    elsif ($path =~ /^\s*([^:]*):([^:]*)\s*$/) {
        $filename = munin_get_filename($config, $domain, $node, $1, $2);
    }
    elsif ($path =~ /^\s*([^:]*)\s*$/) {
        $filename = munin_get_filename($config, $domain, $node, $service, $1);
    }
    return $filename;
}

# Wrapper for munin_get_picture_filename to handle pinpoint
sub get_picture_filename {
    my $of;
    if (defined $output_file) { $of=$output_file; goto exit_label; }

    $of = munin_get_picture_filename(@_);

  exit_label:

    return $of;
}

sub escape {
    my $text = shift;
    return if not defined $text;
    $text =~ s/\\/\\\\/g;
    $text =~ s/:/\\:/g;
    return $text;
}

sub get_scientific {
	my $value = shift;
	$value =~ s/m/e-03/;
	$value =~ s/k/e+03/;
	$value =~ s/M/e+06/;
	$value =~ s/G/e+09/;
	return $value;
}

sub RRDescape {
    my $text = shift;
    return $RRDs::VERSION < 1.2 ? $text : escape($text);
}


sub print_usage_and_exit {
    print "Usage: $0 [options]

Options:
    --[no]fork	        Do not fork.  By default munin-graph forks sub
                        processes for drawing graphs to utilize available
                        cores and I/O bandwidth. [--fork]
    --n n               Max number of concurrent processes [$max_running]
    --[no]force		Force drawing of graphs that are not usually
			drawn due to options in the config file. [--noforce]
    --[no]lazy		Only redraw graphs when needed. [--lazy]
    --help		View this message.
    --version		View version information.
    --debug		View debug messages.
    --[no]cron		Behave as expected when run from cron. (Used internally
			in Munin.)
    --host <host>       Limit graphed hosts to <host>. Multiple --host options
                        may be supplied.
    --only-fqn <FQN>    For internal use with CGI graphing.  Graph only a
                        single fully qualified named graph, e.g. --only-fqn
                          root/Backend/dafnes.example.com/diskstats_iops
                        Always use with the correct --host option.
    --config <file>	Use <file> as configuration file. [$conffile]
    --[no]list-images	List the filenames of the images created.
    			[--nolist-images]
    --output-file  -o	Output graph file. (used for CGI graphing)
    --log-file     -l	Output log file. (used for CGI graphing)
    --[no]day		Create day-graphs.   [--day]
    --[no]week		Create week-graphs.  [--week]
    --[no]month		Create month-graphs. [--month]
    --[no]year		Create year-graphs.  [--year]
    --[no]sumweek	Create summarised week-graphs.  [--summweek]
    --[no]sumyear	Create summarised year-graphs.  [--sumyear]
    --pinpoint <start,stop> Create custom-graphs. <start,stop> is the standard unix Epoch. [not active]
    --size_x <pixels>   Sets the X size of the graph in pixels [175]
    --size_y <pixels>   Sets the Y size of the graph in pixels [400]
    --lower_limit <lim> Sets the lower limit of the graph
    --upper_limit <lim> Sets the upper limit of the graph

NOTE! --pinpoint and --only-fqn must not be combined with
--[no]<day|week|month|year> options.  The result of doing that is
undefined.

";
    exit 0;
}

1;
