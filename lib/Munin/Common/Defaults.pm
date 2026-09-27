use warnings;
use strict;

package Munin::Common::Defaults;

use English qw(-no_match_vars);
use File::Basename qw(dirname);

# This file's package variables are changed during an installation procedure.
# This variable makes only sense in development environment
my $COMPONENT_ROOT = dirname(__FILE__) . '/../../..';

our $DROPDOWNLIMIT = 1;

our $MUNIN_CONFDIR    = '/etc/munin';
our $MUNIN_LIBDIR     = '/var/lib/munin';
our $MUNIN_HTMLDIR    = '/var/www/html/munin';
our $MUNIN_CGITMPDIR  = '/var/lib/munin/cgi-tmp';
our $MUNIN_DBDIR      = '/var/lib/munin';
our $MUNIN_PLUGSTATE  = '/var/lib/munin/plugin-state';
our $MUNIN_SPOOLDIR   = '/var/lib/munin';
our $MUNIN_LOGDIR     = '/var/log/munin';
our $MUNIN_STATEDIR   = '/run/munin';
our $MUNIN_USER       = $OSNAME eq 'MSWin32' ? '' : getpwuid $EUID;
our $MUNIN_GROUP      = $OSNAME eq 'MSWin32' ? '' : getgrgid $EGID;
our $MUNIN_PLUGINUSER = $OSNAME eq 'MSWin32' ? '' : getpwuid $EUID;
our $MUNIN_VERSION    = '2.1.0';
our $MUNIN_PERL       = '/usr/bin/perl';
our $MUNIN_HASSETR    = '';

sub get_defaults {
    my ($class) = @_;

    no strict 'refs';
    my $defaults = {};
    for my $g ( keys %{"Munin::Common::Defaults::"} ) {
        next unless $g =~ /MUNIN_/;
        $defaults->{$g} = ${ *$g{'SCALAR'} };
    }

    return $defaults;
}

sub export_to_environment {
    my ($class) = @_;

    my %defaults = %{ $class->get_defaults() };
    while ( my ( $k, $v ) = each %defaults ) {
        $ENV{$k} = $v;
    }

    return;
}

1;

__END__


=head1 NAME

Munin::Common::Defaults - Default values for Munin paths and settings.


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

=cut
