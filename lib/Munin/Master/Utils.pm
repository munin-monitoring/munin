package Munin::Master::Utils;


use strict;
use warnings;

use Carp;
use Exporter;
use English qw(-no_match_vars);
use Fcntl qw(:DEFAULT :flock);
use File::Path;
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
@EXPORT = (
	   'munin_removelock',
	   'munin_runlock',
	   'munin_getlock',
	   'munin_readconfig_raw',
	   'munin_writeconfig',
	   'munin_writeconfig_storable',
	   'munin_read_storable',
	   'munin_write_storable',
	   'munin_overwrite',
	   'munin_dumpconfig',
	   'munin_dumpconfig_as_str',
	   'munin_readconfig_base',
	   'munin_readconfig_part',
	   'munin_get_bool',
	   'munin_get',
	   'munin_get_picture_loc',
	   'munin_get_filename',
	   'munin_get_keypath',
	   'munin_get_rrd_filename',
	   'munin_get_node_name',
	   'munin_get_orig_node_name',
	   'munin_get_parent_name',
	   'munin_get_node_fqn',
	   'munin_get_node_loc',
	   'munin_get_node',
	   'munin_set_var_loc',
	   'munin_set_var_path',
	   'munin_set',
	   'munin_copy_node_toloc',
	   'munin_mkdir_p',
	   'munin_find_field',
	   'munin_find_field_for_limits',
	   'munin_get_parent',
	   'munin_get_children',
	   'munin_get_node_partialpath',
	   'munin_has_subservices',
	   'print_version_and_exit',
	   'exit_if_run_by_super_user',
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


sub munin_removelock {
    # Remove lock or die trying.
    my ($lockname) = @_;

    unlink $lockname or
      LOGCROAK("[FATAL ERROR] Error deleting lock $lockname: $!\n");
}


sub munin_runlock {
    my ($lockname) = @_;
    unless (munin_getlock($lockname)) {
	LOGCROAK("[FATAL ERROR] Lock already exists: $lockname. Dying.\n");
    }
    return 1;
}


sub munin_getlock {
    my ($lockname) = @_;
    my $LOCK;

    if (sysopen (LOCK, $lockname, O_RDWR | O_CREAT)) {
	DEBUG "[DEBUG] Create/open lock : $lockname succeeded\n";
    } else {
	LOGCROAK("Could not open $lockname for read/write: $!\n");
    }
    my $pid = <LOCK>;

    if (defined($pid)) {
	
	DEBUG "[DEBUG] Lock contained pid '$pid'";
	
        # Make sure it's a proper pid
	if ($pid =~ /^(\d+)$/ and $1 != 1) {
	    $pid = $1;
	    kill(0, $pid);
	    # Ignore ESRCH as not found is as good as if it worked
	    if ($! == EPERM) {
		LOGCROAK("[FATAL ERROR] kill -0 $pid attempted - it is still alive and we can't kill it. Locking failed.\n");
		close LOCK;
	        return 0;
	    }
	    INFO "[INFO] Process $pid is dead, stealing lock";
	} else {
	    INFO "[INFO] PID in lock file is bogus.";
	}
        seek(LOCK, 0, 0);
    }
    DEBUG "[DEBUG] Writing out PID to lock file $lockname";
    print LOCK $$; # we want the pid inside for later use
    if (defined($pid) && length $$ < length $pid) {
	# Since pid was defined we need to truncate in case len($) < len($pid)
	truncate(LOCK, tell(LOCK))
    }
    close LOCK;
    return 1;
}

sub munin_mkdir_p {
    my ($dirname, $umask) = @_;

    eval {
        mkpath($dirname, 0, $umask);
    };
    return if $EVAL_ERROR;
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

=item B<munin_readconfig_base>

Read configuration file, include dir files, and initialize important
default values that are optional.

Parameters:
 - $file: munin.conf filename. If omitted, default filename is used.

Returns:
 - Success: The $config hash (also cached in module)

=item B<munin_copy_node>

Copy hash node.

Parameters:
 - $from: Hash node to copy
 - $to: Where to copy it to

Returns:
 - Success: $to
 - Failure: undef


=item B<munin_copy_node_toloc>

Copy hash node at.

Parameters:
 - $from: Hash node to copy
 - $to: Where to copy it to
 - $loc: Path to node under $to

Returns:
 - Success: $to
 - Failure: undef


=item B<munin_createlock>



=item B<munin_delete>



=item B<munin_find_field>

Search a hash to find hash nodes with $field defined.

Parameters: 
 - $hash: A hash ref to search
 - $field: The name of the field to search for, or a regex
 - $avoid: [optional] Stop traversing further down if this field is found

Returns:
 - Success: A ref to an array of the hash nodes containing $field.
 - Failure: undef


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


=item B<munin_get_filename>

Get rrd filename for a field, without any bells or whistles. Used by
munin-update to figure out which file to update.

Parameters:
 - $hash: Ref to hash field

Returns:
 - Success: Full path to rrd file
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


=item B<munin_get_node_partialpath>

Gets a node from a partial path.

Parameters: 
 - $hash: A ref to the "current" location in the hash tree
 - $var: A path string with relative location (from the $hash).

Returns:
 - Success: The node
 - Failure: undef


=item B<munin_get_parent>

Get parent node of a hash.

Parameters: 
 - $hash: A ref to the node

Returns:
 - Success: Ref to an parent
 - Failure: undef


=item B<munin_get_parent_name>

Return the name of the parent of the hash node supplied

Parameters: 
 - $hash: A ref to the hash node

Returns:
 - Success: The name of the parent node
 - Failure: If no parent node exists, "none" is returned.


=item B<munin_get_picture_loc>

Get location array for hash node for picture purposes. Differs from
munin_get_node_loc in that it honors #%#origin metadata

Parameters: 
 - $hash: A ref to the node 

Returns: 
 - Success: Ref to an array with the full path of the variable
 - Failure: undef


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



=item B<munin_getlock>



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


=item B<munin_overwrite>

Take contents of one config-namespace and replace/insert the instances
needed.

=item B<munin_parse_config>



=item B<munin_path_to_loc>

Returns a loc array from a path string.

Parameters: 
 - $path: A path string

Returns:
 - Success: A ref to an array with the loc
 - Failure: undef


=item B<munin_readconfig_part>

Read a partial configuration

Parameters:
 - $what: name of the part that should be loaded (datafile or limits)

Returns:
 - Success: a $config with the $specified part, but overwritten by $config

=item B<munin_removelock>



=item B<munin_runlock>



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


=item B<munin_set_var_path>

Sets a variable in a hash.

Parameters: 
 - $hash: A ref to the hash to set the variable in
 - $var: A string with the full path of the variable
 - $val: The value to set the variable to

Returns:
 - Success: The $hash we were handed
 - Failure: The $hash we were handed


=item B<munin_writeconfig>



=item B<munin_writeconfig_loop>



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
