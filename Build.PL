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

my ( $version, $release_status );
my $plugins_files = {};

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
    license            => 'GPL2',
    configure_requires => { 'Module::Build' => '0.21', },
    requires           => {
        'perl'                   => '5.10.0',
        'DBD::SQLite'            => '1.42',
        'DBI'                    => '1.631',
        'File::Copy::Recursive'  => '0.38',
        'HTML::Template'         => '2.95',
        'HTML::Template::Pro'    => '0',
        'IO::Socket::INET6'      => '2.72',
        'LWP::UserAgent'         => '6.06',
        'List::MoreUtils'        => '0.33',
        'Log::Dispatch'          => '2.41',
        'Net::SNMP'              => 'v6.0.1',
        'Net::SSLeay'            => '1.65',
        'Net::Server::Daemonize' => '0.06',
        'Net::Server::Fork'      => '0',
        'Params::Validate'       => '1.13',
        'RRDs'                   => '1.4008',
        'URI'                    => '1.64',
    },
    PL_files => {
        'lib/Munin.pm.PL'                 => 'lib/Munin.pm',
        'lib/Munin/Common/Defaults.pm.PL' => 'lib/Munin/Common/Defaults.pm',
        'master/munin.conf.PL'            => 'master/munin.conf',
        'node/munin-node.conf.PL'         => 'node/munin-node.conf',
    },
    etc_files => {
        'master/munin.conf'             => 'etc/munin.conf',
        'node/munin-node.conf'          => 'etc/munin-node.conf',
        'master/static/style-new.css'   => 'etc/static/style-new.css',
        'master/static/jquery-1.8.3.js' => 'etc/static/jquery-1.8.3.js',
        'master/static/logo.png'        => 'etc/static/logo.png',
        'master/static/logo-h-neg.png'  => 'etc/static/logo-h-neg.png',
        'master/static/querystring.js'  => 'etc/static/querystring.js',
        'master/static/style.css'       => 'etc/static/style.css',
        'master/static/style-2.1.css'   => 'etc/static/style-2.1.css',
        'master/static/jquery.lazyload-1.9.3.js' =>
            'etc/static/jquery.lazyload-1.9.3.js',
        'master/static/definitions.html'   => 'etc/static/definitions.html',
        'master/static/zoom.js'            => 'etc/static/zoom.js',
        'master/static/favicon.ico'        => 'etc/static/favicon.ico',
        'master/static/logo-h.png'         => 'etc/static/logo-h.png',
        'master/static/formatdate.js'      => 'etc/static/formatdate.js',
        'master/static/placeholder.gif'    => 'etc/static/placeholder.gif',
        'master/static/style-1.2.css'      => 'etc/static/style-1.2.css',
        'master/static/dynazoom.html'      => 'etc/static/dynazoom.html',
        'master/static/style.lazyload.css' => 'etc/static/style.lazyload.css',
        'master/www/partial/path.tmpl' => 'etc/templates/partial/path.tmpl',
        'master/www/partial/logo_navigation.tmpl' =>
            'etc/templates/partial/logo_navigation.tmpl',
        'master/www/partial/footer.tmpl' =>
            'etc/templates/partial/footer.tmpl',
        'master/www/partial/logo_path.tmpl' =>
            'etc/templates/partial/logo_path.tmpl',
        'master/www/partial/navigation.tmpl' =>
            'etc/templates/partial/navigation.tmpl',
        'master/www/partial/head.tmpl' => 'etc/templates/partial/head.tmpl',
        'master/www/partial/bottom_navigation.tmpl' =>
            'etc/templates/partial/bottom_navigation.tmpl',
        'master/www/partial/logo_navigation_comparison.tmpl' =>
            'etc/templates/partial/logo_navigation_comparison.tmpl',
        'master/www/partial/generated_by.tmpl' =>
            'etc/templates/partial/generated_by.tmpl',
        'master/www/partial/logo_navigation_problem.tmpl' =>
            'etc/templates/partial/logo_navigation_problem.tmpl',
        'master/www/munin-domainview.tmpl' =>
            'etc/templates/munin-domainview.tmpl',
        'master/www/munin-problemview.tmpl' =>
            'etc/templates/munin-problemview.tmpl',
        'master/www/munin-serviceview.tmpl' =>
            'etc/templates/munin-serviceview.tmpl',
        'master/www/munin-categoryview.tmpl' =>
            'etc/templates/munin-categoryview.tmpl',
        'master/www/munin-comparison-day.tmpl' =>
            'etc/templates/munin-comparison-day.tmpl',
        'master/www/munin-comparison-week.tmpl' =>
            'etc/templates/munin-comparison-week.tmpl',
        'master/www/munin-comparison-month.tmpl' =>
            'etc/templates/munin-comparison-month.tmpl',
        'master/www/munin-dynazoom.tmpl' =>
            'etc/templates/munin-dynazoom.tmpl',
        'master/www/munin-comparison-year.tmpl' =>
            'etc/templates/munin-comparison-year.tmpl',
        'master/www/munin-overview.tmpl' =>
            'etc/templates/munin-overview.tmpl',
        'master/www/munin-nodeview.tmpl' =>
            'etc/templates/munin-nodeview.tmpl',
        'master/www/munin-htaccess.in' => 'etc/templates/munin-htaccess.in',
    },
    plugins_files => $plugins_files,
    script_files  => [
        qw(
            script/munin-async
            script/munin-asyncd
            script/munin-check
            script/munin-cron
            script/munin-doc
            script/munin-datafile2storable
            script/munin-graph
            script/munin-html
            script/munin-httpd
            script/munin-limits
            script/munin-node
            script/munin-node-configure
            script/munin-run
            script/munin-sched
            script/munin-storable2datafile
            script/munin-update
            )
    ],
    test_requires => {
        'IO::Scalar'          => '0',
        'Test::Differences'   => '0.62',
        'Test::MockModule'    => '0',
        'Test::MockObject'    => '0',
        'Test::Deep'          => '0',
        'Test::LongString'    => '0',
        'File::Slurp'         => '9999.19',
        'File::ReadBackwards' => '0',
        'XML::Parser'         => '0',
        'DBD::Pg'             => '0',
        'Net::DNS'            => '0',
        'Net::IP'             => '0',
        'XML::LibXML'         => '0',
    },

);

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

$build->add_build_element('share');

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

if ( not $build->install_path('var') ) {
    if ( $build->install_base ) {
        $build->install_path( 'var' => $build->install_base . '/var' );
    }
    else {
        $build->install_path( 'var' => '/var' );
    }
}

$build->add_build_element('plugins');

if ( not $build->install_path('plugins') ) {
    $build->install_path(
        'plugins' => $build->install_path('share') . '/plugins' );
}

File::Find::find( { wanted => \&_find_plugins_wanted },
    'plugins/node.d', "plugins/node.d.$^O" );

sub _find_plugins_wanted {
    my ( $dev, $ino, $mode, $nlink, $uid, $gid );

    # Assume all plugins are located on the same directory level
    my $dirlevel = scalar( split( '/', $File::Find::dir ) );
    return unless $dirlevel == 2;

    if ( ( ( $dev, $ino, $mode, $nlink, $uid, $gid ) = lstat($_) ) && -f _ ) {
        my $dst = $File::Find::name;
        my $src = join( '/', 'plugins', $_ );

        $plugins_files->{$dst} = $src;
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
