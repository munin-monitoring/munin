package Munin::Master::GraphOld;
# -*- cperl -*-

=comment

This is Munin::Master::GraphOld, a package shell to make munin-graph
modular (so it can loaded persistently in munin-fastcgi-graph for
example) without making it object oriented yet.  The non "old" module
will feature propper object orientation like munin-update and will
have to wait until later.


Copyright (C) 2002-2009 Jimmy Olsen, Audun Ytterdal, Kjell Magne Øierud,
Nicolai Langfeldt, Linpro AS, Redpill Linpro AS and others.

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
Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.

$Id$

=cut

use warnings;
use strict;

use Exporter;

our (@ISA, @EXPORT);
@ISA = qw(Exporter);
@EXPORT = qw(graph_startup graph_check_cron graph_main);

use IO::Socket;
use IO::Handle;
use RRDs;
use POSIX qw(strftime);
use Digest::MD5;
use Getopt::Long qw(GetOptionsFromArray);
use Time::HiRes;
use Text::ParseWords;

if ($RRDs::VERSION >= 1.3) { use Encode; }

use Munin::Master::Logger;
use Munin::Master::Utils;
use Munin::Common::Defaults;

use Log::Log4perl qw( :easy );

# RRDtool 1.2 requires \\: in comments
my $RRDkludge = $RRDs::VERSION < 1.2 ? '' : '\\';

# And RRDtool 1.2.* draws lines with crayons so we hack
# the LINE* options a bit.
my $LINEkluge=0;
if ($RRDs::VERSION >= 1.2 and $RRDs::VERSION < 1.3) {
    # Only kluge the line widths in RRD 1.2*
    $LINEkluge=1;
}

# RRD 1.3 has a "ADDNAN" operator which evaluates n + NaN = n instead of = NaN.
my $AddNAN = '+';
if ($RRDs::VERSION >= 1.3) {
  $AddNAN = 'ADDNAN';
}

# Force drawing of "graph no".
my $force_graphing = 0;
my $force_lazy = 1;
my $do_usage = 0;
my $do_version = 0;
my $cron = 0;
my $list_images = 0;
my $skip_locking = 0;
my $skip_stats = 0;
my $stdout = 0;
my $conffile = $Munin::Common::Defaults::MUNIN_CONFDIR."/munin.conf";
my $libdir = $Munin::Common::Defaults::MUNIN_LIBDIR;
my %draw = ("day" => 1, "week" => 1, "month" => 1, "year" => 1, "sumyear" => 1, "sumweek" => 1);

my %PALETTE; # Hash of available palettes
my @COLOUR;  # Array of actuall colours to use

{
    no warnings;
    $PALETTE{'old'} = [ # This is the old munin palette.  It lacks contrast.
       qw(#22ff22 #0022ff #ff0000 #00aaaa #ff00ff
	  #ffa500 #cc0000 #0000cc #0080C0 #8080C0 #FF0080
	  #800080 #688e23 #408080 #808000 #000000 #00FF00
	  #0080FF #FF8000 #800000 #FB31FB
	 )];

    $PALETTE{'default'} = [ # New default palette.Better contrast,more colours
       #Greens Blues   Oranges Dk yel  Dk blu  Purple  lime    Reds    Gray
     qw(#00CC00 #0066B3 #FF8000 #FFCC00 #330099 #990099 #CCFF00 #FF0000 #808080
        #008F00 #00487D #B35A00 #B38F00         #6B006B #8FB300 #B30000 #BEBEBE
        #80FF80 #80C9FF #FFC080 #FFE680 #AA80FF #EE00CC #FF8080
        #666600 #FFBFFF #00FFCC #CC6699 #999900
       )]; # Line variations: Pure, earthy, dark pastel, misc colours
}

my $range_colour = "#22ff22";
my $single_colour = "#00aa00";

my %times = (
	     "day"   => "-30h",
	     "week"  => "-8d",
	     "month" => "-33d",
	     "year"  => "-400d");

my %resolutions = (
             "day"   => "300",
             "week"  => "1500",
             "month" => "7200",
             "year"  => "86400");

my %sumtimes = ( # time => [ label, seconds-in-period ]
	    "week"   => ["hour", 12],
	    "year"   => ["day", 288]
	);

# Limit graphing to certain hosts and/or services
my @limit_hosts = ();
my @limit_services = ();

my $watermark; 

my $running = 0;
my $max_running = 6;
my $do_fork = 1;

# "global" Configuration hash
my $config;

# stats file handle
my $STATS;
my $DEBUG;

sub graph_startup {
    # Parse options and set up.  Stuff that is usually only needed once.
    #
    # Do once pr. run, pr possebly once pr. graph in the case of
    # munin-cgi-graph
    
    my ($ARGV) = @_;

    $watermark = "Munin ".$Munin::Common::Defaults::MUNIN_VERSION;

    # Get options
    &print_usage_and_exit unless
	GetOptionsFromArray (
	    $ARGV,
	    "force!"       => \$force_graphing,
	    "lazy!"        => \$force_lazy,
	    "host=s"       => \@limit_hosts,
	    "service=s"    => \@limit_services,
	    "config=s"     => \$conffile,
	    "stdout!"      => \$stdout,
	    "day!"         => \$draw{'day'},
	    "week!"        => \$draw{'week'},
	    "month!"       => \$draw{'month'},
	    "year!"        => \$draw{'year'},
	    "sumweek!"     => \$draw{'sumweek'},
	    "sumyear!"     => \$draw{'sumyear'},
	    "list-images!" => \$list_images,
	    "skip-locking!"=> \$skip_locking,
	    "skip-stats!"  => \$skip_stats,
	    "debug!"       => \$DEBUG,
	    "version!"     => \$do_version,
	    "cron!"        => \$cron,
	    "fork!"        => \$do_fork,
	    "n=n"	   => \$max_running,
	    "help"         => \$do_usage );

    if ($do_version) {
	print_version_and_exit();
	exit 0;
    }

    exit_if_run_by_super_user();

    $config= &munin_config ($conffile);
    logger_open($config->{'logdir'});

    my $palette = &munin_get ($config, "palette", "default");

    $max_running = &munin_get($config, "max_graph_jobs", $max_running);

    if ($max_running == 0) {
	$do_fork=0;
    }

    if (defined($PALETTE{$palette})) {
	@COLOUR=@{$PALETTE{$palette}};
    } else {
	die "Unknown palette named by 'palette' keyword: $palette\n";
    }

}


