package Munin::Master;  # -*- cperl -*-

=begin comment

This is Munin::Master, a package common to all munin master binaries.

For the time being it simply provides one common utility function.

Copyright (C) 2013 Nicolai Langfeldt, Broadnet AS

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

=end comment

=cut

use warnings;
use strict;
use Log::Log4perl qw( :easy );

use Exporter;
use RRDs;

our (@ISA, @EXPORT, @rrdc);
@rrdc   = ();
@ISA    = qw(Exporter);
@EXPORT = qw(master_setup prepend_rrdc);

sub master_setup {
    my ($config) = @_;

    # The environment variable is not effective in all cases, i.e. it
    # works in munin-update but not in munin-cgi-graph => Discontinue
    # the use of the environment variable.

    delete $ENV{RRDCACHED_ADDRESS};

    if ( exists $config->{'rrdcached_socket'} ) {

        if ($RRDs::VERSION >= 1.3) {
	    @rrdc = ( '--daemon', $config->{'rrdcached_socket'} );
	    INFO "[INFO] Using rrdcache feature through " .
	      $config->{'rrdcached_socket'};
	} else {
	    WARN "[WARN] RRDCached feature ignored: RRD version must be at least 1.3. Version found: " . $RRDs::VERSION;
	} # if $RRDs::VERSION

    }

    # I wonder if we can put log initialization in here too?
}

sub prepend_rrdc {
    my ( $cmd ) = @_;

    if (@rrdc) {
	DEBUG "Prepend rrdcached ".join(", ", @rrdc )."\n";

        # If we're using RRD Cache Daemon then prepend the options to
        # the rrd command array.
        unshift( @$cmd, @rrdc );
    } else {
        DEBUG "NO rrdcached\n";
    }
}
