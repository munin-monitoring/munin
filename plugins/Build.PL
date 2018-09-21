use PluginsBuilder;

use warnings;
use strict;

my $version = `../getversion`;
chomp($version);

my $build = PluginsBuilder->new(
    dist_name      => 'Munin::Plugins',
    dist_version   => $version,
    dist_author    => 'The Munin Team <munin-users@lists.sourceforge.net>',
    dist_abstract  => 'The Munin Plugin module',
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
