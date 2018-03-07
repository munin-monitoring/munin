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

use Time::HiRes;

use POSIX;

use Munin::Master::Utils;

use Munin::Common::Logger;

use File::Basename;
use Data::Dumper;

Munin::Common::Logger::configure( level => 'debug', output => 'screen');

# Hash of available palettes
my %PALETTE;
# Array of actuall colours to use
my @COLOUR;

{
	no warnings;
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
		#Greens Blues   Oranges Dk yel  Dk blu  Purple  lime    Reds    Gray
		qw(00CC00 0066B3 FF8000 FFCC00 330099 990099 CCFF00 FF0000 808080
			008F00 00487D B35A00 B38F00	 6B006B 8FB300 B30000 BEBEBE
			80FF80 80C9FF FFC080 FFE680 AA80FF EE00CC FF8080
			666600 FFBFFF 00FFCC CC6699 999900
	)];
}

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
	"hour"  => "10",
	"day"   => "300",
	"week"  => "1500",
	"month" => "7200",
	"year"  => "86400"
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
	return undef unless $ext;
	return defined $CONTENT_TYPES{uc($ext)};
}

my $watermark = "Munin " . $Munin::Common::Defaults::MUNIN_VERSION;

my $cgi;
sub handle_request
{
	$cgi = shift;

	my $t0 = Time::HiRes::time;
	my $path = $cgi->path_info();

	if ($path !~ m/^\/(.*)-(hour|day|week|month|year|pinpoint=(\d+),(\d+))\.(svg|json|csv|xml|png(?:x(\d+))?|[a-z]+)$/) {
		# We don't understand this URL
		print "HTTP/1.0 404 Not found\r\n";
		print $cgi->header(
			"-X-Reason" => "invalid URL: $path",
		);
		return;
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
		return;
	}

	# Handle the "pinpoint" time
	$time = "pinpoint" if $time =~ m/^pinpoint/;

	# Ok, now SQL is needed to go further
	use DBI;
	my $datafilename = $ENV{MUNIN_DBURL} || "$Munin::Common::Defaults::MUNIN_DBDIR/datafile.sqlite";
	# Note that we reconnect for _each_ request. This is to avoid old data when the DB "rotates"
	my $dbh = DBI->connect("dbi:SQLite:dbname=$datafilename","","") or die $DBI::errstr;

	DEBUG "($graph_path, $time, $start, $end, $format)\n";

	# Find the service to display
	my $sth_url = $dbh->prepare_cached("SELECT id, type FROM url WHERE path = ?");
	if (not defined($sth_url)) {
		# potential cause: permission problem
		my $msg = "Failed to access database ($datafilename): " . $DBI::errstr;
		WARNING "[WARNING] $msg";
		die $msg;
	}
	$sth_url->execute($graph_path);
	my ($id, $type) = $sth_url->fetchrow_array;

	if (! defined $id) {
		# Not found
		print "HTTP/1.0 404 Not found\r\n";
		print $cgi->header(
			"-X-Reason" => "'$graph_path' Not Found in DB",
		);
		return;
	} elsif ($type ne "service") {
		# Not supported yet
		print "HTTP/1.0 404 Not found\r\n";
		print $cgi->header(
			"-X-Reason" => "'$type' graphing is not supported yet",
		);
		return;
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
				JOIN ds_attr hn_attr ON hn.service_id = ds.service_id AND hn_attr.value = ds.name and hn_attr.name = 'negative'
				where hn.service_id = ds.service_id
			) as negative_id,
			rl.value as last_epoch,
			'dummy' as dummy
		FROM ds
		LEFT OUTER JOIN ds_attr l ON l.id = ds.id AND l.name = 'label'
		LEFT OUTER JOIN ds_attr rf ON rf.id = ds.id AND rf.name = 'rrd:file'
		LEFT OUTER JOIN ds_attr rd ON rd.id = ds.id AND rd.name = 'rrd:field'
		LEFT OUTER JOIN ds_attr ra ON ra.id = ds.id AND ra.name = 'rrd:alias'
		LEFT OUTER JOIN ds_attr rc ON rc.id = ds.id AND rc.name = 'rrd:cdef'
		LEFT OUTER JOIN ds_attr gc ON gc.id = ds.id AND gc.name = 'gfx:color'
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

	# Construction of the RRD command line
	# We don't care anymore for rrdtool less than 1.4
	my @rrd_def;
	my @rrd_cdef;
	my @rrd_vdef;
	my @rrd_gfx;
	my @rrd_gfx_negatives;
	my @rrd_legend;
	my @rrd_sum;

	my %negatives;

	push @rrd_gfx, "COMMENT:\\t";
	push @rrd_gfx, "COMMENT:Cur\\t";
	push @rrd_gfx, "COMMENT:Min\\t";
	push @rrd_gfx, "COMMENT:Avg\\t";
	push @rrd_gfx, "COMMENT:Max\\t\\r";

	# CDEF dictionary
	my %rrd_cdefs;

	my $lastupdated;

	my $field_number = 0;
	while (my (
			$_rrdname, $_label,
			$_rrdfile, $_rrdfield, $_rrdalias, $_rrdcdef,
			$_color, $_drawtype,
			$_drawstyle,
			$_printf,
			$_negative,
			$_sum,
			$_stack,
			$_has_negative,
			$_lastupdated,
		) = $sth->fetchrow_array()) {
		# Note that we do *NOT* provide any defaults for those
		# $_rrdXXXX vars. Defaults will be done by munin-update.
		#
		# This will:
		# 	- have only 1 reference on default values
		# 	- reduce the size of the CGI part, which is good for
		# 	  security (& sometimes performances)

		# Fields inherit this field from their plugin, if not overridden
		$_printf = $graph_printf unless defined $_printf;
		$_printf .= "%s";

		DEBUG "rrdname: $_rrdname";

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
		my $real_rrdname = $_rrdcdef ? "r_$_rrdname" : $_rrdname;
		if (! $_sum) {
			push @rrd_def, "DEF:avg_$real_rrdname=" . $_rrdfile . ":" . $_rrdfield . ":AVERAGE";
			push @rrd_def, "DEF:min_$real_rrdname=" . $_rrdfile . ":" . $_rrdfield . ":MIN";
			push @rrd_def, "DEF:max_$real_rrdname=" . $_rrdfile . ":" . $_rrdfield . ":MAX";
		}

		# Handle an eventual cdef
		if ($_rrdcdef) {
			# Populate the CDEF dictionary, to be able to swosh it at the end.
			# As it will enable to solve inter-field CDEFs.
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

		push @rrd_gfx, "$_drawtype:avg_$_rrdname#$_color:$_label$_drawstyle\\l";

		# Legend
		push @rrd_vdef, "VDEF:vavg_$_rrdname=avg_$_rrdname,AVERAGE";
		push @rrd_vdef, "VDEF:vmin_$_rrdname=min_$_rrdname,MINIMUM";
		push @rrd_vdef, "VDEF:vmax_$_rrdname=max_$_rrdname,MAXIMUM";

		push @rrd_vdef, "VDEF:vlst_$_rrdname=avg_$_rrdname,LAST";

		my $is_label_small = length($_label) <= 20;
		if ($is_label_small) {
			push @rrd_gfx, "COMMENT:\\u"; # Rewind the line, to have \r after the \l
		}


		# Handle negatives
		if ($_negative) {
			# We'll have a negative counterpart
			push @rrd_vdef, "CDEF:avg_n_$_rrdname=avg_$_negative,-1,*";
			push @rrd_vdef, "CDEF:min_n_$_rrdname=min_$_negative,-1,*";
			push @rrd_vdef, "CDEF:max_n_$_rrdname=max_$_negative,-1,*";

			push @rrd_vdef, "VDEF:vavg_n_$_rrdname=avg_n_$_rrdname,AVERAGE";
			push @rrd_vdef, "VDEF:vmin_n_$_rrdname=min_n_$_rrdname,MINIMUM";
			push @rrd_vdef, "VDEF:vmax_n_$_rrdname=max_n_$_rrdname,MAXIMUM";

			push @rrd_vdef, "VDEF:vlst_n_$_rrdname=avg_n_$_rrdname,LAST";
		}

		# Displaying the values as POSITIVE/NEGATIVE if $_negative
		push @rrd_gfx, "COMMENT:\\t";

		for my $t (qw(lst min avg max)) {
			if (! $_negative) {
				push @rrd_gfx, "GPRINT:v$t"."_$_rrdname:$_printf\\t";
			} else {
				push @rrd_gfx, "GPRINT:v$t"."_$_rrdname:$_printf\\g";
				push @rrd_gfx, "COMMENT:/\\g";
				push @rrd_gfx, "GPRINT:v$t"."_n_$_rrdname:$_printf\\g";
			}
		}

		push @rrd_gfx, "COMMENT:\\r";

		# Push to another array, to have these at the end
		push @rrd_gfx_negatives, "$_drawtype:avg_n_$_rrdname#$_color" if $_negative;

		$lastupdated = $_lastupdated if ! defined $lastupdated || ($_lastupdated && $_lastupdated > $lastupdated);
	} continue {
		# Move to here so it's always executed
		$field_number ++;
	}

	# Handle the plugin-authored CDEF
	for my $_rrdname (keys %rrd_cdefs) {
		my $_rrdcdef = $rrd_cdefs{$_rrdname}->{_rrdcdef};
		my $real_rrdname = $rrd_cdefs{$_rrdname}->{real_rrdname};

		for my $t (qw(min avg max)) {
			my $expanded_cdef = expand_cdef($_rrdname, $_rrdcdef, $t . "_$real_rrdname");
			for my $inner_rrdname (keys %rrd_cdefs) {
				next if ($inner_rrdname eq $_rrdname); # Already handled

				# expand an eventual sibling field to its realrrdname
				my $inner_real_rrdname = $rrd_cdefs{$inner_rrdname}->{real_rrdname};
				$expanded_cdef = expand_cdef($inner_rrdname, $expanded_cdef, $t . "_$inner_real_rrdname");
			}
			push @rrd_def, "CDEF:$t"."_$_rrdname=$expanded_cdef";
		}
	}

	# $end is possibly in future
	$end = $end ? $end : time;
	$lastupdated = "" unless $lastupdated;
	DEBUG "[DEBUG] lastupdate: $lastupdated, end: $end\n";

	# future begins at this horizontal ruler
	if ($lastupdated) {
		# TODO - we have to find the last updated for aliased items
		push(@rrd_gfx, "VRULE:$lastupdated#999999:Last update:dashes=2,5");
		my $last_update_str = escape_for_rrd(scalar localtime($lastupdated));
		push @rrd_gfx, "COMMENT:\\u";
		push @rrd_gfx, "COMMENT:$last_update_str\\r";
	}

	# Send the HTTP Headers
	print "HTTP/1.0 200 OK\r\n";
	print $cgi->header(
		"-Content-type" => $CONTENT_TYPES{$format},
	) unless $cgi->url_param("no_header");

	# Compute the title
	my $title = "";
	if ($time eq "pinpoint") {
		my $start_text = localtime($start);
		my $end_text = localtime($end);
		$title = "from $start_text to $end_text";
	} else {
		$title = "by " . $time;
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

		'--font', "TITLE:$font_size_title:Sans",
		'--font', "DEFAULT:$font_size_default",
		'--font', "LEGEND:$font_size_legend",
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
		push @rrd_header, "--lower" , $lower_limit if defined $lower_limit;
		push @rrd_header, "--upper" , $upper_limit if defined $upper_limit;

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
	my $rrd_fh = File::Temp->new();
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
		@rrd_gfx,
		@rrd_gfx_negatives,
		@rrd_legend,
	);

	my $err = RRDs_graph_or_dump(
		$format,
		@rrd_cmd,
	);
	if ($err) {
		INFO "'" . join("' \\\n'", @rrd_cmd) . "'";
		ERROR "Error generating image: ". $err;
	};

	# Sending the file
	DEBUG "sending '$rrd_fh'";

	# Since the file desc is still open, we just rewind it to the beginning.
	$rrd_fh->seek( 0, SEEK_SET );
	{
		my $buffer;
		# No buffering wanted when sending the file
		local $| = 1;
		while (sysread($rrd_fh, $buffer, 40 * 1024)) { print $buffer; }
	}

	my $ttot = Time::HiRes::time;
	DEBUG sprintf("total:%.3fs (db:%.3fs rrd:%.3fs)",
		($ttot - $t0),
		($tpng - $t0),
		($ttot - $tpng),
	);
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
	#
	return RRDs::graph(@_);

	use IPC::Open3;
	use IO::String;

	# We just revert to spawning a full featured rrdtool cmd for now.
	my $chld_out = new IO::String();
	my $chld_in = new IO::String();
	my $chld_err = new IO::String();

	local $ENV{PATH} = $1 if $ENV{PATH} =~ /(.*)/;

	my $chld_pid = open3($chld_out, $chld_in, $chld_err, "rrdtool", "graphv", @_);

	DEBUG "[DEBUG] RRDs_graph(chld_out=".${$chld_out->string_ref}.")";
	DEBUG "[DEBUG] RRDs_graph(chld_err=".${$chld_err->string_ref}.")";

	waitpid( $chld_pid, 0 );

	my $child_exit_status = ($? >> 8);

	return $child_exit_status;
}

sub RRDs_graph_or_dump {
	use RRDs;

	my $fileext = shift;
	if ($fileext =~ m/PNG|SVG|EPS|PDF/) {
		return RRDs_graph(@_);
	}

	DEBUG "[DEBUG] RRDs_graph(fileext=$fileext)";
	my $outfile = shift @_;

	# Open outfile
	DEBUG "[DEBUG] Open outfile($outfile)";
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
	DEBUG "[DEBUG] \n\nrrdtool xport '" . join("' \\\n\t'", @xport) . "'\n";
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

	my $rrd_error = RRDs::error();
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
