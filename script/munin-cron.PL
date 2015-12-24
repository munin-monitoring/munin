#!/usr/bin/perl

use strict;
use warnings;

use Module::Build;
my $build        = Module::Build->current;
my $MUNIN_BINDIR = $build->install_path('MUNIN_BINDIR');

my $output_file = shift;
open my $fh, ">", $output_file or die "Can't open $output_file: $!";

print $fh <<"EOF";
#!/bin/sh

# This used to test if the executables were installed.  But that is
# perfectly redundant and suppresses errors that the admin should see.

$MUNIN_BINDIR/munin-update \$\@ || exit 1

# Check limits defined for each service, and notify contacts.
# This also writes state read by munin-httpd.

$MUNIN_BINDIR/munin-limits \$\@
EOF
