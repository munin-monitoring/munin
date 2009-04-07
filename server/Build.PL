use MasterBuilder;

use warnings;
use strict;

my $build = MasterBuilder->new(
    dist_name      => 'Munin::Master',
    dist_version   => '0.0.0',
    dist_author    => 'The Munin Team <fix@example.com>',
    dist_abstract  => 'The Munin Node',
    license        => 'gpl',
    requires       => {},
    build_requires => {},
);
$build->create_build_script;
