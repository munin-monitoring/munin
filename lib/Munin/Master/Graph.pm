#!/usr/bin/perl -T

=begin comment

Copyright (C) 2014 Steve Schnepp

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; version 2 dated June,
1991.

This program is distributed in the hope that it will be useful, but
WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.

=end comment

=cut

use strict;
use warnings;

package Munin::Master::Graph;

use English qw(-no_match_vars);

use Time::HiRes;

use POSIX;

use Munin::Master::Utils;

use Munin::Common::Logger;

use File::Basename;
use Data::Dumper;

# We don't care anymore for rrdtool less than 1.4
die "Munin requires at least version 1.4 of RRD\n" if $RRDs::VERSION < 1.4;

# Hash of available palettes
my %PALETTE;
# Array of colours to use
my @COLOUR;

{
	# This is the old munin palette. Note that it lacks contrast.
	$PALETTE{'old'} = [
		qw(22ff22 0022ff ff0000 00aaaa ff00ff
			ffa500 cc0000 0000cc 0080C0 8080C0 FF0080
			800080 688e23 408080 808000 000000 00FF00
			0080FF FF8000 800000 FB31FB
	)];

	# New default palette. Better contrast & more colours
	# Line variations: Pure, earthy, dark pastel, misc colours
	$PALETTE{'default'} = [
		#  	Green  Blue   Orange Dk yel Dk blu Purple Lime   Reds   Gray
		qw(	00CC00 0066B3 FF8000 FFCC00 330099 990099 AACC00 FF0000 808080
			008F00 00487D B35A00 B38F00 6B006B 8FB300 B30000 BEBEBE
			80FF80 80C9FF FFC080 FFE680 AA80FF EE00CC FF8080
			666600 FFBFFF 00FFCC CC6699 999900
	)];
}

# FIXME: These things affect the legend width:
# - Normal plot:  6 positions for each column
# - Base 1024:    7 positions for each column
# - graph_scale: +1 position for SI unit for column
# - negative:    *2+1 positons: *1 for +, *1 for - and 1 for /

# As it is now: The first set for "normal" graphs, the second set for
# graphs with .negative plotting

my @rrd_legend_headers = (
    [ "COMMENT:Cur ", "COMMENT:Min ", "COMMENT:Avg ", "COMMENT:Max   \\j" ],
    [ "COMMENT:Cur -/+     ",
      "COMMENT:Min -/+     ",
      "COMMENT:Avg -/+     ",
      "COMMENT:Max -/+     \\j", ]
    );

# FIXME: Likewise the longest label length that can be fitted _with_
# the numbers on a legend line varies with all the cases above.
#
# The longest a label can be without using two lines, "the longest a
# short label can be".
#
# Note: SVG somehow has shorter line length!
my $longest_short = 18;      # Regular plot
my $longest_short_neg = 8;   # Plot with .negative series

# Obviously use the default one
@COLOUR = @{ $PALETTE{'default'} };

# those colors are used for single-valued plugins
my $range_colour  = "22ff22";
my $single_colour = "00aa00";

# Use 400 x RRA step, in order to have 1px per RRA sample.
my %times = (
	"hour"  => "end-4000s",  # (i.e. -1h6m40s)
	"day"   => "end-2000m",  # (i.e. -33h20m)
	"week"  => "end-12000m", # (i.e. -8d13h20m)
	"month" => "end-48000m", # (i.e. -33d8h)
	"year"  => "end-400d",
	"pinpoint"  => "unused_value",
);

my %resolutions = (
	"pinpoint"  => "1",
	"hour"  => "10",
	"day"   => "300",
	"week"  => "1500",
	"month" => "7200",
	"year"  => "86400",
);

my %CONTENT_TYPES = (
	"PNG" => "image/png",
	"SVG" => "image/svg+xml",

	"PDF" => "application/pdf",
	"EPS" => "application/postscript",
	"PS"  => "application/postscript",

	"CSV" => "text/csv",
	"XML" => "text/xml",
	"JSON" => "application/json",
);

sub is_ext_handled
{
	my $ext = shift;
	return unless $ext;
	return defined $CONTENT_TYPES{uc($ext)};
}

my $watermark = "Munin " . $Munin::Common::Defaults::MUNIN_VERSION;

