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
	   munin_get_bool
	   munin_get
	   munin_get_rrd_filename
	   munin_get_node_name
	   munin_get_node_loc
	   munin_get_node
	   munin_set_var_loc
	   munin_set
	   munin_mkdir_p
	   munin_find_field_for_limits
	   munin_get_children
	   munin_has_subservices
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

Munin::Master::Utils - Exports a lot of utility functions.

=head1 SYNOPSIS

 use Munin::Master::Utils;

=head1 SUBROUTINES

=over

=item B<munin_copy_node>

Copy hash node.

Parameters:
 - $from: Hash node to copy
 - $to: Where to copy it to

Returns:
 - Success: $to
 - Failure: undef


=item B<munin_delete>



=item B<munin_get>

Get variable.

Parameters:
 - $hash: Ref to hash node
 - $field: Name of field to get
 - $default: [optional] Value to return if $field isn't set

Returns:
 - Success: field contents
 - Failure: $default if defined, else undef


=item B<munin_get_bool>

Get boolean variable.

Parameters:
 - $hash: Ref to hash node
 - $field: Name of field to get
 - $default: [optional] Value to return if $field isn't set

Returns:
 - Success: 1 or 0 (true or false)
 - Failure: $default if defined, else undef


=item B<munin_get_children>

Get all child hash nodes.

Parameters:
 - $hash: A hash ref to the parent node

Returns:
 - Success: A ref to an array of the child nodes
 - Failure: undef


=item B<munin_get_node>

Gets a node by loc.

Parameters:
 - $hash: A ref to the hash to set the variable in
 - $loc: A ref to an array with the full path of the node

Returns:
 - Success: The node ref found by $loc
 - Failure: undef

=item B<munin_get_node_loc>

Get location array for hash node.

Parameters:
 - $hash: A ref to the node

Returns:
 - Success: Ref to an array with the full path of the variable
 - Failure: undef


=item B<munin_get_node_name>

Return the name of the hash node supplied.

Parameters:
 - $hash: A ref to the hash node

Returns:
 - Success: The name of the node


=item B<munin_get_root_node>

Get the root node of the hash tree.

Parameters:
 - $hash: A hash node to traverse up from

Returns:
 - Success: A ref to the root hash node
 - Failure: undef


=item B<munin_get_rrd_filename>

Get the name of the rrd file corresponding to a field. Checks for lots
of bells and whistles.  This function is the correct one to use when
figuring out where to fetch data from.

Parameters:
 - $field: The hash object of the field
 - $path: [optional] The path to the field (as given in graph_order/sum/stack/et al)

Returns:
 - Success: A string with the filename of the rrd file
 - Failure: undef


=item B<munin_get_var_path>



=item B<munin_has_subservices>

  munin_has_subservices($hash);

Checks whether the service represented by $hash has subservices (multigraph),
and returns the result.

Parameters:
 - $hash: Hash reference pointing to a service

Returns:
 - true: if the hash is indeed a service, and said service has got subservices
 - false: otherwise


=item B<munin_mkdir_p>

 munin_mkdir_p('/a/path/', oct('777'));

Make a directory and recursively any nonexistent directory in the path
to it.


=item B<munin_parse_config>



=item B<munin_path_to_loc>

Returns a loc array from a path string.

Parameters:
 - $path: A path string

Returns:
 - Success: A ref to an array with the loc
 - Failure: undef


=item B<munin_set>

Sets a variable in a hash.

Parameters:
 - $hash: A ref to the hash to set the variable in
 - $var: The name of the variable
 - $val: The value to set the variable to

Returns:
 - Success: The $hash we were handed
 - Failure: undef


=item B<munin_set_var_loc>

Sets a variable in a hash.

Parameters:
 - $hash: A ref to the hash to set the variable in
 - $loc: A ref to an array with the full path of the variable
 - $val: The value to set the variable to

Returns:
 - Success: The $hash we were handed
 - Failure: undef


=back

=head1 COPYING

Copyright (C) 2010-2014 Steve Schnepp
Copyright (C) 2003-2011 Jimmy Olsen
Copyright (C) 2006-2010 Nicolai Langfeldt
Copyright (C) Audun Ytterdal

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
Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

=cut
