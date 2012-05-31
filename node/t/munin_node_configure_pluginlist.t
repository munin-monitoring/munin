use strict;
use warnings;

use Test::More 'no_plan';

use_ok 'Munin::Node::Configure::PluginList';

use constant FOUND_DIRECTORY_SCRATCH => eval { require Directory::Scratch };


sub plugin_factory
{
    die 'Directory::Scratch not available' unless FOUND_DIRECTORY_SCRATCH;

    my $dir = Directory::Scratch->new();
    return sub {
        my ($name, @contents) = @_;
        my $plugin = $dir->touch($name, @contents);
        chmod(0755, $plugin->stringify);
        return Munin::Node::Configure::Plugin->new(
            path => $plugin->stringify,
            name => $plugin->basename,
        );
    };
}


### new
{
    my $pluginlist = new_ok('Munin::Node::Configure::PluginList' => [
        libdir     => '/usr/share/munin/plugins',
        servicedir => '/etc/munin/plugins/',
        families   => [ 'auto' ],
    ]) or next;

    is($pluginlist->{libdir},     '/usr/share/munin/plugins', 'libdir key exists');
    is($pluginlist->{servicedir}, '/etc/munin/plugins/',      'servicedir key exists');

    isa_ok($pluginlist->{library},  'Munin::Node::Service', 'libdir is inflated');
    isa_ok($pluginlist->{services}, 'Munin::Node::Service', 'servicedir is inflated');
}


### _valid_files
=cut
SKIP: {
    skip 'Directory::Scratch not installed' unless FOUND_DIRECTORY_SCRATCH;

    my $libdir = Directory::Scratch->new();
    my $valid = $libdir->touch('memory');
    chmod(0755, $valid->stringify);

    is(sprintf('%04o', $valid->stat->mode & 0777), '0755');

    my $invalid = $libdir->touch('if_');

    is_deeply([ Munin::Node::Configure::PluginList::_valid_files($libdir->base->stringify) ],
       [ { name => $valid->basename, path => $valid->stringify } ],
       'Found the only valid plugin');

    eval { Munin::Node::Configure::PluginList::_valid_files('/foo/blort/zork') };
    ok($@, 'Error on missing directory') or diag($@);
}
=cut


### list and names
=cut
SKIP: {
    skip 'Directory::Scratch not installed' unless FOUND_DIRECTORY_SCRATCH;

    my $plugins = Munin::Node::Configure::PluginList->new(
	libdir     => '/usr/share/munin/plugins',
	servicedir => '/etc/munin/plugins',
    );

    my $gen_plugin = plugin_factory;

    my @plugins = qw/memory if_ cpu/;

    for my $plugin (@plugins) {
	$plugins->{plugins}{$plugin} = $gen_plugin->($plugin);
    }

    is_deeply([ map { $_->{name} } $plugins->list ], [ sort @plugins ],
	      'List is sorted');

    is_deeply([ sort $plugins->names ], [ sort @plugins ], 'All plugin names are returned');
}
=cut

# vim: sw=4 : ts=4 : et
