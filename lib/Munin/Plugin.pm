#
# Copyright (C) 2007-2008 Nicolai Langfeldt
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; version 2 dated June,
# 1991.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA
#
#

package Munin::Plugin;

use warnings;
use strict;

# Put only core Perl modules here, as we don't want to ask for more deps
use File::Temp; # File::Temp was first released with perl 5.006001

# This file uses subroutine prototypes. This is considered a bad
# practice according to PBP (see page 194).

## no critic Prototypes

=head1 NAME 

Munin::Plugin - Utility functions for Perl Munin plugins.

=head2 Usage

  use lib $ENV{'MUNIN_LIBDIR'};
  use Munin::Plugin;

If your Munin installation predates the MUNIN_* environment variables
(introduced in 1.3.3) you can put this in your plugin configuration:

  [*]
      env.MUNIN_PLUGSTATE /var/lib/munin-node/plugin-state
      env.MUNIN_LIBDIR /usr/share/munin

IF, indeed that is the munin plugin state directory.  The default
install directory for Munin::Plugin is in Perl's module search path,
the "use lib" is there for the cases where this is not so, and the
variable needs to be set to stop Perl from complaining.

The module exports these functions: clean_fieldname,
set_state_name, save_state, restore_state, tail_open, tail_close.

=cut

use Exporter;
our @ISA = ('Exporter');
our @EXPORT = qw(
        clean_fieldname
        set_state_name save_state restore_state
        get_thresholds print_thresholds adjust_threshold
        tail_open tail_close
        scaleNumber
        need_multigraph
        readfile
        readarray
);

use Munin::Common::Defaults;

=head2 Variables

The module instantiates a number of variables in the $Munin::Plugin
scope.  None of these are exported, and they must be referenced by the
full names shown here.

=head3 $Munin::Plugin::me

The name of the plugin without any prefixing directory names and so
on.  Same as "basename $0" in a shell.  It is a very good idea to use
this in warning and/or error messages so that the logs show clearly
what plugin the error message comes from.

=cut

our $me = (split '/', $0)[-1];

=head3 $Munin::Plugin::pluginstatedir

Identical to the environment variable MUNIN_PLUGSTATE (available since
Munin 1.3.3)

You can use this if you need to save several different state files.
But there is also a function to change the state file name so the
state file support functions can be used for several state files.

If its value cannot be determined the plugin will be aborted at once
with an explanatory message.  The most likely causes are:

=over 8

=item *
You are running the plugin directly and not from munin-node or munin-run;

=item *
Your munin-node is too old;

=item *
munin-node was installed incorrectly.

=back

The two last points can be worked around by the plugin configuration
shown at the beginning of this document.

=cut

our $pluginstatedir = $ENV{'MUNIN_PLUGSTATE'}
                      || $Munin::Common::Defaults::MUNIN_PLUGSTATE;

=head3 $Munin::Plugin::statefile

The automatically calculated name for the plugins state file.  The
name is supplied by munin-node or munin-run (in the MUNIN_STATEFILE
environment variable).  The file name contains the plugin name and the
IP address of the munin-master the node is talking to (munin-run leaves
the master part blank).  This enables stateful plugins that calculate
gauges and assume a 5 minute run interval to work correctly in setups
with multiple masters (this is not a uncommon way to set up Munin).

To change the value of this please use the C<set_state_name($)>
procedure (see below).

=cut

our $statefile = $ENV{'MUNIN_STATEFILE'};

=head3 $Munin::Plugin::DEBUG

Set to true if the plugin should emit debug output.  There are some
(but not many) debug print statements in the Module as well, which all
obey this variable.  Set from the MUNIN_DEBUG environment variable.
Defaults to false (0).

=cut

our $DEBUG = $ENV{'MUNIN_DEBUG'} || 0;

=head2 Functions

=head3 $fieldname = clean_fieldname($input_fieldname)

Munin plugin field names are restricted with regards to what
characters they may use: The characters must be C<[a-zA-Z0-9_]>, while
the first character must be C<[a-zA-Z_]>.  To satisfy these demands
the function replaces illegal characters with a '_'.

See also
L<http://munin-monitoring.org/wiki/notes_on_datasource_names>

=cut

sub clean_fieldname ($) {
    my $name = shift;

    # Replace a sequence of illegal leading chars with a single _
    $name =~ s/^[^A-Za-z_]+/_/;
    # Replace remaining illegals with _
    $name =~ s/[^A-Za-z0-9_]/_/g;

    # "root" is *not* allowed due to a 2.0 bug
    $name = "__root" if $name eq "root";

    return $name;
}


=head3 set_state_name($statefile_name)

