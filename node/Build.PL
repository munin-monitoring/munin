use NodeBuilder;

use warnings;
use strict;

my $build = NodeBuilder->new(
    dist_name      => 'Munin::Node',
    dist_version   => '0.0.0',
    dist_author    => 'The Munin Team <fix@example.com>',
    dist_abstract  => 'The Munin Node',
    license        => 'gpl',
    requires       => {},
    build_requires => {},
);
$build->create_build_script;
