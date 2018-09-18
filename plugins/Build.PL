BEGIN { push @INC, '.'; }
use PluginsBuilder;

use warnings;
use strict;

my $build = PluginsBuilder->new(
    dist_name      => 'Munin::Plugins',
    dist_version   => '0.0.0',
    dist_author    => 'The Munin Team <fix@example.com>',
    dist_abstract  => 'The Munin Node',
    license        => 'gpl',
    requires       => {
        perl            => '5',
    },
    build_requires => {},
    recommends     => {
        'Net::SNMP'   => 0,
    },
);
$build->create_build_script;