Override the default statefile name.  This only modifies the filename
part, not the directory name. The function unconditionally appends
"-$MUNIN_MASTER_IP" to the file name to support multiple masters as
described in the documentation for the statefile variable (above).

Calling this function is not normally needed and is not recommended.

=cut

sub set_state_name ($) {
    my ($filename) = @_;
    return $statefile = "$pluginstatedir/$filename-$ENV{MUNIN_MASTER_IP}";
};


sub _encode_string {
    # Internal function: URL encode a few characters that save_state
    # breaks on otherwise

    my ($s) = @_;

    # This is to do a general URL encode
    # $str =~ s/([^A-Za-z0-9])/sprintf("%%%02X", ord($1))/seg;

    # But we do a restricted because that's all we need.  I hope O:-)
    $s =~ s/%/%25/g;
    $s =~ s/\n/%0A/g;
    $s =~ s/\r/%0D/g;

    return $s;
}


sub _decode_string {
    # Internal function: URL decode a string
    my ($s) = @_;

    # General URL decode, just in case.  "Be graceful about what you
    # accept" you know.
    $s =~ s/\%([A-Fa-f0-9]{2})/pack('C', hex($1))/seg;

    return $s;
};


sub _encode_state (@) {
    # Internal function: Return an encoded instance of the state vector
    my @ns;

    @ns = map { _encode_string($_); } @_;

    return @ns;
};


sub _decode_state (@) {
    # Internal function: Return a decoded instance of the state vector
    my @ns = @_;

    @ns = map { _decode_string($_); } @_;

    return @ns;
};


=head3 save_state(@state_vector)

Save the passed state vector to the state file appropriate for the
plugin.  The state vector should contain only strings (or numbers),
and absolutely no objects or references.  The strings may contain
newlines without ill effect.

If the file cannot be opened for writing the plugin will be aborted.

The state file name is determined automatically based on the
name of the process we're running as.  See L<$Munin::Plugin::me>,
L<$Munin::Plugin::statefile> and L<set_state_name> above about the
file name.

The file will contain a starting line with a magic number so that the
library can see the difference between an actual state file and a file
containing rubbish.  Currently this magic number is
'%MUNIN-STATE1.0\n'. Files with this magic number will contain the
vector verbatim with \r, \n and % URL encoded.

The function takes security precautions, like protesting fatally if the
state file is a symbolic link (symbolic link overwriting can have
unfortunate security ramifications).

=cut

sub save_state (@) {
    print "State file: $statefile\n" if $DEBUG;

    # Open a tempfile, to rename() after. ensures atomic updates.
    my $STATE = File::Temp->new(DIR => $pluginstatedir, UNLINK => 0 )
	or die "$me: Could not open temporary statefile in '$pluginstatedir' for writing: $!\n";

    # Munin-state 1.0 encodes %, \n and \r in URL encoding and leaves
    # the rest.
    print $STATE "%MUNIN-STATE1.0\n";
    print $STATE join("\n",_encode_state(@_)),"\n";

    close $STATE;

    rename($STATE->filename, $statefile);
}

=head3 @state_vector = restore_state()

Read state from the state file written by L<save_state(@)>. If
everything is OK the state vector will be returned.

undef will be returned if the file cannot be opened.  Likewise if it
does not have a recognized magic number (in this case a warning will
also be printed, which will appear in the munin-node logs).

=cut

sub restore_state {
	my @state;
	# Protects _restore_state_raw() with an eval()
	eval { @state = _restore_state_raw(); };
	if ($@) { @state = (); warn $@; }

	return _decode_state(@state);
}

sub _restore_state_raw {
    my $STATE;
    if (-e $statefile) {
        open $STATE, '<', $statefile or die "$me: Statefile exists but I cannot open it!";
    } else {
        return;
    }

    # Read a state vector from a plugin appropriate state file
    local $/;

    my @state = split(/\n/, <$STATE>);
    my $filemagic = shift(@state);

    if ($filemagic ne '%MUNIN-STATE1.0') {
	die "$me: Statefile $statefile has unrecognized magic number: '$filemagic'\n";
    }

    return @state;
}

=head3 ($warning, $critical) = get_thresholds($field, [$warning_env, [$critical_env]])

Look up the thresholds for the specified field from the environment
variables named after the field: "$field_warning" and
"$field_critical".  Return their values.  If there are no
$field_warning or $field_critical values then look for the variables
"warning" and "critical" and return those values if any.

If the second and/or third arguments are specified then they will be
used to specify the name of variables giving the warning and
critical levels.

If no values are found for a threshold then undef is returned.

=cut

