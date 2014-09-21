#!/usr/bin/env perl

use strict;
use warnings;

use Module::Build;

my $build = Module::Build->new(
    module_name   => 'Munin',
    dist_version  => qx{./getversion},
    dist_author   => 'The Munin Project <project@munin-monitoring.org>',
    dist_abstract => 'networked resource monitoring tool with plugins',
    license       => 'gpl2',
    requires      => {
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
    script_files => [
        'script/munin-async',          'script/munin-asyncd',
        'script/munin-cgi-datafile',   'script/munin-cgi-graph',
        'script/munin-cgi-html',       'script/munin-check',
        'script/munin-cron',           'script/munin-datafile2storable',
        'script/munin-graph',          'script/munin-html',
        'script/munin-limits',         'script/munin-node',
        'script/munin-node-configure', 'script/munin-run',
        'script/munin-sched',          'script/munin-storable2datafile',
        'script/munin-update',         'script/munindoc',
    ],
    test_requires => {
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
