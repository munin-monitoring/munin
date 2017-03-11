#
# Copyright (C) 2013 Diego Elio Pettenò
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
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA
# 02110-1301 USA.

# This Module is user documented inline, interspersed with code with
# perlpod.

=head1 NAME

Munin::Plugin::Framework - Framework for Munin Perl plugins

=head1 SYNOPSIS

This module is designed to implement the basic interface of a Munin
plugin, so that the plugin itself only has to describe what data to
output, instead of having to remember Munin's syntax as well as all
possible expanded functionalities.


=head1 DEBUGGING

Additional debugging messages can be enabled by setting
C<$Munin::Plugin::Framework::DEBUG>, C<$Munin::Plugin::DEBUG>, or by
exporting the C<MUNIN_DEBUG> environment variable before running the
plugin (by passing the C<--pidebug> option to C<munin-run>, for
instance).

=cut

package Munin::Plugin::Framework;

use strict;
use warnings;
use Munin::Plugin;

our ($Plugin, $DEBUG);

# Alias $Munin::Plugin::Framework::DEBUG to $Munin::Plugin::DEBUG, so
# SNMP plugins don't need to import the latter module to get debug
# output.
*DEBUG = \$Munin::Plugin::DEBUG;

sub new {
  my ($class) = shift;
  my (%args)  = @_;

  my $self =
    {
     mode     => ($ARGV[0] || "fetch"),
     hostname => undef,
     graphs   => undef,
    };

  return bless $self, $class;
}

sub add_graphs {
  my $self = shift;
  my (%newgraphs) = @_;

  if ( defined($self->{graphs}) ) {
    $self->{graphs} = { %{$self->{graphs}}, %newgraphs };
  } else {
    $self->{graphs} = { %newgraphs };
  }
}

sub run {
  my ($self) = @_;

  if ( $self->{mode} eq "autoconf" ) {
    my $res = "yes";
    if ( !defined($self->{graphs}) || scalar( keys %{ $self->{graphs} } ) == 0 ) {
      $res = "no (no graphs configured)";
    } elsif ( ref($self->{autoconf}) eq "CODE" ) {
      $res = $self->{autoconf}() if $self->{autoconf};
    } elsif ( defined($self->{autoconf}) ) {
      $res = $self->{autoconf};
    }

    print $res, "\n";
    exit 0;
  } elsif ( $self->{mode} eq "config" ) {
    $self->{pre_config}() if $self->{pre_config};

    printf "host_name %s\n", $self->{hostname} if $self->{hostname};

    while (my ($name, $graph) = each %{ $self->{graphs} } ) {
      printf "multigraph %s\n", $name;

      foreach my $config (qw(title args vlabel category info order total)) {
	printf "graph_%s %s\n", $config, $graph->{$config}
	  if defined($graph->{$config});
      }

      my $scale = $graph->{scale} || "yes";
      if ( $scale eq "yes" ) {
	# do nothing as this is the default
      } elsif ( $scale ne "no" ) {
	print STDERR "Invalid value $scale for ${name}'s scale.\n" if $DEBUG;
      } else {
	print "graph_scale no\n";
      }

      while ( my ($field, $data) = each %{ $graph->{fields} } ) {
	printf "%s.label %s\n", $field, ($data->{label} || $field);

	my $draw = $data->{draw} || "LINE2";
	if ( $draw eq "LINE2" ) {
	  # do nothing as this is the default
	} elsif ( !grep($draw, qw(AREA LINE1 LINE2 LINE3 STACK)) ) {
	  print STDERR "Invalid data draw $draw for $field.\n" if $DEBUG;
	} else {
	  printf "%s.draw %s\n", $field, $draw;
	}

	my $type = $data->{type} || "GAUGE";
	if ( $type eq "GAUGE" ) {
	  # do nothing as this is the default
	} elsif ( !grep($type, qw(COUNTER ABSOLUTE DERIVE GAUGE)) ) {
	  print STDERR "Invalid data type $type for $field.\n" if $DEBUG;
	} else {
	  printf "%s.type %s\n", $field, $type;
	}

	if ( $DEBUG and
	     $data->{negative} and
	     !defined($graph->{fields}->{$data->{negative}}) ) {
	  print STDERR "Invalid negative data line ", $data->{negative}, " for $field.\n";
	}

	foreach my $config (qw(max min info extinfo negative graph cdef colour sum stack line)) {
	  printf "%s.%s %s\n", $field, $config, $data->{$config}
	    if defined($data->{$config});
	}

	my ($defwarning, $defcritical) = get_thresholds($field);
	my $warning  = defined($data->{warning})  ? $data->{warning}  : $defwarning;
	my $critical = defined($data->{critical}) ? $data->{critical} : $defcritical;

	printf "%s.warning %s\n",  $field, $warning  if defined($warning);
	printf "%s.critical %s\n", $field, $critical if defined($critical);
      }
      print "\n";
    }

    unless ( ($ENV{MUNIN_CAP_DIRTYCONFIG} || 0) == 1 ) {
      exit 0;
    }
  } elsif ( $self->{mode} ne "fetch" ) {
    print STDERR "Paramenter " . $self->{mode} . " unsupported\n" if $DEBUG;

    exit 1;
  }

  $self->{pre_fetch}() if $self->{pre_fetch};

  while (my ($name, $graph) = each %{$self->{graphs}} ) {
    printf "multigraph %s\n", $name;

    while ( my ($field, $data) = each %{$graph->{fields}} ) {
      printf "%s.value %s\n", $field, (defined($data->{value}) ? $data->{value} : "U");
    }
  }
}