sub get_thresholds {
    my ($field, $warning_env, $critical_env,
	$warning_default, $critical_default) = @_;
    my ($warning, $critical);

    # First look for explicitly specified warning environment variables

    $warning = $ENV{$warning_env}
      if defined($warning_env) and defined($ENV{$warning_env});

    $critical = $ENV{$critical_env}
      if defined($critical_env) and defined($ENV{$critical_env});

    # Then look for more and more generic ones

    $warning  = $warning || $ENV{$field."_warning"}  ||
	$ENV{"warning"}  || $warning_default;

    $critical = $critical || $ENV{$field."_critical"} ||
	$ENV{"critical"} || $critical_default;

    return ($warning, $critical);
}

=head3 print_thresholds($field, [$warning_env, [$critical_env]])

If $field has warning or critical thresholds set for it, prints them in the
default fashion (eg. 'field.warning 42').

See get_thresholds for an explanation of the arguments.

=cut

sub print_thresholds {
    my $field = $_[0];
    my ($warning, $critical) = get_thresholds(@_);
    print "$field.warning $warning\n" if defined($warning);
    print "$field.critical $critical\n" if defined($critical);
}

=head3 adjust_threshold($threshold, $base)

If $threshold contains % signs, return a new threshold with adjusted values for
these percentages against $base.

=cut

sub adjust_threshold {
    my ($threshold, $base) = @_;

    return undef if(!defined $threshold or !defined $base);

    $threshold =~ s!(\d+\.?\d*)%!$1*$base/100!eg;

    return $threshold;
}

=head3 ($file_handle,$rotated) = tail_open($file_name, $position)

Open the file and seek to the given position.  If this position
is beyond the end of the file the function assumes that the file has
been rotated, and the file position will be at the start of the file.

If the file is opened OK the function returns a tuple consisting of
the file handle and a file rotation indicator.  $rotated will be 1 if
the file has been rotated and 0 otherwise.  Also, if the file was
rotated a warning is printed (only in debug mode, this can be found
in the munin-node log or seen in the terminal when using munin-run).

At this point the plugin can read from the file with <$file_handle> in
loop as usual until EOF is encountered.

If the file cannot be stat'ed C<(undef,undef)> is returned.  If the
file cannot be opened for reading the plugin is aborted with a error
in the interest of error-obviousness.

=cut

sub tail_open ($$) {
    my ($file,$position) = @_;

    my $filereset=0;

    my $size = (stat($file))[7];

    warn "**Size of $file is $size\n" if $DEBUG;

    if (!defined($size)) {
	warn "$me: Could not stat input file '$file': $!\n";
	return (undef,undef);
    }

    open my $FH, '<', $file or
      die "$me: Could not open input file '$file' for reading: $!\n";

    if ($position > $size) {
	warn "$me: File rotated, starting at start\n" if $DEBUG;
	$filereset=1;
    } elsif (!seek($FH, $position, 0)) {
	die "$me: Seek to position $position of '$file' failed: $!\n";
    }
    return ($FH, $filereset);
}


=head3 $content = readfile($path)

Read the whole content of a file (usually a single line) into a scalar.

This is extremely helpful when reading data out of /proc or /sys that
the kernel exposes.

=cut

sub readfile($) {
  my ($path) = @_;

  open my $FH, "<", $path or return undef;
  local $/;
  my $content = <$FH>;
  close $FH;

  return $content;
}

=head3 $content = readarray($path)

Read the first line of a file into an array.

This is extremely helpful when reading data out of /proc or /sys that
the kernel exposes.

Returns undef if the file does not exist.
Returns an empty array if the file is empty (or contains only whitespace).

=cut

sub readarray($) {
  my ($path) = @_;

  open my $FH, "<", $path or return undef;
  my $line = <$FH>;
  # handle an empty file gracefully
  $line = "" if not defined($line);
  chomp($line);
  my @row = split(/\s+/, $line);
  close $FH;

  return @row;
}

=head3 $position = tail_close($file_handle)

Close the file and return the current position in the file.  This
position can be stored in a state file until the next time the plugin runs.

If the C<close> system call fails, a warning will be printed (which can be
found in the munin-node log or seen when using munin-run).

=cut

sub tail_close ($) {
    my ($FH) = @_;

    my $position = tell($FH);

    # If this ever hits us I'll be amazed.
    close($FH) or
      warn "$me: Could not close input file: $!\n";

    return $position;
}

=head3 $string = scaleNumber($number, $unit, $ifZero, $format);

Returns a string representation of the given number scaled in SI
prefixes such as G(iga), M(ega), and k(ilo), m(illi), u (for micro)
and so on for magnitudes from 10^-24 to 10^24.

The $unit is the base unit for the number and is appended to the
prefix.

The contents of $ifZero is used if the number is 0 (smaller than
10^-26), instead of any other string.  In some contexts "" (empty
string) is most appropriate and sometimes "0" without any scale or
prefix is more appropriate.