my $cgi;
sub handle_request
{
	$cgi = shift;

	my $t0 = Time::HiRes::time;
	my $path = $cgi->path_info();

	if ($path !~ m/^\/(.*)-(hour|day|week|month|year|pinpoint=(\d+),(\d+))\.(svg|json|csv|xml|pdf|png(?:x(\d+))?|[a-z]+)$/) {
		# We don't understand this URL
		print "HTTP/1.0 404 Not found\r\n";
		print $cgi->header(
			"-X-Reason" => "invalid URL: $path",
		);
		goto CLEANUP;
	}


	my ($graph_path, $time, $start, $end, $format, $hidpi) = ($1, $2, $3, $4, $5, $6);
	$start = $times{$time} unless defined $start;
	$end = "" unless defined $end;

	$format = "png" if $hidpi; # Only PNG is supported when HiDPI mode

	# Only accept known formats
	$format = uc($format);
	if (! $CONTENT_TYPES{$format}) {
		# We don't understand this format
		 print "HTTP/1.0 404 Not found\r\n";
		print $cgi->header(
			"-X-Reason" => "invalid format $format",
		);
		goto CLEANUP;
	}

	# Handle the "pinpoint" time
	$time = "pinpoint" if $time =~ m/^pinpoint/;

	# Ok, now SQL is needed to go further
	# Note that we reconnect for _each_ request. This is to avoid old data when the DB "rotates"
	use Munin::Master::Update;
	my $dbh = Munin::Master::Update::get_dbh(1);

	DEBUG "($graph_path, $time, $start, $end, $format)\n";

	# Find the service to display
	my $sth_url = $dbh->prepare_cached("SELECT id, type FROM url WHERE path = ?");
	if (not defined($sth_url)) {
		# potential cause: permission problem
		my $msg = "Failed to access database: " . $DBI::errstr;
		WARNING $msg;
		die $msg;
	}
	$sth_url->execute($graph_path);
	my ($id, $type) = $sth_url->fetchrow_array;
	$sth_url->finish();

	if (! defined $id) {
		# Not found
		print "HTTP/1.0 404 Not found\r\n";
		print $cgi->header(
			"-X-Reason" => "'$graph_path' Not Found in DB",
		);
		goto CLEANUP;
	} elsif ($type ne "service") {
		# Not supported yet
		print "HTTP/1.0 404 Not found\r\n";
		print $cgi->header(
			"-X-Reason" => "'$type' graphing is not supported yet",
		);
		goto CLEANUP;
	}

	DEBUG "found node=$id, type=$type";

	# Here's the most common case: only plain plugins
	my $sth;

	$sth = $dbh->prepare_cached("SELECT value FROM service_attr WHERE id = ? and name = ?");
	$sth->execute($id, "graph_title");
	my ($graph_title) = $sth->fetchrow_array();

	$sth->execute($id, "graph_period");
	my ($graph_period) = $sth->fetchrow_array();
	$graph_period = "second" unless $graph_period;

	# Note that graph_vtitle is *NOT* supported anymore
	$sth->execute($id, "graph_vlabel");
	my ($graph_vlabel) = $sth->fetchrow_array();
	$graph_vlabel =~ s/\$\{graph_period\}/$graph_period/g if $graph_vlabel;

	# Note: This will be the graph order computed in munin-update,
	# not the graph_order emitted by the plugin.
	$sth->execute($id, "graph_order");
	my ($graph_order) = $sth->fetchrow_array() || "";
	DEBUG "graph_order: $graph_order";

	$sth->execute($id, "graph_args");
	my ($graph_args) = $sth->fetchrow_array() || "";
	my @rrd_graph_args = split /\s+/, $graph_args;
	DEBUG "graph_args: $graph_args";

	$sth->execute($id, "graph_printf");
	my ($graph_printf) = $sth->fetchrow_array();
	if (! defined $graph_printf) {
		# If the base unit is 1024 then 1012.56 is a valid
		# number to show.  That's 7 positions, not 6.
		$graph_printf = ($graph_args =~ /--base\s+1024/) ? "%7.2lf" : "%6.2lf";
	}

	$sth->execute($id, "graph_scale");
	my ($graph_scale) = $sth->fetchrow_array() || "";
	DEBUG "graph_scale: $graph_scale";
	if (lc($graph_scale) eq 'no') {
	    $graph_scale = 0;
	} else {
	    $graph_scale = 1;
	}

	DEBUG "graph_printf: $graph_printf";

	$sth = $dbh->prepare_cached("
		SELECT
			ds.name,
			l.value,
			rf.value,
			rd.value,
			ra.value,
			rc.value,
			gc.value,
			gd.value,
			gds.value,
			pf.value,
			ne.value,
			sm.value as sum,
			st.value as stack,
			(
				select hn.id
				from ds hn
				JOIN ds_attr hn_attr ON hn_attr.id = hn.id AND hn_attr.value = ds.name and hn_attr.name = 'negative'
				where hn.service_id = ds.service_id
			) as negative_id,
			rl.value as last_epoch,
			'dummy' as dummy
		FROM ds
		LEFT OUTER JOIN ds_attr l ON l.id = ds.id AND l.name = 'label'
		LEFT OUTER JOIN ds_attr rf ON rf.id = ds.id AND rf.name = 'rrd:file'
		LEFT OUTER JOIN ds_attr rd ON rd.id = ds.id AND rd.name = 'rrd:field'
		LEFT OUTER JOIN ds_attr ra ON ra.id = ds.id AND ra.name = 'rrd:alias'
		LEFT OUTER JOIN ds_attr rc ON rc.id = ds.id AND rc.name = 'cdef'
		LEFT OUTER JOIN ds_attr gc ON gc.id = ds.id AND gc.name = 'colour'
		LEFT OUTER JOIN ds_attr gd ON gd.id = ds.id AND gd.name = 'draw'
		LEFT OUTER JOIN ds_attr gds ON gds.id = ds.id AND gds.name = 'drawstyle'
		LEFT OUTER JOIN ds_attr pf ON pf.id = ds.id AND pf.name = 'printf'
		LEFT OUTER JOIN ds_attr ne ON ne.id = ds.id AND ne.name = 'negative'
		LEFT OUTER JOIN ds_attr sm ON sm.id = ds.id AND sm.name = 'sum'
		LEFT OUTER JOIN ds_attr st ON st.id = ds.id AND st.name = 'stack'
		LEFT OUTER JOIN ds_attr rl ON rl.id = ds.id AND rl.name = 'rrd:last'
		WHERE ds.service_id = ?
		ORDER BY ds.ordr ASC
	");
	$sth->execute($id);

	# Collect the field set in the graph and
	my $graph_has_negative = 0;
	my $longest_fieldname = 0;
	my %row;

	while (my ($_rrdname, @rest) = $sth->fetchrow_array()) {
	    $row{$_rrdname} = \@rest;

	    my $l = length($_rrdname);
	    $longest_fieldname = $l if $l > $longest_fieldname;
	    $graph_has_negative = 1 if $rest[9];
	}

	DEBUG "Graph survey: graph_has_negatives: $graph_has_negative, longest field name: $longest_fieldname";

	# To be robust and sure to be complete we apply the computed
	# graph_order here and any fields left over is added at the
	# end in alphabetical order. They will not have been in the
	# plugin "config" output.
	my %seen;
	my @graph_order = grep { $seen{$_}++ == 0 }
	  ( split(/ +/, $graph_order), sort keys %row );

	# Now @graph_order contains all the rrd field names, in the desired order

	DEBUG "Finalized graph order: ".join(', ', @graph_order);

	# Construction of the RRD command line
	my @rrd_def;
	my @rrd_cdef;
	my @rrd_vdef;
	my @rrd_gfx;
	my @rrd_gfx_negatives;
	my @rrd_legend;
	my @rrd_sum;

	# CDEF dictionary
	my %rrd_cdefs;

	my $lastupdated;

	my $first_def;
	my $field_number = 0;

	my $longest = $longest_short;
	my $legendhead = 0; # See $rrd_legend_headers

	if ($graph_has_negative) {
	    $legendhead = 1;
	    $longest = $longest_short_neg;
	}
	my $PAD = "COMMENT:" . (' ' x $longest);
	my $LPAD = "COMMENT:" . (' ' x ($longest+2));

	# Get out the right legend for this graph and then put in some
	# alignment.
	@rrd_legend = @{$rrd_legend_headers[$legendhead]};
	unshift(@rrd_legend, $LPAD);
	DEBUG "RRD legend: ".join(", ", @rrd_legend);

	# ^^^^ There used to be a \j here, but I think that was wrong.
	# This note is here to remind me in case _I_ was wrong.

	foreach my $_rrdname (@graph_order) {
	        my ($_label,
			$_rrdfile, $_rrdfield, $_rrdalias, $_rrdcdef,
			$_color, $_drawtype,
			$_drawstyle,
			$_printf,
			$_negative,
			$_sum,
			$_stack,
			$_has_negative,
		    $_lastupdated) = @{$row{$_rrdname}};

		# Note that we do *NOT* provide any defaults for those
		# $_rrdXXXX vars. Defaults will be done by munin-update.
		#
		# This will:
		# 	- have only 1 reference on default values
		# 	- reduce the size of the CGI part, which is good for
		# 	  security (& sometimes performances)

		# Fields inherit this field from their plugin, if not overridden by the field
		$_printf = $graph_printf unless defined $_printf;
		$_printf .= "%s" if $graph_scale;

		# The label is the fieldname if not present
		$_label = $_rrdname unless $_label;

		DEBUG "rrdname: $_rrdname: negative: ".($_negative // "undef")." has_negative: ".($_has_negative // "undef");

		# rrdtool fails on unescaped colons found in its input data
		$_label =~ s/:/\\:/g;

		# Handle .sum
		if ($_sum) {
			# .sum is just a alias + cdef shortcut, an example is:
			#
			# inputtotal.sum \
			#            ups-5a:snmp_ups_ups-5a_current.inputcurrent \
			#            ups-5b:snmp_ups_ups-5b_current.inputcurrent
			# outputtotal.sum \
			#            ups-5a:snmp_ups_ups-5a_current.outputcurrent \
			#            ups-5b:snmp_ups_ups-5b_current.outputcurrent
			#
			my @sum_items = split(/ +/, $_sum);
			my @sum_items_generated;
			my $sum_item_idx = 0;
			for my $sum_item (@sum_items) {
				my $sum_item_rrdname = "s_" . $sum_item_idx . "_" . $_rrdname;
				push @sum_items_generated, $sum_item_rrdname;

				# Get the RRD from the $sum_item
				my ($sum_item_rrdfile, $sum_item_rrdfield, $sum_item_lastupdated)
					= get_alias_rrdfile($dbh, $sum_item);


				push @rrd_sum, "DEF:avg_$sum_item_rrdname=" . $sum_item_rrdfile . ":" . $sum_item_rrdfield . ":AVERAGE";
				push @rrd_sum, "DEF:min_$sum_item_rrdname=" . $sum_item_rrdfile . ":" . $sum_item_rrdfield . ":MIN";
				push @rrd_sum, "DEF:max_$sum_item_rrdname=" . $sum_item_rrdfile . ":" . $sum_item_rrdfield . ":MAX";

				$first_def = "avg_$sum_item_rrdname" unless $first_def; # useful for Day&Night

				# The sum lastupdated is the latest of its parts.
				if (! $_lastupdated || $_lastupdated < $sum_item_lastupdated) {
					$_lastupdated = $sum_item_lastupdated;
				}
			} continue {
				$sum_item_idx ++;
			}

			# Now, the real meat. The CDEF SUMMING.
			# The initial 0 is because you have to have an initial value when chain summing
			for my $t (qw(min avg max)) {
				# Yey... a nice little MapReduce :-)
				my @s = map { $t . "_" . $_ } @sum_items_generated;
				my $cdef_sums = join(",+,", @s);
				push @rrd_sum, "CDEF:$t". "_r_" . "$_rrdname=0," . $cdef_sums . ",+";
			}
		}

		# Handle virtual DS by overriding the fields that describe the RDD _file_
		if ($_rrdalias) {
			# This is a virtual DS, we have to fetch the original values
			($_rrdfile, $_rrdfield, $_lastupdated) = get_alias_rrdfile($dbh, $_rrdalias);
		}

		# Fetch the data from the RRDs
		my $rrd_is_virtual = is_virtual($_rrdname, $_rrdcdef);
		my $rrd_is_cdef = defined $_rrdcdef && $_rrdcdef ne "";
		my $real_rrdname = ($rrd_is_virtual || ! $_rrdcdef) ? "$_rrdname" : "r_$_rrdname";
		if (! $_sum && ! $rrd_is_virtual) {
			push @rrd_def, "DEF:avg_$real_rrdname=" . $_rrdfile . ":" . $_rrdfield . ":AVERAGE";
			push @rrd_def, "DEF:min_$real_rrdname=" . $_rrdfile . ":" . $_rrdfield . ":MIN";
			push @rrd_def, "DEF:max_$real_rrdname=" . $_rrdfile . ":" . $_rrdfield . ":MAX";

			$first_def = "avg_$real_rrdname" unless $first_def; # useful for Day&Night
		}


		# Handle an eventual cdef
		if ($_rrdcdef) {
			# Populate the CDEF dictionary, to be able to swosh it at the end.
			# As it will enable to solve inter-field CDEFs.
			DEBUG "cdef handing for $_rrdname: _rrdcdef:$_rrdcdef, real_rrdname:$real_rrdname, rrd_is_virtual:$rrd_is_virtual, rrd_is_cdef:$rrd_is_cdef";
			$rrd_cdefs{$_rrdname}->{_rrdcdef} = $_rrdcdef;
			$rrd_cdefs{$_rrdname}->{real_rrdname} = $real_rrdname;
		}

		# Graph them
		$_color = $COLOUR[$field_number % $#COLOUR] unless defined $_color;
		$_drawtype = "LINE" unless defined $_drawtype;

		# Handle draw style such as "dashes=..."
		$_drawstyle = $_drawstyle ? ":$_drawstyle" : '';

		# Handle the (LINE|AREA)STACK munin extensions
		$_drawtype = $field_number ? "STACK" : "AREA" if $_drawtype eq "AREASTACK";
		$_drawtype = $field_number ? "STACK" : "LINE" if $_drawtype eq "LINESTACK";

		# Override a STACK to LINE if it's the first field
		$_drawtype = "LINE" if $_drawtype eq "STACK" && ! $field_number;

		# If this field is the negative of another field, we don't draw it anymore
		# ... But we did still want to compute the related DEF & CDEF
		next if $_has_negative;

		push @rrd_vdef, "VDEF:vavg_$_rrdname=avg_$_rrdname,AVERAGE";
		push @rrd_vdef, "VDEF:vmin_$_rrdname=min_$_rrdname,MINIMUM";
		push @rrd_vdef, "VDEF:vmax_$_rrdname=max_$_rrdname,MAXIMUM";
		push @rrd_vdef, "VDEF:vlst_$_rrdname=avg_$_rrdname,LAST";

		my $drawcmd = "$_drawtype:avg_$_rrdname#$_color:";

		# FIXME: This becomes sub-optimal if we in a -/+ plot
		# has a line that does not have a .negative, because
		# then the label can be longer anyway.  Example: if__err plugin
		my $shortlabel = ( length($_label) <= $longest );

		DEBUG "Longest $longest, '$_label' is short? $shortlabel";

		if ($shortlabel) {
		    push @rrd_gfx, $drawcmd.sprintf("%-${longest}s$_drawstyle",$_label);
		} else {
		    push @rrd_gfx, $drawcmd."$_label$_drawstyle\\l", $LPAD;
		}

		# Handle negatives
		if ($_negative) {
		        DEBUG "Negative of $_rrdname is $_negative";

			# These are for plotting! Sign is reversed to
			# plot them under the X-axis
			push @rrd_vdef, "CDEF:avg_n_$_rrdname=avg_$_negative,-1,*";
			push @rrd_vdef, "CDEF:min_n_$_rrdname=min_$_negative,-1,*";
			push @rrd_vdef, "CDEF:max_n_$_rrdname=max_$_negative,-1,*";

			# These are for the legend! Original sign,
			# because we want to see the original value
			# read, not the negated value used to plot
			push @rrd_vdef, "VDEF:vavg_$_negative=avg_$_negative,AVERAGE";
			push @rrd_vdef, "VDEF:vmin_$_negative=min_$_negative,MINIMUM";
			push @rrd_vdef, "VDEF:vmax_$_negative=max_$_negative,MAXIMUM";
			push @rrd_vdef, "VDEF:vlst_$_negative=avg_$_negative,LAST";
		}

		my $end = '';
		for my $t (qw(lst min avg max)) {
			$end = '\j' if $t eq 'max';

			if ($_negative) {
			    push @rrd_gfx, "GPRINT:v$t"."_$_negative:$_printf/\\g";
			    push @rrd_gfx, "GPRINT:v$t"."_$_rrdname:$_printf$end";
			} else {
			    push @rrd_gfx, "GPRINT:v$t"."_$_rrdname:$_printf$end";
			}
		}

		push @rrd_gfx_negatives, "$_drawtype:avg_n_$_rrdname#$_color" if $_negative;

		DEBUG "_lastupdated: ".($_lastupdated // '(undef)').
		    " lastupdated: ".($lastupdated // '(undef)');

		$lastupdated = $_lastupdated if ! defined $lastupdated || ($_lastupdated && $_lastupdated > $lastupdated);

		# Last resort
		$lastupdated = RRDs::last($_rrdfile) if !$lastupdated and $_rrdfile;
	} continue {
		# Move to here so it's always executed
		$field_number ++;
	}

	# Handle the plugin-authored CDEF
	for my $_rrdname (keys %rrd_cdefs) {
		my $_rrdcdef = $rrd_cdefs{$_rrdname}->{_rrdcdef};
		my $real_rrdname = $rrd_cdefs{$_rrdname}->{real_rrdname};

		my $expanded_cdef = expand_cdef($_rrdname, $_rrdcdef, "$real_rrdname");
		for my $inner_rrdname (keys %rrd_cdefs) {
			next if ($inner_rrdname eq $_rrdname); # Already handled

			# expand an eventual sibling field to its realrrdname
			my $inner_real_rrdname = $rrd_cdefs{$inner_rrdname}->{real_rrdname};
			$expanded_cdef = expand_cdef($inner_rrdname, $expanded_cdef, "$inner_real_rrdname");
		}

		# Now, create a version for each min/max/avg
		for my $t (qw(min avg max)) {
			push @rrd_def, "CDEF:${t}_$_rrdname=${t}_$expanded_cdef";
		}
	}

	# $end is possibly in future
	$end = $end ? $end : time;
	$lastupdated = "" unless $lastupdated;
	DEBUG "lastupdate: $lastupdated, end: $end\n";

	# future begins at this horizontal ruler
	if ($lastupdated) {
		# TODO - we have to find the last updated for aliased items
		push(@rrd_gfx, "VRULE:$lastupdated#999999::dashes=2,5");
		my $last_update_str = escape_for_rrd("Last update: ".localtime($lastupdated));
		# push @rrd_gfx, "COMMENT:\\u";
		push @rrd_gfx, "COMMENT:$last_update_str\\r";
	}

	# Compute the title
	my $title = "";
	if ($time eq "pinpoint") {
		my $start_text = localtime($start);
		my $end_text = localtime($end);
		$title = "from $start_text to $end_text";
	} else {
		$title = "for the last " . $time;
	}

	my $width = $cgi->url_param("size_x") || 400;  # We aligned our RRA to 400px
	my $height = $cgi->url_param("size_y") || 175; # Aligned to current CSS

	# Sanitize $width & $height to 4000, to avoid RSS-based DoS
	if (! is_int($width) || $width < 1 || $width > 4000) {
		$width = 400;
	}

	if (! is_int($height) || $height < 1 || $height > 4000) {
		$height = 175;
	}

	my $font_size_title = 12;
	my $font_size_default = 7;
	my $font_size_legend = 7;

	if ($hidpi) {
		$width *= $hidpi;
		$height *= $hidpi;
		$font_size_title *= $hidpi;
		$font_size_default *= $hidpi;
		$font_size_legend *= $hidpi;
	}

	my @rrd_header = (
		"--title", "$graph_title - $title",
		"--watermark", "Munin " . $Munin::Common::Defaults::MUNIN_VERSION,
		"--imgformat", $format,
		"--start", $start,
		"--slope-mode",

		'--font', "LEGEND:$font_size_legend",
		'--font', "TITLE:$font_size_title:Sans",
		'--font', "DEFAULT:$font_size_default",
		# Colors coordinated with CSS.
		'--color', 'BACK#F0F0F0',   # Area around the graph
		'--color', 'FRAME#F0F0F0',  # Line around legend spot
		'--color', 'CANVAS#FFFFFF', # Graph background, max contrast
		'--color', 'FONT#666666',   # Some kind of gray
		'--color', 'AXIS#CFD6F8',   # And axis like html boxes
		'--color', 'ARROW#CFD6F8',  # And arrow, ditto.

		'--width', $width,
		'--height', $height,

		"--border", "0",
	);
	push @rrd_header, "--end" , $end if $end;

	# Optional header args
	push @rrd_header, "--vertical-label", $graph_vlabel if $graph_vlabel;

	# Sparklines
	push @rrd_header, "--only-graph" if $cgi->url_param("only_graph");

	# Handle vertical limits
	{
		my $lower_limit  = $cgi->url_param("lower_limit");
		my $upper_limit  = $cgi->url_param("upper_limit");
		push @rrd_header, "--lower-limit" , $lower_limit if defined $lower_limit;
		push @rrd_header, "--upper-limit" , $upper_limit if defined $upper_limit;

		# Adding --rigid, otherwise the limits are not taken into account.
		push @rrd_header, "--rigid" if defined $lower_limit || defined $upper_limit;
	}

	# Now it gets *REALLY* dirty: FastCGI doesn't handle correctly stdout
	# streaming for rrdtool. So we have to revert to use a temporary file.
	# This way of doing things might _eventually_ be reused later if we
	# implement server-side caching, but I'd rather not to.
	#
	# I think caching would be better handled via HTTP headers:
	# 	- on the browser
	# 	- on a caching reverse proxy, such as varnish.

	use File::Temp;
	my $rrd_fh = File::Temp->new(
		SUFFIX => ".$format",
	);
	# Send the PNG output
	my $tpng = Time::HiRes::time;
	my @rrd_cmd = (
		$rrd_fh->filename,
		@rrd_graph_args,
		@rrd_header,
		@rrd_sum,
		@rrd_def,
		@rrd_cdef,
		@rrd_vdef,
		@rrd_legend,
		@rrd_gfx,
		@rrd_gfx_negatives,
	);

	# Add the night/day cycle at the extreme end, so it can be in
	# the background. The first batch here is for above X-axis, the
	# second below X-axis.
	if (defined $first_def) {
		push @rrd_cmd, (
			"CDEF:dummy_val=$first_def",
			"CDEF:n_d_b=LTIME,86400,%,28800,LT,INF,LTIME,86400,%,64800,GE,INF,UNKN,dummy_val,*,IF,IF",
			"CDEF:n_d_c=LTIME,604800,%,172800,GE,LTIME,604800,%,345600,LT,INF,UNKN,dummy_val,*,IF,UNKN,dummy_val,*,IF",
			"CDEF:n_d_b2=LTIME,86400,%,28800,LT,NEGINF,LTIME,86400,%,64800,GE,NEGINF,UNKN,dummy_val,*,IF,IF",
			"CDEF:n_d_c2=LTIME,604800,%,172800,GE,LTIME,604800,%,345600,LT,NEGINF,UNKN,dummy_val,*,IF,UNKN,dummy_val,*,IF",
		);

		push @rrd_cmd, "AREA:n_d_b#00519909","AREA:n_d_b2#00519909" unless grep { $_ eq $time } ("month", "year");
		push @rrd_cmd, "AREA:n_d_c#AAABA11F","AREA:n_d_c2#AAABA11F" unless grep { $_ eq $time } ("year");

	} else {
		WARN "day/night not working for [$path] as \$first_def is NULL";
	}

	my $err = RRDs_graph_or_dump(
		$format,
		@rrd_cmd,
	);
	if ($err) {
	        print "HTTP/1.1 400 Bad Request\r\n";
                print $cgi->header('-Content-type' => 'text/plain');
                print "RRD error, consult server logs\r\n";

		ERROR "RRD error generating image for [$path]: ". $err;
                ERROR "Complete RRD command: rrdtool graph '".join("' \\\n\t'", @rrd_cmd)."'";
	};

	# Sending the file
	DEBUG "sending '$rrd_fh'";

	# Send the HTTP Headers
	{
		my ($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size,$atime,$mtime,$ctime,$blksize,$blocks) = $rrd_fh->stat();

		print "HTTP/1.1 200 OK\r\n";
		print $cgi->header(
			"-Content-type" => $CONTENT_TYPES{$format},
			"-Content-length" => $size,
			"-Cache-Control" => "public, max-age=$resolutions{$time}",
		) unless $cgi->url_param("no_header");
	}

	# Since the file desc is still open, we just rewind it to the beginning.
	$rrd_fh->seek( 0, SEEK_SET );
	{
		my $buffer;
		# No buffering wanted when sending the file
		local $OUTPUT_AUTOFLUSH = 1;
		# Using a 4kiB buffer
		while (sysread($rrd_fh, $buffer, 4096)) { print $buffer; }
	}

CLEANUP:
	$dbh = undef;

	my $ttot = Time::HiRes::time;
	DEBUG sprintf("total:%.3fs (db:%.3fs rrd:%.3fs)",
		($ttot - $t0),
		($tpng - $t0),
		($ttot - $tpng),
	);
}

# is_virtual() means that the field itself isn't in the cdef.
sub is_virtual {
	my ($field, $cdef) = @_;
	return 0 unless $cdef;

	my @a = split(/,/, $cdef);
	return 0 if (grep {$_ eq $field} @a);
	return 1;
}

sub remove_dups {
	my ($str) = @_;

	return unless $str;

	my @a = split(/ +/, $str);
	my %seen;
	@a = grep { ! ($seen{$_}++) } @a;

	return join(" ", @a);
}

sub is_int {
	my ($str) = @_;

	return ($str =~ m/[0-9]+/);
}

sub escape_for_rrd {
	my $text = shift;
	return if not defined $text;
	$text =~ s/\\/\\\\/g;
	$text =~ s/:/\\:/g;
	return $text;
}

# Expands $_rrdcdef, replacing $_rrdname by $real_rrdname
# TODO - should use a split, and a array map{} operator instead of a complex regex.
# But it seems to work, so refactoring only if we need to tweak it
sub expand_cdef {
	my ($_rrdname, $_rrdcdef, $real_rrdname) = @_;
	DEBUG "expand_cdef($_rrdname $_rrdcdef $real_rrdname)";
	$_rrdcdef =~ s/(?<=[,=])$_rrdname(?=[,=]|$)/$real_rrdname/g; # ?<= is lookbehind, ?= is lookforward
	$_rrdcdef =~ s/^$_rrdname(?=[,=]|$)/$real_rrdname/g; # Also handle the first element
	DEBUG "=$_rrdcdef";
	return $_rrdcdef;
}

sub RRDs_graph {
	# RRDs::graph() is *STATEFUL*. It doesn't emit the same PNG
	# when called the second time.
	RRDs::graph(@_);
	my $rrd_error = RRDs::error();
	return $rrd_error;
}

sub RRDs_graph_or_dump {
	use RRDs;

	# Appending $RRD_EXTRA_ARGS if present
	if ($ENV{RRD_EXTRA_ARGS}) {
		# Beware, the split is rather simple, and does not
		# handle the following : "this contains spaces"
		my @RRD_EXTRA_ARGS = split(/ /, $ENV{RRD_EXTRA_ARGS});
		push @_, @RRD_EXTRA_ARGS;
	}

	my $fileext = shift;
	if ($fileext =~ m/PNG|SVG|EPS|PDF/) {
		RRDs_graph(@_);
		return RRDs::error;
	}

	DEBUG "RRDs_graph(fileext=$fileext)";
	my $outfile = shift @_;

	# Open outfile
	DEBUG "Open outfile($outfile)";
	my $out_fh = new IO::File(">$outfile");

	# Remove unknown args
	my @xport;
	while ( defined ( my $arg = shift @_ )) {
		if ($arg eq "--start" || $arg eq "--end") {
			push @xport, $arg;
			push @xport, shift @_;
			next;
		}
		if ($arg =~ m/^C?DEF:/) { push @xport, $arg; next; }

		if ($arg =~ m/^(LINE|AREA|STACK)/) {
			my ($type, $var, $legend) = split(/:/, $arg);

			$type = "XPORT"; # Only 1 export type
			$var =~ s/#.*//; # Remove optional color

			# repaste..
			push @xport, "$type:$var:$legend";

			next;
		}

		# Ignore the arg
	}
	# Now we have to fetch the textual values
	DEBUG "\n\nrrdtool xport '" . join("' \\\n\t'", @xport) . "'\n";
	my ($start, $end, $step, $nb_vars, $columns, $values) = RRDs::xport(@xport);
	if ($fileext eq "CSV") {
		print $out_fh '"epoch", "' . join('", "', @{ $columns } ) . "\"\n";
		my $idx_value = 0;
		for (my $epoch = $start; $epoch <= $end; $epoch += $step) {
			print $out_fh "$epoch";
			my $row = $values->[$idx_value++];
			for my $value (@$row) {
				print $out_fh "," . (defined $value ? $value : "");
			}
			print $out_fh "\n";
		}
	} elsif ($fileext eq "XML") {
		print $out_fh "<xport>\n";
		print $out_fh "    <meta>\n";
		print $out_fh "        <start>$start</start>\n";
		print $out_fh "        <step>$step</step>\n";
		print $out_fh "        <end>$end</end>\n";
		print $out_fh "        <rows>" . (scalar @$values) . "</rows>\n";
		print $out_fh "        <columns>" . (scalar @$columns) . "</columns>\n";
		print $out_fh "        <legend>\n";
		for my $column ( @{ $columns } ) {
			print $out_fh "            <entry>$column</entry>\n";
		}
		print $out_fh "        </legend>\n";
		print $out_fh "    </meta>\n";
		print $out_fh "    <data>\n";
		my $idx_value = 0;
		for (my $epoch = $start; $epoch <= $end; $epoch += $step) {
			print $out_fh "        <row><t>$epoch</t>";
			my $row = $values->[$idx_value++];
			for my $value (@$row) {
				print $out_fh "<v>" . (defined $value ? $value : 'NaN') . "</v>";
			}
			print $out_fh "</row>\n";
		}
		print $out_fh "    </data>\n";
		print $out_fh "</xport>\n";
	} elsif ($fileext eq "JSON") {
		print $out_fh "{\n";
		print $out_fh "    \"meta\": { \n";
		print $out_fh "        \"start\": $start,\n";
		print $out_fh "        \"step\": $step,\n";
		print $out_fh "        \"end\": $end,\n";
		print $out_fh "        \"rows\": " . (scalar @$values) . ",\n";
		print $out_fh "        \"columns\": " . (scalar @$columns) . ",\n";
		print $out_fh "        \"legend\": [\n";
		my $index = 0;
		## no critic qw(ControlStructures::ProhibitMutatingListFunctions)
		my @json_columns = map { s/\\l$//; $_; } @{ $columns }; # Remove trailing "\l"
		for my $column ( @json_columns ) {
			print $out_fh "            \"$column\"";

			my $is_last_column = ($index != scalar(@json_columns)-1);
			if ($is_last_column) {
				print $out_fh ",";
			}
			print $out_fh "\n";

			$index++;
		}
		print $out_fh "        ]\n";
		print $out_fh "    }, \n";
		print $out_fh "    \"data\": [ \n";
		my $idx_value = 0;
		for (my $epoch = $start; $epoch <= $end; $epoch += $step) {
			print $out_fh "        [ $epoch";
			my $row = $values->[$idx_value++];
			for my $value (@$row) {
				print $out_fh ", " . (defined $value ? $value : '"NaN"');
			}
			print $out_fh " ]";
			# Don't print "," for the last item
			if ($epoch != $end) {
				print $out_fh ",";
			}
			print $out_fh "\n";
		}
		print $out_fh "    ] \n";
		print $out_fh "}\n";
	}

	my $rrd_error = RRDs::error;
	return $rrd_error;
}

sub get_alias_rrdfile
{
	my ($dbh, $_rrdalias) = @_;

	return unless ($_rrdalias =~ m/^(.*)\.([^.]+)$/);

	my ($_alias_service, $_alias_ds) = ($1, $2);

	# This is a virtual DS, we have to fetch the original values
	my ($_rrdfile, $_rrdfield, $_lastupdated) = $dbh->selectrow_array("
		SELECT
			rf.value,
			rd.value,
			rl.value,
			'dummy' as dummy
		FROM ds
		INNER JOIN service s ON s.id = ds.service_id AND (
			s.name = ?
		OR	s.path = ?
		)
		LEFT OUTER JOIN ds_attr rf ON rf.id = ds.id AND rf.name = 'rrd:file'
		LEFT OUTER JOIN ds_attr rd ON rd.id = ds.id AND rd.name = 'rrd:field'
		LEFT OUTER JOIN ds_attr rl ON rl.id = ds.id AND rl.name = 'rrd:last'
		WHERE ds.name = ?
		ORDER BY ds.ordr ASC
	", undef, $_alias_service, $_alias_service, $_alias_ds);
	DEBUG "($_alias_service $_alias_ds) = ($_rrdfile $_rrdfield, $_lastupdated)";

	return ($_rrdfile, $_rrdfield, $_lastupdated);
}

1;
