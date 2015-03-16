#!/usr/bin/perl

use strict;
use warnings;

use Module::Build;
my $build        = Module::Build->current;
my $MUNIN_BINDIR = $build->install_path('MUNIN_BINDIR');

my $output_file = shift;
open my $fh, ">", $output_file or die "Can't open $output_file: $!";

print $fh <<"EOF";
#!/usr/sh

# This used to test if the executables were installed.  But that is
# perfectly redundant and suppresses errors that the admin should see.

$MUNIN_BINDIR/munin-update \$\@ || exit 1

# The result of munin-limits is needed by munin-html but not by
# munin-graph.  So run it in the background now, it will be done
# before munin-graph.

$MUNIN_BINDIR/munin-limits \$\@

# We always launch munin-html.
# It is a noop if html_strategy is "cgi"
nice $MUNIN_BINDIR/munin-html \$\@ || exit 1

# The result of munin-html is needed for munin-graph.
# It is a noop if graph_strategy is "cgi"
nice $MUNIN_BINDIR/munin-graph --cron \$\@ || exit 1
EOF
