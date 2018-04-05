#!/usr/bin/env perl

=head1 NAME

Build - Build, test and install Munin

=head1 SYNOPSIS

  perl Build.PL [options]
  ./Build test
  ./Build install

=head1 DESCRIPTION

Installs Munin and its components, using Module::Build. Some files are generated using templates.

=head1 OPTIONS

Note: options are "sticky". Options set at C<perl Build.PL> are re-used for calls to C<./Build>
later.

=over

=item --debug

Enables debugging

=item --installpaths, --install_base, --install_path

Configures how munin is installed.

=back

=head1 EXAMPLES

=over

=item Set base install location

Handled by Module::Build standard.  Overall options

* C<--installpaths site>, installs under /usr/local (this is the default)

* C<--installpaths vendor>, installs under /usr (used for packaging)

* C<--installbase /opt/munin>, installs under the named directory. You are responsible for making
  sure the perl library path is set.

=item Override etcdir

Override install path with C<--install_path etc=/path/to/etc>

=item Override vardir

Override install path with C<--install_path var=/path/to/var>

=item Override sharedir

Override install path with C<--install_path share=/path/to/share>

Note: This affects plugins. Available plugins are installed to C</path/to/share/plugins/>, and
C<>munin-node-configure> will look in this directory.

=back

=head1 PLUGINS

Plugins are installed from:

* plugins/node.d/ - Generic plugins for common applications, which should work on all platforms.

