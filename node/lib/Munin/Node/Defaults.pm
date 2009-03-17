use warnings;
use strict;

package Munin::Node::Defaults;

use English qw(-no_match_vars);
use File::Basename qw(dirname);

# This file's package variables are changed during the build process.

# This variable makes only sense in development environment
my $COMPONENT_ROOT = dirname(__FILE__) . '/../../..';


our $MUNIN_PREFIX     = '';
our $MUNIN_CONFDIR    = "$COMPONENT_ROOT/config//";
our $MUNIN_BINDIR     = '';
our $MUNIN_SBINDIR    = '';
our $MUNIN_DOCDIR     = '';
our $MUNIN_LIBDIR     = '';
our $MUNIN_HTMLDIR    = '';
our $MUNIN_CGIDIR     = '';
our $MUNIN_DBDIR      = '';
our $MUNIN_PLUGSTATE  = ''; 
our $MUNIN_MANDIR     = '';
our $MUNIN_LOGDIR     = "$COMPONENT_ROOT/log/";
our $MUNIN_STATEDIR   = ''; 
our $MUNIN_USER       = getpwuid $UID;
our $MUNIN_GROUP      = getgrgid $GID;
our $MUNIN_PLUGINUSER = getpwuid $UID;
our $MUNIN_VERSION    = 'svn';
our $MUNIN_PERL       = '/usr/bin/perl';
our $MUNIN_PERLLIB    = '';
our $MUNIN_GOODSH     = '';
our $MUNIN_BASH       = '';
our $MUNIN_PYTHON     = '';
our $MUNIN_OSTYPE     = '';
our $MUNIN_HOSTNAME   = '';
our $MUNIN_MKTEMP     = '';
our $MUNIN_HASSETR    = '';


sub get_defaults {
    my ($class) = @_;
    
    ## no critic

    no strict 'refs';
    my $defaults = {};
    for my $g (keys %{Munin::Node::Defaults::}) {
        next unless $g =~ /MUNIN_/;
        $defaults->{$g} = ${*$g{'SCALAR'}};
    }

    ## use critic

    return $defaults;
}


sub export_to_environment {
    my ($class) = @_;

    my %defaults = %{$class->get_defaults()};
    while (my ($k, $v) = each %defaults) {
        $ENV{$k} = $v;
    }

    return
}


1;


__END__


=head1 NAME

Munin::Node::Defaults - Default values defined by installation scripts


=head1 PACKAGE VARIABLES

FIX Document each and every one? Or point to some other doc?


=head1 METHODS

=over

=item B<get_defaults>

  \%defaults = $class->get_defaults()

FIX

=item B<export_to_environment>

  $class = $class->export_to_environment()

FIX

=back

