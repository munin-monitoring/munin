use Module::Build;

my $version = `../getversion`;
chomp($version);

my $build = Module::Build->new(
    dist_name      => 'Munin::Common',
    dist_version   => $version,
    dist_author    => 'The Munin Team <munin-users@lists.sourceforge.net>',
    dist_abstract  => 'Shared libraries for Munin Node and Munin Master',
    license        => 'gpl',
    requires       => {},
    build_requires => {},
    recommends     => {
        'Net::SSLeay' => 0,
    },

);
$build->create_build_script;