$format can be any valid Perl printf format string.  The default is
"%.1f%s%s".

The $format may be specified as a whole string such as "The interface
speed is %.1f%s%s.".  In that case, $ifZero could be set to "The
interface is down" -- some equipment uses an interface speed of 0 for
a downed interface, and some don't.

=cut

sub scaleNumber {
    my $number = shift;
    my $unit = shift;
    my $zero = shift;
    my $format = shift || '%.1f%s%s';

    my %large = (1E+24, 'Y',  # yotta
		 1E+21, 'Z',  # zetta
		 1E+18, 'E',  # exa
		 1E+15, 'P',  # peta
		 1E+12, 'T',  # tera
		 1E+9,  'G',  # giga
		 1E+6,  'M',  # mega
		 1E+3,  'k',  # kilo
		 1,     '');  # nothing

    my %small = (1,     '',   # nothing
		 1E-3,  'm',  # milli
		 1E-6,  'u',  # micro
		 1E-9,  'n',  # nano
		 1E-12, 'p',  # pico
		 1E-15, 'f',  # femto
		 1E-18, 'a',  # atto
		 1E-21, 'z',  # zepto
		 1E-24, 'y'); # yocto

    # Get the absolute and exaggerate it slightly since floating point
    # numbers don't compare very well.
    my $absnum = abs($number) * 1.0000001;

    if ($absnum < 1E-26) {
	# So small it might as well be zero.  If compared against
	# 1E-27 we'll get "Illegal division by zero", so we're damn
	# close to nothing.
	if (defined($zero)) {
	    return $zero;
	} else {
	    return sprintf $format, $number, '', $unit;
	}
    } elsif ($absnum > 1) {
	my $mag = 0;
	for my $magnitude (sort { $a <=> $b } keys %large) {
	    last if $magnitude >= $absnum;
	    $mag = $magnitude;
	}
	return sprintf $format, $number/$mag, $large{$mag}, $unit;
    } else {
	# Less than 1 but greater than zero
	my $mag = 0;
	for my $magnitude (sort { $a <=> $b } keys %small) {
	    last if $magnitude >= $absnum;
	    $mag = $magnitude;
	}
	return sprintf $format, $number/$mag, $small{$mag}, $unit;
    }
}


=head3 need_multigraph()

Should be called at the top of all multigraph plugins.

Checks the current environment, and exits with appropriate output
if it doesn't support multigraph plugins.

=cut

sub need_multigraph {
    return if $ENV{MUNIN_CAP_MULTIGRAPH};

    if (-t and (!$ARGV[0] or ($ARGV[0] eq 'config'))) {

	# Catch people running the plugin on the command line.  Note
	# that munin-node-configure may also be detected as "command
	# line" so be very conditional and careful about it.

	# Observation: Munin-node-configure will first try "autoconf"
	# which will fail so all other modes of running in combination
	# with a tty on STDIN means that it's a human running us.

	print "
Please use at least munin-run 1.4.0 to run this plugin at the command
line.  You are probably looking for the command

   munin-run --servicedir \$PWD $me

This should by preference be run as root, but other users can also be
used as long as the plugin doesn not use a state file and does not
need to be run as a special user or need special privileges.

";

	exit 1;
    }

    if (! $ARGV[0]) {
        print "multigraph.value 0\n";
    }
    elsif ($ARGV[0] eq 'autoconf') {
        print "no (no multigraph support)\n";
    }
    elsif ($ARGV[0] eq 'config') {
        print "graph_title This plugin needs multigraph support\n";
        print "multigraph.label No multigraph here\n";
        print "multigraph.info This plugin has been installed in a munin-node "
            . "that is too old to know about multigraph plugins.  Even if your "
            . "munin master understands multigraph plugins this is not enough, "
            . "the node too needs to be new enough.  Version 1.4.0 or later "
            . "should work.\n"
    }

    exit 0;
}


=head3 Testing

There is some test stuff in this module.

  Test like this:
  MUNIN_PLUGSTATE=/var/lib/munin-node/plugin-state -e 'require "Plugin.pm.in"; Munin::Plugin::_test;' -- or something.

  sub _test () {
    my $pos;
    my $fh;
    my $reset;

    warn "Testing tail and state file.  Press ^C to stop\n";

    do {
	$pos = undef;

	($pos) = restore_state();
	$pos = 0 unless defined($pos);

	($fh,$reset) = tail_open('/var/log/messages',$pos);
	while (<$fh>) {
	    print;
	}
	$pos = tail_close($fh);
	print "**Position is $pos\n";
	save_state($pos);
    } while sleep 1;
  }

=cut

# _test();

1;
