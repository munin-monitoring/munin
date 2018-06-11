#!/usr/bin/perl

use strict;
use warnings;

my $output_file = shift;
open my $fh, ">", $output_file or die "Can't open $output_file: $!";

use Module::Build;
my $build           = Module::Build->current;
my $MUNIN_BINDIR    = $build->install_path('MUNIN_BINDIR');
my $MUNIN_CONFDIR   = $build->install_path('MUNIN_CONFDIR');
my $MUNIN_LIBDIR    = $build->install_path('MUNIN_LIBDIR');
my $MUNIN_LOGDIR    = $build->install_path('MUNIN_LOGDIR');
my $MUNIN_HTMLDIR   = $build->install_path('MUNIN_HTMLDIR');
my $MUNIN_CGITMPDIR = $build->install_path('MUNIN_CGITMPDIR');
my $MUNIN_DBDIR     = $build->install_path('MUNIN_DBDIR');
my $MUNIN_PLUGSTATE = $build->install_path('MUNIN_PLUGSTATE');
my $MUNIN_SPOOLDIR  = $build->install_path('MUNIN_SPOOLDIR');
my $MUNIN_STATEDIR  = $build->install_path('MUNIN_STATEDIR');
my $MUNIN_VERSION   = $build->dist_version;

print $fh <<'EOF';
use warnings;
use strict;

# Please note: This file is generated when munin is built.

package Munin::Common::Defaults;

use English qw(-no_match_vars);
use File::Basename qw(dirname);

# This file's package variables are changed during the build process.
EOF

print $fh <<"EOF";
# This variable makes only sense in development environment
my \$COMPONENT_ROOT = dirname(__FILE__) . '/../../..';

our \$DROPDOWNLIMIT = 1;

our \$MUNIN_CONFDIR    = '$MUNIN_CONFDIR';
# our \$MUNIN_BINDIR     = '';
# our \$MUNIN_SBINDIR    = '';
# our \$MUNIN_DOCDIR     = '';
our \$MUNIN_LIBDIR     = '$MUNIN_LIBDIR';
our \$MUNIN_HTMLDIR    = '$MUNIN_HTMLDIR';
# our \$MUNIN_CGIDIR     = '';
our \$MUNIN_CGITMPDIR  = '$MUNIN_CGITMPDIR';
our \$MUNIN_DBDIR      = '$MUNIN_DBDIR';
our \$MUNIN_PLUGSTATE  = '$MUNIN_PLUGSTATE';
our \$MUNIN_SPOOLDIR   = '$MUNIN_SPOOLDIR';
# our \$MUNIN_MANDIR     = '';
our \$MUNIN_LOGDIR     = '$MUNIN_LOGDIR';
our \$MUNIN_STATEDIR   = '$MUNIN_STATEDIR';
our \$MUNIN_USER       = \$^O eq 'MSWin32' ? '' : getpwuid \$EUID;
our \$MUNIN_GROUP      = \$^O eq 'MSWin32' ? '' : getgrgid \$EGID;
our \$MUNIN_PLUGINUSER = \$^O eq 'MSWin32' ? '' : getpwuid \$EUID;
our \$MUNIN_VERSION    = '$MUNIN_VERSION';
our \$MUNIN_PERL       = '/usr/bin/perl';
# our \$MUNIN_PERLLIB    = '';
# our \$MUNIN_GOODSH     = '';
# our \$MUNIN_BASH       = '';
# our \$MUNIN_PYTHON     = '';
# our \$MUNIN_RUBY       = '';
# our \$MUNIN_OSTYPE     = '';
# our \$MUNIN_HOSTNAME   = '';
our \$MUNIN_HASSETR    = '';
EOF

print $fh <<'EOF';
sub get_defaults {
    my ($class) = @_;

    ## no critic

    no strict 'refs';
    my $defaults = {};
    for my $g ( keys %{"Munin::Common::Defaults::"} ) {
        next unless $g =~ /MUNIN_/;
        $defaults->{$g} = ${ *$g{'SCALAR'} };
    }

    ## use critic

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

sub print_as_sed_substitutions {
    my ($class) = @_;

    my %defaults = %{ $class->get_defaults() };
    while ( my ( $k, $v ) = each %defaults ) {
        $k =~ /MUNIN_(.*)/;
        print("s#@@" . $1 . "@@#$v#;");
    }

    return;
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

=item B<print_as_sed_substitutions>

  $class->print_as_sed_substitutions()

Output an expression suitable for "sed". This expression can be used to
substitude placeholders (e.g. "@@SPOOLDIR") in munin's source files
during an installation procedure.

=back

EOF
