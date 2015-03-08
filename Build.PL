#!/usr/bin/env perl

use strict;
use warnings;

use Module::Build;

my ( $version, $release_status );

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
        'master/munin.conf'             => 'conf/munin.conf',
        'node/munin-node.conf'          => 'conf/munin-node.conf',
        'master/static/style-new.css'   => 'conf/static/style-new.css',
        'master/static/jquery-1.8.3.js' => 'conf/static/jquery-1.8.3.js',
        'master/static/logo.png'        => 'conf/static/logo.png',
        'master/static/logo-h-neg.png'  => 'conf/static/logo-h-neg.png',
        'master/static/querystring.js'  => 'conf/static/querystring.js',
        'master/static/style.css'       => 'conf/static/style.css',
        'master/static/style-2.1.css'   => 'conf/static/style-2.1.css',
        'master/static/jquery.lazyload-1.9.3.js' =>
            'conf/static/jquery.lazyload-1.9.3.js',
        'master/static/definitions.html' => 'conf/static/definitions.html',
        'master/static/zoom.js'          => 'conf/static/zoom.js',
        'master/static/favicon.ico'      => 'conf/static/favicon.ico',
        'master/static/logo-h.png'       => 'conf/static/logo-h.png',
        'master/static/formatdate.js'    => 'conf/static/formatdate.js',
        'master/static/placeholder.gif'  => 'conf/static/placeholder.gif',
        'master/static/style-1.2.css'    => 'conf/static/style-1.2.css',
        'master/static/dynazoom.html'    => 'conf/static/dynazoom.html',
        'master/static/style.lazyload.css' =>
            'conf/static/style.lazyload.css',
        'master/www/partial/path.tmpl' => 'conf/templates/partial/path.tmpl',
        'master/www/partial/logo_navigation.tmpl' =>
            'conf/templates/partial/logo_navigation.tmpl',
        'master/www/partial/footer.tmpl' =>
            'conf/templates/partial/footer.tmpl',
        'master/www/partial/logo_path.tmpl' =>
            'conf/templates/partial/logo_path.tmpl',
        'master/www/partial/navigation.tmpl' =>
            'conf/templates/partial/navigation.tmpl',
        'master/www/partial/head.tmpl' => 'conf/templates/partial/head.tmpl',
        'master/www/partial/bottom_navigation.tmpl' =>
            'conf/templates/partial/bottom_navigation.tmpl',
        'master/www/partial/logo_navigation_comparison.tmpl' =>
            'conf/templates/partial/logo_navigation_comparison.tmpl',
        'master/www/partial/generated_by.tmpl' =>
            'conf/templates/partial/generated_by.tmpl',
        'master/www/partial/logo_navigation_problem.tmpl' =>
            'conf/templates/partial/logo_navigation_problem.tmpl',
        'master/www/munin-domainview.tmpl' =>
            'conf/templates/munin-domainview.tmpl',
        'master/www/munin-problemview.tmpl' =>
            'conf/templates/munin-problemview.tmpl',
        'master/www/munin-serviceview.tmpl' =>
            'conf/templates/munin-serviceview.tmpl',
        'master/www/munin-categoryview.tmpl' =>
            'conf/templates/munin-categoryview.tmpl',
        'master/www/munin-comparison-day.tmpl' =>
            'conf/templates/munin-comparison-day.tmpl',
        'master/www/munin-comparison-week.tmpl' =>
            'conf/templates/munin-comparison-week.tmpl',
        'master/www/munin-comparison-month.tmpl' =>
            'conf/templates/munin-comparison-month.tmpl',
        'master/www/munin-dynazoom.tmpl' =>
            'conf/templates/munin-dynazoom.tmpl',
        'master/www/munin-comparison-year.tmpl' =>
            'conf/templates/munin-comparison-year.tmpl',
        'master/www/munin-overview.tmpl' =>
            'conf/templates/munin-overview.tmpl',
        'master/www/munin-nodeview.tmpl' =>
            'conf/templates/munin-nodeview.tmpl',
        'master/www/munin-htaccess.in' => 'conf/templates/munin-htaccess.in',
    },
    script_files => [
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
        'IO::Scalar'        => '0',
        'Test::Differences' => '0.62',
        'Test::MockModule'  => '0',
        'Test::MockObject'  => '0',
        'Test::Deep'        => '0',
        'Test::LongString'  => '0',
        'File::Slurp'       => '9999.19',
    },

);

$build->add_build_element('etc');

if ( not $build->install_path('etc') ) {
    if ( $build->install_base ) {
        $build->install_path(
            'etc' => join( '/', $build->install_base, 'etc' ) );
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
        $build->install_path(
            'share' => join( '/', $build->install_base, 'share' ) );
    }
    elsif ( $build->installdirs eq 'site' ) {
        $build->install_path( 'share' => '/usr/local/share/munin' );
    }
    elsif ( $build->installdirs eq 'vendor' ) {
        $build->install_path( 'share' => '/usr/share/munin' );
    }
}

# Add generated variables to be used from .PL files

# sharedir (aka libdir)
$build->install_path( 'MUNIN_SHAREDIR' => $build->install_path('share') );
$build->install_path( 'MUNIN_LIBDIR'   => $build->install_path('share') );

# conf
$build->install_path( 'MUNIN_CONFDIR' => $build->install_path('etc') );

# runstate
$build->install_path( 'MUNIN_RUNDIR'   => '/run/munin' );
$build->install_path( 'MUNIN_STATEDIR' => '/run/munin' );
$build->install_path(
    'MUNIN_PLUGSTATE' => '/var/lib/munin-node/plugin-state' );

# var
$build->install_path( 'MUNIN_LOGDIR'    => '/var/log/munin' );
$build->install_path( 'MUNIN_HTMLDIR'   => '/var/www/munin' );
$build->install_path( 'MUNIN_DBDIR'     => '/var/lib/munin' );
$build->install_path( 'MUNIN_CGITMPDIR' => '/var/cache/munin' );
$build->install_path( 'MUNIN_SPOOLDIR'  => '/var/spool/munin' );

$build->dispatch('manifest');
$build->dispatch('distmeta');
$build->create_build_script;

if ( $build->debug ) {
    use Data::Dumper;
    print Dumper $build->install_path();
}
