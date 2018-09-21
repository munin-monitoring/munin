use NodeBuilder;

use warnings;
use strict;

my $version = `../getversion`;
chomp($version);

my $build = NodeBuilder->new(
    dist_name      => 'Munin::Node',
    dist_version   => $version,
    dist_author    => 'The Munin Team <munin-users@lists.sourceforge.net>',
    dist_abstract  => 'The Munin Node',
    license        => 'gpl',
    requires       => {
        perl            => '5',
        'Net::Server'   => 0,
        'Time::HiRes'   => 0,
        #'Munin::Common' => 0,
    },
    build_requires => {},
    recommends     => {
        #'Net::SSLeay' => 0, In Munin::Common?
        'Net::SNMP'   => 0,
    },
);
$build->create_build_script;


