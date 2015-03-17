#!/usr/bin/perl

use strict;
use warnings;

my $output_file = shift;
open my $fh, ">", $output_file or die "Can't open $output_file: $!";


print $fh <<'EOF_HEADER';

=head1 NAME

Munin - Module to keep track of Munin install information.

=head1 DESCRIPTION

This module contains package variables for locating the configuration files used by Munin.

=head1 SYNOPSIS

=head2 From perl
    use Munin

    printf "MUNIN_CONF='%s'\n", Munin::munin_conf;
    printf "MUNIN_NODE_CONF='%s'\n", Munin::munin_node_conf;

=head2 From shell

    munin_conf=$(perl -MMunin -e 'print $Munin::munin_conf')

=head1 LICENSE

GPL v2 or later

=begin comment

Copyright (C) 2014, 2015 Stig Sandbeck Mathisen

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.

=end comment

=cut

package Munin;

use warnings;
use strict;

EOF_HEADER


print $fh <<"EOF";
our \$munin_conf      = '/etc/munin/munin.conf';
our \$munin_node_conf = '/etc/munin/munin-node.conf';
EOF


print $fh <<'EOF_FOOTER';

# This file was generated when building munin.
1;
EOF_FOOTER
