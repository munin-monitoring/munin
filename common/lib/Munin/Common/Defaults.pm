use warnings;
use strict;

# If you change the class path take a look in get_defaults too, please!
package Munin::Common::Defaults;

use English qw(-no_match_vars);
use File::Basename qw(dirname);

# This file's package variables are changed during the build process.

# This variable makes only sense in development environment
my $COMPONENT_ROOT = dirname(__FILE__) . '/../../..';


our $DROPDOWNLIMIT     = 1;

our $MUNIN_PREFIX     = '';
our $MUNIN_CONFDIR    = "$COMPONENT_ROOT/t/config/";
our $MUNIN_BINDIR     = '';
our $MUNIN_SBINDIR    = '';
our $MUNIN_DOCDIR     = '';
our $MUNIN_LIBDIR     = '';
our $MUNIN_HTMLDIR    = '';
our $MUNIN_CGIDIR     = '';
our $MUNIN_CGITMPDIR     = '';
our $MUNIN_DBDIR      = '';
our $MUNIN_PLUGSTATE  = ''; 
our $MUNIN_SPOOLDIR   = '';
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
our $MUNIN_RUBY       = '';
our $MUNIN_OSTYPE     = '';
our $MUNIN_HOSTNAME   = '';
our $MUNIN_MKTEMP     = '';
our $MUNIN_HASSETR    = '';


sub get_defaults {
    my ($class) = @_;
    
    ## no critic

    no strict 'refs';
    my $defaults = {};
    for my $g (keys %{"Munin::Common::Defaults::"}) {
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

Munin::Common::Defaults - Default values defined by installation
scripts.


=head1 PACKAGE VARIABLES

See L<http://munin-monitoring.org/wiki/MuninInstallProcedure> for
more information on the variables provided by this package.


=head1 METHODS

=over

=item B<get_defaults>

  \%defaults = $class->get_defaults()

Returns all the package variables as key value pairs in a hash.

=item B<export_to_environment>

  $class = $class->export_to_environment()

Export all the package variables to the environment.

=back

