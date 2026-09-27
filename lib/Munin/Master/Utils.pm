package Munin::Master::Utils;


use strict;
use warnings;

use Carp;
use Exporter;
use English qw(-no_match_vars);
use File::Path qw(make_path);
use IO::Handle;
use Munin::Common::Defaults;
use Munin::Master::Config;
use Munin::Common::Config;
use Munin::Common::Logger;
use POSIX qw(strftime);
use POSIX qw(:sys_wait_h);
use POSIX qw(:errno_h);
use Symbol qw(gensym);
use Data::Dumper;
use Time::Local qw(timelocal);
use Storable;
use Scalar::Util qw(isweak weaken);

our (@ISA, @EXPORT);

@ISA = ('Exporter');
@EXPORT = qw(
	   munin_mkdir_p
	   print_version_and_exit
	   exit_if_run_by_super_user
	   munin_time
	   faketime
	   faketime_delta
	   munin_duration_to_sec
	   );

my $VERSION = $Munin::Common::Defaults::MUNIN_VERSION;

my $config = undef;
my $config_parts = {
	# config parts that might be loaded and reloaded at times
	'datafile' => {
		'timestamp' => 0,
		'config' => undef,
		'revision' => 0,
		'include_base' => 1,
	},
	'limits' => {
		'timestamp' => 0,
		'config' => undef,
		'revision' => 0,
		'include_base' => 1,
	},
	'htmlconf' => {
		'timestamp' => 0,
		'config' => undef,
		'revision' => 0,
		'include_base' => 0,
	},
};

my $configfile="$Munin::Common::Defaults::MUNIN_CONFDIR/munin.conf";

# Fields to copy when "aliasing" a field
my @COPY_FIELDS    = ("label", "draw", "drawstyle", "type", "rrdfile", "fieldname", "info");

my @dircomponents = split('/',$0);
my $me = pop(@dircomponents);

# Mockable time function for testing
# Override $TIME_OVERRIDE in tests for deterministic behavior
our $TIME_OVERRIDE;
sub munin_time {
    return $TIME_OVERRIDE if defined $TIME_OVERRIDE;
    return time;
}

# Convert human-readable time spec to seconds
# Examples: '1s', '30m', '1h', '7d', '2w', '1t' (month=31d), '1y' (year=365d)
sub munin_duration_to_sec {
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
        my $unit = lc($2);
        return $1 * $secs_table->{$unit};
    } else {
        # no recognised unit, return the int value as seconds
        return 0 unless $target =~ /^\d+$/;
        return int $target;
    }
}

# faketime() - set deterministic time for testing
# Usage:
#   faketime('2024-01-01 00:00:00')  # absolute
#   faketime('+1h')                   # relative from now
#   faketime('-1d')                   # relative from now
#   faketime(1704067200)             # epoch
#   faketime(undef)                  # clear, return to real time
#
# faketime_delta() - offset from frozen time
# Usage:
#   faketime('2024-01-01 00:00:00')  # freeze at midnight
#   faketime_delta('+1h');           # now 01:00
#   faketime_delta('+1h');           # now 02:00
sub faketime {
    my ($spec) = @_;

    if (!defined $spec) {
        undef $TIME_OVERRIDE;
        return;
    }

    if ($spec =~ /^([+-])(\d+[smhdwty])$/i) {
        my ($sign, $dur) = ($1, $2);
        my $offset = munin_duration_to_sec($dur);
        $offset = -$offset if $sign eq '-';
        $TIME_OVERRIDE = time + $offset;
    } elsif ($spec =~ /^\d+$/) {
        # Epoch timestamp
        $TIME_OVERRIDE = $spec;
    } elsif ($spec =~ /^(\d{4})-(\d{2})-(\d{2})\s*(\d{2}):(\d{2}):(\d{2})$/) {
        # ISO date string: YYYY-MM-DD HH:MM:SS
        my ($year, $month, $day, $hour, $min, $sec) = ($1, $2, $3, $4, $5, $6);
        $TIME_OVERRIDE = timelocal($sec, $min, $hour, $day, $month - 1, $year);
    } else {
        warn "faketime: unrecognized format '$spec'";
    }
}

# faketime_delta() - offset from current (possibly frozen) time
sub faketime_delta {
    my ($spec) = @_;

    my $base = defined $TIME_OVERRIDE ? $TIME_OVERRIDE : time;

    if ($spec =~ /^([+-])(\d+[smhdwty])$/i) {
        my ($sign, $dur) = ($1, $2);
        my $offset = munin_duration_to_sec($dur);
        $offset = -$offset if $sign eq '-';
        $TIME_OVERRIDE = $base + $offset;
    } else {
        warn "faketime_delta: unrecognized format '$spec'";
    }
}

sub munin_mkdir_p {
    my ($dirname, $umask) = @_;

    eval {
        make_path($1) if $dirname =~ /(.*)/;
    };
    print STDERR "cannot create '$dirname' because $@" if $@;
    return if $@;
    return 1;
}

sub exit_if_run_by_super_user {
    if ($EFFECTIVE_USER_ID == 0) {
        print qq{This program will easily break if you run it as root as you are
trying now.  Please run it as user '$Munin::Common::Defaults::MUNIN_USER'.  The correct 'su' command
on many systems is 'su - munin --shell=/bin/bash'
Aborting.
};
        exit 1;
    }
}

sub print_version_and_exit {
    print qq{munin version $Munin::Common::Defaults::MUNIN_VERSION.

Copyright (C) 2002-2018 Contributors of Munin

This is free software released under the GNU General Public
License. There is NO warranty; not even for MERCHANTABILITY or FITNESS
FOR A PARTICULAR PURPOSE. For details, please refer to the file
COPYING that is included with this software or refer to
http://www.fsf.org/licensing/licenses/gpl.txt
};
    exit 0;
}

1;

__END__

=head1 NAME

Munin::Master::Utils - Utility functions.

=head1 SYNOPSIS

 use Munin::Master::Utils;

=head1 SUBROUTINES

=over

=item B<munin_mkdir_p>

 munin_mkdir_p('/a/path/', oct('777'));

Make a directory and recursively any nonexistent directory in the path.

=item B<exit_if_run_by_super_user>

Exit if running as root.

=item B<print_version_and_exit>

Print version and exit.

=back

=head1 COPYING

Copyright (C) 2010-2014 Steve Schnepp

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; version 2 dated June,
1991.

=cut
