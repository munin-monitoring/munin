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

$build->create_build_script;
$build->dispatch('distmeta');
$build->dispatch('manifest');
