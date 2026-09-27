use warnings;
use strict;

# This module contains default values for Munin paths and settings.
# It is a static file with FHS-compliant paths.
# Distributions should patch this file directly instead of using
# code generation.
#
# To change a default, edit the corresponding variable below.
# For example:
#   our $MUNIN_CONFDIR = '/etc/munin-custom';

package Munin::Common::Defaults;

use English qw(-no_match_vars);
use File::Basename qw(dirname);

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

    return {
        MUNIN_CONFDIR    => $MUNIN_CONFDIR,
        MUNIN_LIBDIR     => $MUNIN_LIBDIR,
        MUNIN_HTMLDIR    => $MUNIN_HTMLDIR,
        MUNIN_CGITMPDIR  => $MUNIN_CGITMPDIR,
        MUNIN_DBDIR      => $MUNIN_DBDIR,
        MUNIN_PLUGSTATE  => $MUNIN_PLUGSTATE,
        MUNIN_SPOOLDIR   => $MUNIN_SPOOLDIR,
        MUNIN_LOGDIR     => $MUNIN_LOGDIR,
        MUNIN_STATEDIR   => $MUNIN_STATEDIR,
        MUNIN_USER       => $MUNIN_USER,
        MUNIN_GROUP      => $MUNIN_GROUP,
        MUNIN_PLUGINUSER => $MUNIN_PLUGINUSER,
        MUNIN_VERSION    => $MUNIN_VERSION,
        MUNIN_PERL       => $MUNIN_PERL,
        MUNIN_HASSETR    => $MUNIN_HASSETR,
    };
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


=head1 DESCRIPTION

This module contains default values for Munin paths and settings.
It is a static file with FHS-compliant paths.

Distributions should patch this file directly instead of using
code generation.


=head1 PATHS

=over

=item B<MUNIN_CONFDIR>

Configuration directory. Default: /etc/munin

=item B<MUNIN_LIBDIR>

Library directory. Default: /var/lib/munin

=item B<MUNIN_HTMLDIR>

HTML output directory. Default: /var/www/html/munin

=item B<MUNIN_DBDIR>

Database directory. Default: /var/lib/munin

=item B<MUNIN_LOGDIR>

Log directory. Default: /var/log/munin

=item B<MUNIN_STATEDIR>

Runtime state directory. Default: /run/munin

=item B<MUNIN_PLUGSTATE>

Plugin state directory. Default: /var/lib/munin/plugin-state

=item B<MUNIN_SPOOLDIR>

Spool directory. Default: /var/lib/munin

=item B<MUNIN_CGITMPDIR>

CGI temporary directory. Default: /var/lib/munin/cgi-tmp

=back


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
