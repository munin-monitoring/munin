#! /usr/bin/perl
# Real-time visualization of block accesses
# with a layout as old DOS defraggers
#
# Idea borrowed from seekwatcher [http://oss.oracle.com/~mason/seekwatcher/]
#
# Copyright (C) 2010 Steve Schnepp
#
# License: GPL

use strict;
use warnings;
	
use Curses;
use Time::HiRes qw(sleep);

# Should not buffer anything since we are "real-time"
$| = 1;

# Give the blocksize as first arg
my $nb_blocks_1k = shift;
if (! $nb_blocks_1k) {
	die "Should give the number of 1k blocks as first arg";
}

my $win = Curses::new();
# Hide cursor
Curses::curs_set(0);

my $last_tstp = 0;
my $tstp_step = 1 / 25; # 25 Hz

# use non-blocking IO on stdin. 
# Otherwise when there is no activity, the drawing is stalled
use IO::Handle;
STDIN->blocking(0);

my $io_ops = {};
while(1) {
	my $line = <>;
	if (! $line) { sleep $tstp_step; $io_ops = {}; draw($io_ops); $last_tstp += $tstp_step; next; }
	chomp($line);
	# 8,0    3        1     0.000000000   697  G   W 223490 + 8 [kjournald]
	my ($device, $cpu_id, $seqno, $tstp, $pid, $action, $mode, $offset, $dummy, $length, $detail) = split(/ +/, trim($line), 11);

	# Only take complete lines
	next unless $detail;

	# Only take the C (completed) requests to take care of an eventual buffering/queuing
	next unless $action eq 'C';

	# Flush if needed. Assumes the data is timestamp ordered
	if ($tstp > $last_tstp + $tstp_step) {
		$last_tstp += $tstp_step;

		# flush to img
		draw($io_ops);

		# flush the in-flight IO ops
		$io_ops = {};
	}

	# Fill the in-flight IO ops
	$io_ops->{$offset} = [ $mode, $length ];
} continue {
}

sub draw 
{
	my $io_ops = shift;
	
	use Term::Size;

	my ($columns, $rows) = Term::Size::chars *STDOUT{IO};
	$rows --; # last row is status row

	my $nb_chars = $columns * $rows;
	my $blocks_per_char = int ($nb_blocks_1k * 2 / $nb_chars) + 1;
	
	# Each frame we redraw everything 
	$win->clear();

	# Update the status line
	$win->addstr($rows, 0, sprintf("%.2f", $last_tstp));

	# Iterate & fill the window
	while (my ($offset, $value) = each %$io_ops) {
		my $offset_in_chars = $offset / $blocks_per_char;
		my $x = $offset_in_chars / $columns;
		my $y = $offset_in_chars % $columns;

		my $op = ($value->[0] =~ m/R/ ? "R" : "W");
		my $len = int($value->[1] / $blocks_per_char) + 1;

		$win->addstr($x, $y, $op x $len);
	}

	sleep($tstp_step);
	$win->refresh();
}

# haaa.. this should really be part of Perl :-)
sub trim
{
	my $string = shift;
	$string =~ s/^\s+//;
	$string =~ s/\s+$//;
	return $string;
}
