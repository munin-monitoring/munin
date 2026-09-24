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
use Storable;
use Scalar::Util qw(isweak weaken);

our (@ISA, @EXPORT);

@ISA = ('Exporter');
@EXPORT = qw(
	   munin_mkdir_p
	   print_version_and_exit
	   exit_if_run_by_super_user
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
