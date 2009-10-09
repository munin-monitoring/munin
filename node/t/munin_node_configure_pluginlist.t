use strict;
use warnings;

use Test::More 'no_plan';

use Directory::Scratch;
use Data::Dumper;

use_ok 'Munin::Node::Configure::PluginList';


sub plugin_factory
{
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
    new_ok('Munin::Node::Configure::PluginList' => [
	libdir     => '/usr/share/munin/plugins',
	servicedir => '/etc/munin/plugins/',
    ]);

}


### _valid_files
{
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



### list
{
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
}


