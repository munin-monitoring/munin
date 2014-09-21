#!/usr/bin/env perl

use strict;
use warnings;

use Module::Build;
my $build = Module::Build->new(
    module_name  => 'Munin',
    dist_version => qx{./getversion},
    dist_author  => 'The Munin Project <project@munin-monitoring.org>',
    dist_abstract =>
        'Munin is a networked resource monitoring tool that can help analyze '
        . 'resource trends and "what just happened to kill our performance?" '
        . 'problems. It is designed to be very plug and play. A default '
        . 'installation provides a lot of graphs with almost no work.',
    license  => 'gpl2',
    requires => { 'perl' => '5.10.0', },
);

$build->create_build_script;
