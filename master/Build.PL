use MasterBuilder;

use warnings;
use strict;

my $build = MasterBuilder->new(
    dist_name      => 'Munin::Master',
    dist_version   => '0.0.0',
    dist_author    => 'The Munin Team <fix@example.com>',
    dist_abstract  => 'The Munin Master',
    license        => 'gpl',
    requires       => {
        perl => '5',
        'Digest::MD5'               => 0,
        'HTML::Template'            => 0,
        'Log::Dispatch'             => 0,
        'Storable'                  => 0,
        'Text::Balanced'            => 0,
        'Time::HiRes'               => 0,
        'Getopt::Long'              => 0,
        #'Munin::Common' => 0,
    },
    build_requires => {},
    recommends     => {
        #'Net::SSLeay' => 0, In Munin::Common?
    },
);
$build->create_build_script;