* plugins/node.d.$^O/ - Specific plugins for the platform where Munin is built. (for the value of
  $^O for your platform, see http://perldoc.perl.org/perlport.html)

=cut

use strict;
use warnings;

use Module::Build;
use File::Find;
use Config;

my ( $version, $release_status );
my $plugins_files = {};
my $web_files     = {};

$version = qx{./getversion};
chomp $version;

if ( $version =~ m/^\d+\.\d+\.\d+$/ ) {
    $release_status = 'stable';
}
else {
    $release_status = 'unstable';
}

my $build = Module::Build->new(
    module_name        => 'Munin',
    dist_version       => $version,
    release_status     => $release_status,
    dist_author        => 'The Munin Project <project@munin-monitoring.org>',
    dist_abstract      => 'networked resource monitoring tool with plugins',
    license            => 'gpl_2',
    configure_requires => { 'Module::Build' => '0.21', },
    requires           => {
        'perl'                   => '5.10.0',
        'DBD::SQLite'            => '1.35',
        'DBI'                    => '1.616',
        'HTML::Template::Pro'    => '0',
        'HTTP::Server::Simple::CGI::PreFork'    => '0',
        'CGI::Cookie'            => '0',
        'IO::Socket::INET6'      => '2.69',
        'JSON'                   => '0',
        'LWP::UserAgent'         => '6.03',
        'List::Util'             => '0',
        'List::MoreUtils'        => '0.33',
        'Log::Dispatch'          => '2.29',
        'Net::SNMP'              => '6.0.1',
        'Net::SSLeay'            => '1.42',
        'Net::Server::Daemonize' => '0.06',
        'Net::Server::Fork'      => '0',
        'Parallel::ForkManager'  => '0',
        'Params::Validate'       => '1.08',
        'Alien::RRDtool'         => '0',
        'URI'                    => '1.59',
        'XML::Dumper'            => '0',
    },
    PL_files => {
        'etc/munin-node.conf.PL'          => 'etc/munin-node.conf.sample',
        'etc/munin.conf.PL'               => 'etc/munin.conf.sample',
        'lib/Munin.pm.PL'                 => 'lib/Munin.pm',
        'lib/Munin/Common/Defaults.pm.PL' => 'lib/Munin/Common/Defaults.pm',
        'script/munin-cron.PL'            => 'script/munin-cron',
    },
    etc_files => {
        'etc/munin.conf.sample'      => 'etc/munin.conf.sample',
        'etc/munin-node.conf.sample' => 'etc/munin-node.conf.sample',
    },
    plugins_files => $plugins_files,
    web_files     => $web_files,
    script_files  => [
        qw(
            script/munin-async
            script/munin-asyncd
            script/munin-cron
            script/munin-doc
            script/munin-httpd
            script/munin-limits
            script/munin-node
            script/munin-node-configure
            script/munin-run
            script/munin-update
            )
    ],
    test_requires => {
        'IO::Scalar'          => '0',
        'Test::Class'         => '0',
        'Test::Differences'   => '0.62',
        'Test::MockModule'    => '0',
        'Test::MockObject'    => '0',
        'Test::Deep'          => '0',
        'Test::LongString'    => '0',
        'Test::Perl::Critic'  => '0',
        'File::Slurp'         => '9999.19',
        'File::ReadBackwards' => '0',
        'XML::Parser'         => '0',
        'DBD::Pg'             => '0',
        'Net::DNS'            => '0',
        'Net::IP'             => '0',
        'XML::LibXML'         => '0',
    },

);

##############################
## Build element "etc"
#
# Contains generated configuration files

$build->add_build_element('etc');

if ( not $build->install_path('etc') ) {
    if ( $build->install_base ) {
        $build->install_path( 'etc' => $build->install_base . '/etc' );
    }
    elsif ( $build->installdirs eq 'site' ) {
        $build->install_path( 'etc' => '/usr/local/etc/munin' );
    }
    elsif ( $build->installdirs eq 'vendor' ) {
        $build->install_path( 'etc' => '/etc/munin' );
    }
}

##############################
## Path "share"
#
# Used as root for other parts of munin, like "plugins"

if ( not $build->install_path('share') ) {
    if ( $build->install_base ) {
        $build->install_path( 'share' => $build->install_base . '/share' );
    }
    elsif ( $build->installdirs eq 'site' ) {
        $build->install_path( 'share' => '/usr/local/share/munin' );
    }
    elsif ( $build->installdirs eq 'vendor' ) {
        $build->install_path( 'share' => '/usr/share/munin' );
    }
}

##############################
## Path "var"

if ( not $build->install_path('var') ) {
    if ( $build->install_base ) {
        $build->install_path( 'var' => $build->install_base . '/var' );
    }
    else {
        $build->install_path( 'var' => '/var' );
    }
}

##############################
## Build element "plugins"
#
# Contains munin plugins.  Installed under the "share" path by default.

$build->add_build_element('plugins');

if ( not $build->install_path('plugins') ) {
    $build->install_path(
        'plugins' => $build->install_path('share') . '/plugins' );
}

$plugins_files->{'plugins/plugin.sh'} = 'plugins/plugin.sh';

File::Find::find( { wanted => \&_find_plugins_wanted },
    'plugins/node.d', "plugins/node.d.$^O" );

sub _find_plugins_wanted {

    # Assume all plugins are located on the same directory level
    my $dirlevel = scalar( split( '/', $File::Find::dir ) );
    return unless $dirlevel == 2;

    if ( ( lstat($_) ) && -f _ && -x _ ) {
        my $src = $File::Find::name;
        my $dst = join( '/', 'plugins', $_ );

        $plugins_files->{$src} = $dst;
    }
}

##############################
## Build element "web"
#
# Contains static files and templates. Installed under the "etc" path by default.

$build->add_build_element('web');

if ( not $build->install_path('web') ) {
    $build->install_path( 'web' => $build->install_path('etc') );
}

File::Find::find( { wanted => \&_find_web_wanted }, 'web' );

sub _find_web_wanted {
    if ( lstat && -f _ ) {
        my $file = $File::Find::name;
        $web_files->{$file} = $file;
    }
}

##############################
# Add generated variables to be used from .PL files

# sharedir (aka libdir)
$build->install_path( 'MUNIN_SHAREDIR' => $build->install_path('share') );

# etc
$build->install_path( 'MUNIN_CONFDIR' => $build->install_path('etc') );

# runstate

# var
if ( $build->install_base ) {
    $build->install_path(
        'MUNIN_BINDIR' => $build->install_base . '/bin' );
    $build->install_path(
        'MUNIN_RUNDIR' => $build->install_path('var') . '/run' );
    $build->install_path(
        'MUNIN_LOGDIR' => $build->install_path('var') . '/log' );
    $build->install_path(
        'MUNIN_HTMLDIR' => $build->install_path('var') . '/www' );
    $build->install_path(
        'MUNIN_DBDIR' => $build->install_path('var') . '/lib' );
    $build->install_path(
        'MUNIN_CGITMPDIR' => $build->install_path('var') . '/cache' );
    $build->install_path(
        'MUNIN_SPOOLDIR' => $build->install_path('var') . '/spool' );
    $build->install_path(
        'MUNIN_PLUGSTATE' => $build->install_path('var') . '/plugin-state' );
}
else {
    if ($build->installdirs eq 'site') {
        $build->install_path( 'MUNIN_BINDIR' => $Config{installsitebin} );
    }
    else {
        $build->install_path( 'MUNIN_BINDIR' => $Config{installvendorbin} );
    }
    $build->install_path(
        'MUNIN_RUNDIR' => $build->install_path('var') . '/run/munin' );
    $build->install_path(
        'MUNIN_LOGDIR' => $build->install_path('var') . '/log/munin' );
    $build->install_path(
        'MUNIN_HTMLDIR' => $build->install_path('var') . '/www/munin' );
    $build->install_path(
        'MUNIN_DBDIR' => $build->install_path('var') . '/lib/munin' );
    $build->install_path(
        'MUNIN_CGITMPDIR' => $build->install_path('var') . '/cache/munin' );
    $build->install_path(
        'MUNIN_SPOOLDIR' => $build->install_path('var') . '/spool/munin' );
    $build->install_path( 'MUNIN_PLUGSTATE' => $build->install_path('var')
            . '/lib/munin-node/plugin-state' );
}

# Aliases, kept for as long as code uses these
$build->install_path(
    'MUNIN_STATEDIR' => $build->install_path('MUNIN_RUNDIR') );
$build->install_path(
    'MUNIN_LIBDIR' => $build->install_path('MUNIN_SHAREDIR') );

$build->dispatch('manifest');
$build->dispatch('distmeta');
$build->create_build_script;

if ( $build->debug ) {
    use Data::Dumper;
    print Dumper $build->install_path();
}