sub graph_check_cron {
    # Are we running from cron and do we have matching graph_strategy
    if (&munin_get ($config, "graph_strategy", "cron") ne "cron" and $cron) {
	# Strategy mismatch: We're run from cron, but munin.conf says
        # we use dynamic graph generation
	return 0;
    }
    # Strategy match:
    return 1;
}


sub graph_main {
    my $graph_time= Time::HiRes::time;

    munin_runlock("$config->{rundir}/munin-graph.lock") unless $skip_locking;

    unless ($skip_stats) {
	open ($STATS, '>', "$config->{dbdir}/munin-graph.stats.tmp") or
	    logger("Unable to open $config->{dbdir}/munin-graph.stats.tmp");
	autoflush $STATS 1; 
    }

    logger("Starting munin-graph");

    process_work(@limit_hosts);

    $graph_time = sprintf ("%.2f",(Time::HiRes::time - $graph_time));
    logger("Munin-graph finished ($graph_time sec)");
    print $STATS "GT|total|$graph_time\n" unless $skip_stats;
    rename ("$config->{dbdir}/munin-graph.stats.tmp", "$config->{dbdir}/munin-graph.stats");
    close $STATS unless $skip_stats;

    munin_removelock("$config->{rundir}/munin-graph.lock") unless $skip_locking;

    $running = wait_for_remaining_children($running);
}


# --------------------------------------------------------------------------

sub get_title {
    my $service = shift;
    my $scale   = shift;

    return (munin_get ($service, "graph_title", $service) . " - by $scale");
}

sub get_custom_graph_args
{
    my $service = shift;
    my $result  = [];

    my $args    = munin_get ($service, "graph_args");
    if (defined $args) {
	my $result = [ &quotewords('\s+', 0, $args) ] ;
	return $result;
    } else {
	return;
    }
}

sub get_vlabel
{
    my $service = shift;
    my $scale   = munin_get ($service, "graph_period", "second");
    my $res     = munin_get ($service, "graph_vlabel", munin_get ($service, "graph_vtitle"));

    if (defined $res) {
	$res =~ s/\$\{graph_period\}/$scale/g;
    }
    return $res;
}

sub should_scale
{
    my $service = shift;
    my $ret;

    if (!defined ($ret = munin_get_bool ($service, "graph_scale"))) {
	$ret = !munin_get_bool ($service, "graph_noscale", 0);
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
    push @$result, munin_get_picture_filename ($service, $scale, $sum||undef);

    # Title
    push @$result, ("--title", get_title ($service, $scale));

    # When to start the graph
    push @$result, "--start",$times{$scale};

    # Custom graph args, vlabel and graph title
    if (defined ($tmp_field = get_custom_graph_args ($service))) {
	push (@$result, @{$tmp_field});
    }
    if (defined ($tmp_field = get_vlabel ($service))) {
	push @$result, ("--vertical-label", $tmp_field);
    }

    push @$result,"--height", munin_get ($service, "graph_height", "175");
    push @$result,"--width", munin_get ($service, "graph_width", "400");
    push @$result,"--imgformat", "PNG";
    push @$result,"--lazy" if ($force_lazy);

    push (@$result, "--units-exponent", "0") if (! should_scale ($service));

    return $result;
}

sub get_sum_command {
    my $field   = shift;
    return munin_get ($field, "sum");
}

sub get_stack_command {
    my $field   = shift;
    return munin_get ($field, "stack");
}

sub expand_specials
{
    my $service = shift;
    my $preproc = shift;
    my $order   = shift;
    my $single  = shift;
    my $result  = [];

    my $fieldnum = 0;
    for my $field (@$order) { # Search for 'specials'...
	my $tmp_field;

	if ($field =~ /^-(.+)$/) { # Invisible field
	    $field = $1;
	    munin_set_var_loc ($service, [$field, "graph"], "no");
	}

	$fieldnum++;
	if ($field =~ /^([^=]+)=(.+)$/) { # Aliased in graph_order
	    my $fname = $1;
	    my $spath = $2;
	    my $src   = munin_get_node_partialpath ($service, $spath);
	    my $sname = munin_get_node_name ($src);

	    next unless defined $src;
	    logger ("DEBUG: Copying settings from $sname to $fname.") if $DEBUG;

	    foreach my $foption ("draw", "type", "rrdfile", "fieldname", "info") {
		if (!defined $service->{$fname}->{$foption}) {
		    if (defined $src->{$foption}) {
			munin_set_var_loc ($service, [$fname, $foption], $src->{$foption});
		    }
		}
	    }

	    # cdef is special...
	    if (!defined $service->{$fname}->{"cdef"}) {
		if (defined $src->{"cdef"}) {
		    (my $tmpcdef = $src->{"cdef"}) =~ s/([,=])$sname([,=]|$)/$1$fname$2/g;
		    munin_set_var_loc ($service, [$fname, "cdef"], $tmpcdef);
		}
	    }

	    if (!defined $service->{$fname}->{"label"}) {
		munin_set_var_loc ($service, [$fname, "label"], $fname);
	    }
	    munin_set_var_loc ($service, [$fname, "filename"], munin_get_rrd_filename ($src));

	} elsif (defined ($tmp_field = get_stack_command ($service->{$field}))) {
	    logger ("DEBUG: expand_specials ($tmp_field): Doing stack...") if $DEBUG;
	    my @spc_stack = ();
	    foreach my $pre (split (/\s+/, $tmp_field)) {
		(my $name = $pre) =~ s/=.+//;
		if (!@spc_stack) {
		    munin_set_var_loc ($service, [$name, "draw"], munin_get ($service->{$field}, "draw", "LINE2"));
		    munin_set_var_loc ($service, [$field, "process"], "no");
		} else {
		    munin_set_var_loc ($service, [$name, "draw"], "STACK");
		}
		push (@spc_stack, $name);
		push (@$preproc, $pre);
		push @$result, "$name.label";
		push @$result, "$name.draw";
		push @$result, "$name.cdef";

		munin_set_var_loc ($service, [$name, "label"], $name);
		munin_set_var_loc ($service, [$name, "cdef"], "$name,UN,0,$name,IF");
		if (munin_get ($service->{$field}, "cdef") and !munin_get_bool ($service->{$name}, "onlynullcdef", 0)) {
		    logger ("DEBUG: NotOnlynullcdef ($field)...") if $DEBUG;
		    $service->{$name}->{"cdef"} .= "," . $service->{$field}->{"cdef"};
		    $service->{$name}->{"cdef"} =~ s/\b$field\b/$name/g;
		} else {
		    logger ("DEBUG: Onlynullcdef ($field)...") if $DEBUG;
		    munin_set_var_loc ($service, [$name, "onlynullcdef"], 1);
		    push @$result, "$name.onlynullcdef";
		}
	    }
	} elsif (defined ($tmp_field = get_sum_command ($service->{$field}))) {
	    my @spc_stack = ();
	    my $last_name = "";
	    logger ("DEBUG: expand_specials ($tmp_field): Doing sum...") if $DEBUG;

	    if (@$order == 1 or (@$order == 2 and munin_get {$field, "negative", 0})) {
		    $single = 1;
	    }

	    foreach my $pre (split (/\s+/, $tmp_field)) {
		(my $path = $pre) =~ s/.+=//;
		my $name = "z".$fieldnum."_".scalar (@spc_stack);
		$last_name = $name;

		munin_set_var_loc ($service, [$name, "cdef"], "$name,UN,0,$name,IF");
		munin_set_var_loc ($service, [$name, "graph"], "no");
		munin_set_var_loc ($service, [$name, "label"], $name);
		push @$result, "$name.cdef";
		push @$result, "$name.graph";
		push @$result, "$name.label";

		push (@spc_stack, $name);
		push (@$preproc, "$name=$pre");
	    }
	    $service->{$last_name}->{"cdef"} .= "," . join (',+,', @spc_stack[0 .. @spc_stack-2]) . ',+';

	    if (my $tc = munin_get ($service->{$field}, "cdef", 0)) { # Oh bugger...
		logger ("DEBUG: Oh bugger...($field)...\n") if $DEBUG;
		$tc =~ s/\b$field\b/$service->{$last_name}->{"cdef"}/;
		$service->{$last_name}->{"cdef"} = $tc;
	    }
	    munin_set_var_loc ($service, [$field, "process"], "no");
	    munin_set_var_loc ($service, [$last_name, "draw"], munin_get ($service->{$field}, "draw"));
	    munin_set_var_loc ($service, [$last_name, "label"], munin_get ($service->{$field}, "label"));
	    munin_set_var_loc ($service, [$last_name, "graph"], munin_get ($service->{$field}, "graph", "yes"));

	    if (my $tmp = munin_get($service->{$field}, "negative")) {
		munin_set_var_loc ($service, [$last_name, "negative"], $tmp);
	    }

	    munin_set_var_loc ($service, [$field, "realname"], $last_name);

	} elsif (my $nf = munin_get ($service->{$field}, "negative", 0)) {
	    if (!munin_get_bool ($service->{$nf}, "graph", 1) or munin_get_bool ($service->{$nf}, "skipdraw", 0)) {
		munin_set_var_loc ($service, [$nf, "graph"], "no");
	    }
	}
    }
    return $result;
}

sub single_value
{
    my $service = shift;

    my $graphable = munin_get ($service, "graphable", 0);;
    if (!$graphable) {
	foreach my $field (@{munin_get_field_order ($service)}) {
	    logger ("DEBUG: single_value: Checking field \"$field\".") if $DEBUG;
	    $graphable++ if munin_draw_field ($service->{$field});
	}
	munin_set_var_loc ($service, ["graphable"], $graphable);
    }
    logger ("DEBUG: service ". join (' :: ', @{munin_get_node_loc ($service)}) ." has $graphable elements.") if $DEBUG;
    return ($graphable == 1);
}


sub get_field_name
{
    my $name = shift;

    $name = substr (Digest::MD5::md5_hex ($name), -15)
	if (length $name > 15);

    return $name;
}


sub process_work {
    my (@limit_hosts) = @_;
    # Make array of what is probably needed to graph
    my $work_array = [];
    if (@limit_hosts) { # Limit what to update if needed
	foreach my $nodename (@limit_hosts) {
	    push @$work_array, map { @{munin_find_field ($_->{$nodename}, "graph_title")} } @{munin_find_field($config, $nodename)};
	}
    } else { # ...else just search for all adresses to update
	push @$work_array, @{munin_find_field($config, "graph_title")};
    }

    for my $service (@$work_array) {

	# Want to avoid forking for that
	next if (skip_service ($service));

	# Fork (or not) and run the anonymous sub afterwards.
	fork_and_work(sub { process_service ($service); } );
    }
}


sub process_field {
    my $field   = shift;
    return munin_get_bool ($field, "process", 1);
}


sub fork_and_work {
    my ($work) = @_;

    if (! $do_fork) {
	# We're not forking.  Do work and return.
	DEBUG "[DEBUG] Doing work synchrnonously";
	&$work;
	return;
    }

    # Make sure we don't fork too much
    while ($running >= $max_running) {
	DEBUG "[DEBUG] Too many forks ($running/$max_running), wait for something to get done";
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

    } else {
	++$running;
	DEBUG "[DEBUG] Forked: $pid. Now running $running/$max_running";
	while ($running and look_for_child()) {
	    --$running;
	}
    }
}


sub process_service {
    my ($service) = @_;

    # Make my graphs
    my $sname = munin_get_node_name ($service);
    my $service_time= Time::HiRes::time;
    my $lastupdate = 0;
    my $now  = time;
    my $fnum = 0;
    my @rrd;
    my @added = ();

    # See if we should skip the service
    return if (skip_service ($service));

    my $field_count = 0;
    my $max_field_len = 0;
    my @field_order = ();
    my $rrdname;
    my $force_single_value;

    @field_order = @{munin_get_field_order($service)};

    # Array to keep 'preprocess'ed fields.
    my @rrd_preprocess = ();
    logger ("DEBUG: Expanding specials for $sname: \"" . join("\",\"", @field_order) . "\".") if $DEBUG;

    @added = @{&expand_specials ($service, \@rrd_preprocess, \@field_order, \$force_single_value)};

    @field_order = (@rrd_preprocess, @field_order);
    logger ("DEBUG: Checking field lengths for $sname: \"" . join("\",\"", @rrd_preprocess) . "\".") if $DEBUG;

    # Get max label length
    $max_field_len = munin_get_max_label_length ($service, \@field_order);

    # Global headers makes the value tables easier to read no matter how
    # wide the labels are.
    my $global_headers = 1;

    # Default format for printing under graph.
    my $avgformat;
    my $rrdformat=$avgformat="%6.2lf";

    if (munin_get ($service, "graph_args", "") =~ /--base\s+1024/) {
	# If the base unit is 1024 then 1012.56 is a valid
	# number to show.  That's 7 positions, not 6.
	$rrdformat=$avgformat="%7.2lf";
    }

    # Plugin specified complete printf format
    $rrdformat = munin_get ($service, "graph_printf", $rrdformat);

    my $rrdscale = '';
    if (munin_get_bool ($service, "graph_scale", 1)) {
	$rrdscale = '%s';
    }

    # Array to keep negative data until we're finished with positive.
    my @rrd_negatives = ();

    my $filename = "unknown";
    my %total_pos;
    my %total_neg;
    my $autostacking=0;

    logger ("DEBUG: Treating fields \"" . join ("\",\"", @field_order) . "\".") if $DEBUG;
    for my $fname (@field_order) {
	my $path     = undef;
	my $field    = undef;

	if ($fname =~ s/=(.+)//) {
	    $path = $1;
	}
	$field = munin_get_node ($service, [$fname]);

	next if (!defined $field or !$field or !process_field ($field));
	logger ("DEBUG: Processing field \"$fname\" [".munin_get_node_name($field)."].") if $DEBUG;

	my $fielddraw = munin_get ($field, "draw", "LINE2");

	if ($field_count == 0 and $fielddraw eq 'STACK') {
	    # Illegal -- first field is a STACK
	    logger ("ERROR: First field (\"$fname\") of graph " . join (' :: ', munin_get_node_loc ($service)) .
		    " is STACK. STACK can only be drawn after a LINEx or AREA.");
	    $fielddraw = "LINE2";
	}

	if ($fielddraw eq 'AREASTACK') {
	    if ($autostacking==0) {
		$fielddraw='AREA';
		$autostacking=1;
	    } else {
		$fielddraw='STACK';
	    }
	}

	if ($fielddraw =~ /LINESTACK(\d+(?:.\d+)?)/ ) {
	    if ($autostacking==0) {
		$fielddraw="LINE$1";
		$autostacking=1;
	    } else {
		$fielddraw='STACK';
	    }
	}

	# Getting name of rrd file
	$filename = munin_get_rrd_filename ($field, $path);

	my $update = RRDs::last ($filename);
	$update = 0 if ! defined $update;
	if ($update > $lastupdate) {
	    $lastupdate = $update;
	}

	# It does not look like $fieldname.rrdfield is possible to set
	my $rrdfield = munin_get ($field, "rrdfield", "42");

	my $single_value = $force_single_value || single_value ($service);

	my $has_negative = munin_get ($field, "negative");

	# Trim the fieldname to make room for other field names.
	$rrdname = &get_field_name ($fname);
	if ($rrdname ne $fname) {
	    # A change was made
	    munin_set ($field, "cdef_name", $rrdname);
	}

	# Push will place the DEF too far down for some CDEFs to work
	unshift (@rrd, "DEF:g$rrdname=" .
		 $filename . ":" . $rrdfield . ":AVERAGE");
	unshift (@rrd, "DEF:i$rrdname=" .
		 $filename . ":" . $rrdfield . ":MIN");
	unshift (@rrd, "DEF:a$rrdname=" .
		 $filename . ":" . $rrdfield . ":MAX");

	if (munin_get_bool ($field, "onlynullcdef", 0)) { 
	    push (@rrd, "CDEF:c$rrdname=g$rrdname" . (($now-$update)>900 ? ",POP,UNKN" : ""));
	}

	if (munin_get ($field, "type", "GAUGE") ne "GAUGE" and graph_by_minute ($service)) {
		push (@rrd, expand_cdef($service, \$rrdname, "$fname,60,*"));
	}

	if (my $tmpcdef = munin_get ($field, "cdef")) {
	    push (@rrd,expand_cdef($service, \$rrdname, $tmpcdef));
	    push (@rrd, "CDEF:c$rrdname=g$rrdname");
	    logger ("DEBUG: Field name after cdef set to $rrdname") if $DEBUG;
	} elsif (!munin_get_bool ($field, "onlynullcdef", 0)) {
	    push (@rrd, "CDEF:c$rrdname=g$rrdname" . (($now-$update)>900 ? ",POP,UNKN" : ""));
	}

	next if !munin_draw_field ($field);
	logger ("DEBUG: Drawing field \"$fname\".") if $DEBUG;

	if ($single_value) {
	    # Only one field. Do min/max range.
	    push (@rrd, "CDEF:min_max_diff=a$rrdname,i$rrdname,-");
	    push (@rrd, "CDEF:re_zero=min_max_diff,min_max_diff,-")
	      if !munin_get ($field, "negative");

	    push (@rrd, "AREA:i$rrdname#ffffff");
	    push (@rrd, "STACK:min_max_diff$range_colour");
	    push (@rrd, "LINE2:re_zero#000000") if
	      !munin_get ($field, "negative");
	}

	# Push "global" headers or not
	if ($has_negative and !@rrd_negatives and $global_headers < 2) {
	    # Always for -/+ graphs
	    push (@rrd, "COMMENT:" . (" " x $max_field_len));
    	    push (@rrd, "COMMENT:Cur (-/+)");
	    push (@rrd, "COMMENT:Min (-/+)");
	    push (@rrd, "COMMENT:Avg (-/+)");
	    push (@rrd, "COMMENT:Max (-/+) \\j");
	    $global_headers=2; # Avoid further headers/labels
	} elsif ($global_headers == 1) {
	    # Or when we want to.
	    push (@rrd, "COMMENT:" . (" " x $max_field_len));
	    push (@rrd, "COMMENT: Cur$RRDkludge:");
	    push (@rrd, "COMMENT:Min$RRDkludge:");
	    push (@rrd, "COMMENT:Avg$RRDkludge:");
	    push (@rrd, "COMMENT:Max$RRDkludge:  \\j");
	    $global_headers=2; # Avoid further headers/labels
	}

	my $colour;

	if (my $tmpcol = munin_get ($field, "colour")) {
	    $colour = "#" . $tmpcol;
	} elsif ($single_value) {
	    $colour = $single_colour;
	} else {
	    $colour = $COLOUR[$field_count%@COLOUR];
	}

	$field_count++;

	my $tmplabel = munin_get ($field, "label", $fname);

	push (@rrd, $fielddraw . ":g$rrdname" . $colour . ":" .
	    escape ($tmplabel) . (" " x ($max_field_len + 1 - length $tmplabel)));

	# Check for negative fields (typically network (or disk) traffic)
	if ($has_negative) {
	    my $negfieldname = orig_to_cdef ($service, munin_get ($field, "negative"));
	    my $negfield     = $service->{$negfieldname};
	    if (my $tmpneg = munin_get ($negfield, "realname")) {
		$negfieldname = $tmpneg;
		$negfield     = $service->{$negfieldname};
	    }

	    if (!@rrd_negatives) {
		# zero-line, to redraw zero afterwards.
		push (@rrd_negatives, "CDEF:re_zero=g$negfieldname,UN,0,0,IF");
	    }

	    push (@rrd_negatives, "CDEF:ng$negfieldname=g$negfieldname,-1,*");

	    if ($single_value) {
		# Only one field. Do min/max range.	
		push (@rrd, "CDEF:neg_min_max_diff=i$negfieldname,a$negfieldname,-");
		push (@rrd, "CDEF:ni$negfieldname=i$negfieldname,-1,*");
		push (@rrd, "AREA:ni$negfieldname#ffffff");
		push (@rrd, "STACK:neg_min_max_diff$range_colour");
	    }

	    push (@rrd_negatives, $fielddraw . ":ng$negfieldname" . $colour );

	    # Draw HRULEs
	    my $linedef = munin_get ($negfield, "line");
	    if ($linedef) {
		my ($number, $ldcolour, $label) = split (/:/, $linedef, 3);
		push (@rrd_negatives, "HRULE:".$number.
		    ($ldcolour ? "#$ldcolour" : $colour));
	    } elsif (my $tmpwarn = munin_get ($negfield, "warning")) {

		my ($warn_min,$warn_max) = split(':', $tmpwarn);

		if ( defined($warn_min) ) {
		    push (@rrd, "HRULE:".$warn_min.($single_value ? "#ff0000" : $COLOUR[($field_count-1)%@COLOUR]));
		}
		if ( defined($warn_max) ) {
		    push (@rrd, "HRULE:".$warn_max.($single_value ? "#ff0000" : $COLOUR[($field_count-1)%@COLOUR]));
		}
	    }

	    push (@rrd, "GPRINT:c$negfieldname:LAST:$rrdformat" . $rrdscale . "/\\g");
	    push (@rrd, "GPRINT:c$rrdname:LAST:$rrdformat" . $rrdscale . "");
	    push (@rrd, "GPRINT:i$negfieldname:MIN:$rrdformat" . $rrdscale . "/\\g");
	    push (@rrd, "GPRINT:i$rrdname:MIN:$rrdformat" . $rrdscale . "");
	    push (@rrd, "GPRINT:g$negfieldname:AVERAGE:$avgformat" . $rrdscale . "/\\g");
	    push (@rrd, "GPRINT:g$rrdname:AVERAGE:$avgformat" . $rrdscale . "");
	    push (@rrd, "GPRINT:a$negfieldname:MAX:$rrdformat" . $rrdscale . "/\\g");
	    push (@rrd, "GPRINT:a$rrdname:MAX:$rrdformat" . $rrdscale . "\\j");
	    push (@{$total_pos{'min'}}, "i$rrdname");
	    push (@{$total_pos{'avg'}}, "g$rrdname");
	    push (@{$total_pos{'max'}}, "a$rrdname");
	    push (@{$total_neg{'min'}}, "i$negfieldname");
	    push (@{$total_neg{'avg'}}, "g$negfieldname");
	    push (@{$total_neg{'max'}}, "a$negfieldname");
	} else {
	    push (@rrd, "COMMENT: Cur$RRDkludge:") unless $global_headers;
	    push (@rrd, "GPRINT:c$rrdname:LAST:$rrdformat" . $rrdscale . "");
	    push (@rrd, "COMMENT: Min$RRDkludge:") unless $global_headers;
	    push (@rrd, "GPRINT:i$rrdname:MIN:$rrdformat" . $rrdscale . "");
	    push (@rrd, "COMMENT: Avg$RRDkludge:") unless $global_headers;
	    push (@rrd, "GPRINT:g$rrdname:AVERAGE:$avgformat" . $rrdscale . "");
	    push (@rrd, "COMMENT: Max$RRDkludge:") unless $global_headers;
	    push (@rrd, "GPRINT:a$rrdname:MAX:$rrdformat" . $rrdscale . "\\j");
	    push (@{$total_pos{'min'}}, "i$rrdname");
	    push (@{$total_pos{'avg'}}, "g$rrdname");
	    push (@{$total_pos{'max'}}, "a$rrdname");
	}

	# Draw HRULEs
	my $linedef = munin_get ($field, "line");
	if ($linedef) {
	    my ($number, $ldcolour, $label) = split (/:/, $linedef, 3);
	    $label =~ s/:/\\:/g if defined $label;
	    push (@rrd, "HRULE:".$number.
		  ($ldcolour ? "#$ldcolour" :
		   ((defined $single_value and $single_value) ?
		    "#ff0000" : $colour)).
		  ((defined $label and length ($label)) ? ":$label" : ""),
		  "COMMENT: \\j"
		 );
	} elsif (my $tmpwarn = munin_get ($field, "warning")) {

	    my ($warn_min,$warn_max) = split(':', $tmpwarn);

	    if ( defined( $warn_min ) ) {
		push (@rrd, "HRULE:".$warn_min.($single_value ? "#ff0000" : $COLOUR[($field_count-1)%@COLOUR]));
	    }
	    if ( defined( $warn_max ) ) {
		push (@rrd, "HRULE:".$warn_max.($single_value ? "#ff0000" : $COLOUR[($field_count-1)%@COLOUR]));
	    }
	}
    }

    my $graphtotal = munin_get ($service, "graph_total");
    if (@rrd_negatives) {
	push (@rrd, @rrd_negatives);
	push (@rrd, "LINE2:re_zero#000000"); # Redraw zero.
	if (defined $graphtotal and exists $total_pos{'min'} and 
	    exists $total_neg{'min'} and
	    @{$total_pos{'min'}} and @{$total_neg{'min'}}) {

	    push (@rrd, "CDEF:ipostotal=".
		  join (",", @{$total_pos{'min'}}).
		  (",$AddNAN" x (@{$total_pos{'min'}}-1)));
	    push (@rrd, "CDEF:gpostotal=".
		  join (",", @{$total_pos{'avg'}}).
		  (",$AddNAN" x (@{$total_pos{'avg'}}-1)));
	    push (@rrd, "CDEF:apostotal=".
		  join (",", @{$total_pos{'max'}}).
		  (",$AddNAN" x (@{$total_pos{'max'}}-1)));
	    push (@rrd, "CDEF:inegtotal=".
		  join (",", @{$total_neg{'min'}}).
		  (",$AddNAN" x (@{$total_neg{'min'}}-1)));
	    push (@rrd, "CDEF:gnegtotal=".
		  join (",", @{$total_neg{'avg'}}).
		  (",$AddNAN" x (@{$total_neg{'avg'}}-1)));
	    push (@rrd, "CDEF:anegtotal=".
		  join (",", @{$total_neg{'max'}}).
		  (",$AddNAN" x (@{$total_neg{'max'}}-1)));
	    push (@rrd, "LINE1:gpostotal#000000:$graphtotal" . (" " x ($max_field_len - length ($graphtotal) + 1)));
	    push (@rrd, "GPRINT:gnegtotal:LAST:$rrdformat" . $rrdscale . "/\\g");
	    push (@rrd, "GPRINT:gpostotal:LAST:$rrdformat" . $rrdscale . "");
	    push (@rrd, "GPRINT:inegtotal:MIN:$rrdformat" . $rrdscale . "/\\g");
	    push (@rrd, "GPRINT:ipostotal:MIN:$rrdformat" . $rrdscale . "");
	    push (@rrd, "GPRINT:gnegtotal:AVERAGE:$avgformat" . $rrdscale . "/\\g");
	    push (@rrd, "GPRINT:gpostotal:AVERAGE:$avgformat" . $rrdscale . "");
	    push (@rrd, "GPRINT:anegtotal:MAX:$rrdformat" . $rrdscale . "/\\g");
	    push (@rrd, "GPRINT:apostotal:MAX:$rrdformat" . $rrdscale . "\\j");
	}
    } elsif (defined $graphtotal and exists $total_pos{'min'} and @{$total_pos{'min'}}) {
	push (@rrd, "CDEF:ipostotal=".
	      join (",", @{$total_pos{'min'}}).
	      (",$AddNAN" x (@{$total_pos{'min'}}-1)));
	push (@rrd, "CDEF:gpostotal=".
	      join (",", @{$total_pos{'avg'}}).
	      (",$AddNAN" x (@{$total_pos{'avg'}}-1)));
	push (@rrd, "CDEF:apostotal=".
	      join (",", @{$total_pos{'max'}}).
	      (",$AddNAN" x (@{$total_pos{'max'}}-1)));

	push (@rrd, "LINE1:gpostotal#000000:$graphtotal" . (" " x ($max_field_len - length ($graphtotal) + 1)));
	push (@rrd, "COMMENT: Cur$RRDkludge:") unless $global_headers;
	push (@rrd, "GPRINT:gpostotal:LAST:$rrdformat" . $rrdscale . "");
	push (@rrd, "COMMENT: Min$RRDkludge:") unless $global_headers;
	push (@rrd, "GPRINT:ipostotal:MIN:$rrdformat" . $rrdscale . "");
	push (@rrd, "COMMENT: Avg$RRDkludge:") unless $global_headers;
	push (@rrd, "GPRINT:gpostotal:AVERAGE:$avgformat" . $rrdscale ."");
	push (@rrd, "COMMENT: Max$RRDkludge:") unless $global_headers;
	push (@rrd, "GPRINT:apostotal:MAX:$rrdformat" . $rrdscale . "\\j");
    }

    for my $time (keys %times) {
	next unless ($draw{$time});
	my $picfilename = munin_get_picture_filename ($service, $time);
	(my $picdirname = $picfilename) =~ s/\/[^\/]+$//;

	my @complete = ();
	if ($RRDkludge) {
	    # since rrdtool 1.3 with libpango the LEGEND column alignment
	    # only works with monospace fonts
	    if ( $RRDs::VERSION >= 1.3 ) {
		push (@complete,
  		      '--font' ,'LEGEND:7:monospace');
	    } else {
		push (@complete,
  		      '--font' ,'LEGEND:7:$libdir/VeraMono.ttf');
	    }

	    push (@complete,
		  '--font' ,'UNIT:7:$libdir/VeraMono.ttf',
		  '--font' ,'AXIS:7:$libdir/VeraMono.ttf');
	}
	push(@complete,'-W', $watermark) if $RRDs::VERSION >= 1.2;

	# Do the header (title, vtitle, size, etc...)
	push @complete, @{get_header ($service, $time)};
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

	push (@complete, "COMMENT:Last update$RRDkludge: " .
	      RRDescape(scalar localtime($lastupdate)) .  "\\r");

	if (time - 300 < $lastupdate) {
	    push @complete, "--end",
	      (int($lastupdate/$resolutions{$time}))*$resolutions{$time};
	}
	print( "\n\nrrdtool \"graph\" \"",
	       join ("\"\n\t\"",@complete), "\"\n") if $DEBUG;

	# Make sure directory exists
	munin_mkdir_p ($picdirname, oct(777));

	# Since version 1.3 rrdtool uses libpango which needs its input
	# as utf8 string. So we assume that every input is in latin1
	# and decode it to perl's internal representation and then to utf8.

	if ( $RRDs::VERSION >= 1.3 ) {
	    @complete = map {
                my $str = $_;
		$str = encode("utf8", (decode("latin1", $_)));
                $str;
	    } @complete;
	}

	RRDs::graph (@complete);
	if (my $ERROR = RRDs::error) {
	    logger ("Unable to graph ". munin_get_picture_filename ($service, $time) . ": $ERROR");
	} else {
	    # Set time of png file to the time of the last update of
	    # the rrd file.  This makes http's If-Modified-Since more
	    # reliable, esp. in combination with munin-*cgi-graph.

	    utime $lastupdate, $lastupdate, munin_get_picture_filename($service, $time);
	    if ($list_images) {
		# Command-line option to list images created
		print munin_get_picture_filename ($service, $time),"\n";
	    }
	}
    }

    if (munin_get_bool ($service, "graph_sums", 0)) {
	foreach my $time (keys %sumtimes) {
	    my $picfilename = munin_get_picture_filename ($service, $time, 1);
	    (my $picdirname = $picfilename) =~ s/\/[^\/]+$//;
	    next unless ($draw{"sum".$time});
	    my @rrd_sum;
	    push @rrd_sum, @{get_header ($service, $time, 1)};

	    if (time - 300 < $lastupdate) {
		push @rrd_sum, "--end",(int($lastupdate/$resolutions{$time}))*$resolutions{$time};
	    }
	    push @rrd_sum, @rrd;
	    push (@rrd_sum, "COMMENT:Last update$RRDkludge: " . RRDescape(scalar localtime($lastupdate)) .  "\\r");

	    my $labelled = 0;
	    my @defined = ();
	    for (my $index = 0; $index <= $#rrd_sum; $index++) {
		if ($rrd_sum[$index] =~ /^(--vertical-label|-v)$/) {
		    (my $label = munin_get ($service, "graph_vlabel")) =~ s/\$\{graph_period\}/$sumtimes{$time}[0]/g;
		    splice (@rrd_sum, $index, 2, ("--vertical-label", $label));
		    $index++;
		    $labelled++;
		} elsif ($rrd_sum[$index] =~ /^(LINE[123]|STACK|AREA|GPRINT):([^#:]+)([#:].+)$/) {
		    my ($pre, $fname, $post) = ($1, $2, $3);
		    next if $fname eq "re_zero";
		    if ($post =~ /^:AVERAGE/) {
			splice (@rrd_sum, $index, 1, $pre . ":x$fname" . $post);
			$index++;
			next;
		    }
		    next if grep /^x$fname$/, @defined;
		    push @defined, "x$fname";
		    my @replace;

		    if (munin_get ($service->{$fname}, "type", "GAUGE") ne "GAUGE") {
			if ($time eq "week") {
			    # Every plot is half an hour. Add two plots and multiply, to get per hour
			    if (graph_by_minute ($service)) {
				# Already multiplied by 60
				push @replace, "CDEF:x$fname=PREV($fname),UN,0,PREV($fname),IF,$fname,+,5,*,6,*";
			    } else {
				push @replace, "CDEF:x$fname=PREV($fname),UN,0,PREV($fname),IF,$fname,+,300,*,6,*";
			    }
			} else {
			    # Every plot is one day exactly. Just multiply.
			    if (graph_by_minute ($service)) {
				# Already multiplied by 60
				push @replace, "CDEF:x$fname=$fname,5,*,288,*";
			    } else {
				push @replace, "CDEF:x$fname=$fname,300,*,288,*";
			    }
			}
		    }
		    push @replace, $pre . ":x$fname" . $post;
		    splice (@rrd_sum, $index, 1, @replace);
		    $index++;
		} elsif ($rrd_sum[$index] =~ /^(--lower-limit|--upper-limit|-l|-u)$/) {
		    $index++;
		    $rrd_sum[$index] = $rrd_sum[$index] * 300 * $sumtimes{$time}->[1];
		}
	    }
	    
	    
	    unless ($labelled) {
		my $label = munin_get ($service, "graph_vlabel_sum_$time", $sumtimes{$time}->[0]);
		unshift @rrd_sum, "--vertical-label", $label;
	    }

	    print ("\n\nrrdtool \"graph\" \"", join ("\"\n\t\"",@rrd_sum), "\"\n") if $DEBUG;

	    # Make sure directory exists
	    munin_mkdir_p ($picdirname, oct(777));

	    RRDs::graph (@rrd_sum);

	    if (my $ERROR = RRDs::error) {
		logger ("Unable to graph ". munin_get_picture_filename ($service, $time) . ": $ERROR");
	    } elsif ($list_images) {
		# Command-line option to list images created
		print munin_get_picture_filename ($service, $time, 1),"\n";
	    }
	}
    }

    $service_time = sprintf ("%.2f",(Time::HiRes::time - $service_time));
    logger ("Graphed service : $sname ($service_time sec * 4)");
    print $STATS "GS|$service_time\n" unless $skip_stats;

    foreach (@added) {
	delete $service->{$_} if exists $service->{$_};
    }
    @added = ();
}


sub graph_by_minute {
    my $service = shift;

    return (munin_get ($service, "graph_period", "second") eq "minute");
}

sub orig_to_cdef {
    my $service   = shift;
    my $fieldname = shift;

    return unless ref ($service) eq "HASH";

    if (defined $service->{$fieldname}->{"cdef_name"}) {
	return orig_to_cdef ($service, $service->{$fieldname}->{"cdef_name"});
    }
    return $fieldname;
}


sub skip_service {
    my $service = shift;
    my $sname   = munin_get_node_name ($service);

    # Skip if we've limited services with cli options
    return 1 if (@limit_services and !grep /^$sname$/, @limit_services);

    # Always graph if --force is present
    return 0 if $force_graphing;

    # See if we should skip it because of conf-options
    return 1 if (munin_get ($service, "graph", "yes") eq "on-demand" or
	    !munin_get_bool ($service, "graph", 1));

    # Don't skip
    return 0;
}

sub expand_cdef {
    my $service     = shift;
    my $cfield_ref  = shift;
    my $cdef        = shift;

    my $new_field = &get_field_name ("cdef$$cfield_ref");

    my ($max, $min, $avg) = ("CDEF:a$new_field=$cdef", "CDEF:i$new_field=$cdef", "CDEF:g$new_field=$cdef");

    foreach my $field (@{munin_find_field ($service, "label")}) {
	my $fieldname = munin_get_node_name ($field);
	my $rrdname = &orig_to_cdef ($service, $fieldname);
	if ($cdef =~ /\b$fieldname\b/) {
		$max =~ s/([,=])$fieldname([,=]|$)/$1a$rrdname$2/g;
		$min =~ s/([,=])$fieldname([,=]|$)/$1i$rrdname$2/g;
		$avg =~ s/([,=])$fieldname([,=]|$)/$1g$rrdname$2/g;
	}
    }

    munin_set_var_loc ($service, [$$cfield_ref, "cdef_name"], $new_field);
    $$cfield_ref = $new_field;

    return ($max, $min, $avg);
}

sub parse_path
{
    my ($path, $domain, $node, $service, $field) = @_;
    my $filename = "unknown";

    if ($path =~ /^\s*([^:]*):([^:]*):([^:]*):([^:]*)\s*$/)
    {
	$filename = munin_get_filename ($config, $1, $2, $3, $4);
    }
    elsif ($path =~ /^\s*([^:]*):([^:]*):([^:]*)\s*$/)
    {
	$filename = munin_get_filename ($config, $domain, $1, $2, $3);
    }
    elsif ($path =~ /^\s*([^:]*):([^:]*)\s*$/)
    {
	$filename = munin_get_filename ($config, $domain, $node, $1, $2);
    }
    elsif ($path =~ /^\s*([^:]*)\s*$/)
    {
	$filename = munin_get_filename ($config, $domain, $node, $service, $1);
    }
    return $filename;
}

sub escape
{
    my $text = shift;
    return if not defined $text;
    $text =~ s/\\/\\\\/g;
    $text =~ s/:/\\:/g;
    return $text;
}

sub RRDescape
{
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
    --service <service>	Limit graphed services to <service>. Multiple --service
			options may be supplied.
    --host <host>	Limit graphed hosts to <host>. Multiple --host options
    			may be supplied.
    --config <file>	Use <file> as configuration file. [$conffile]
    --[no]list-images	List the filenames of the images created. 
    			[--nolist-images]
    --[no]day		Create day-graphs.   [--day]
    --[no]week		Create week-graphs.  [--week]
    --[no]month		Create month-graphs. [--month]
    --[no]year		Create year-graphs.  [--year]
    --[no]sumweek	Create summarised week-graphs.  [--summweek]
    --[no]sumyear	Create summarised year-graphs.  [--sumyear]

";
	exit 0;
}

1;
