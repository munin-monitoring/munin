use strict;
use warnings;

use Test::More tests => 7;

use File::Temp qw( tempfile );
use Munin::Node::Configure::Plugin;

use_ok 'Munin::Node::Configure::History';

my ($fh, $history_file) = tempfile( UNLINK => 1);

print {$fh} <<'EOH';
#
# This file contains a test plugin history.
#

[0.0.0]
[0.9.2]
[0.9.7]

[0.9.8]
df
df_inode
freebsd/df_inode
freebsd/open_files
linux/cpu

[0.9.9pre1]
[0.9.9pre2]
squid_cache
tomcat_volume
[1.3.3]
users
[1.3.4]
  colour_tester
squid_objectsize

EOH

close $fh;


### tests start here ###########################################################

### new
{
    new_ok('Munin::Node::Configure::History' => [
	history_file => '/usr/share/munin/plugins/plugins.history',
    ]);
}
{
    eval { Munin::Node::Configure::History->new(newer => '1.2.3') };
    like($@, qr/history/, 'Error if no history file is specified');
}


### load
{
    # no history file
    my $hist = Munin::Node::Configure::History->new(
	history_file => '/foo/blort',
	newer  => '1.3.4',
    );
    eval { $hist->load };
    ok($@, 'Dies if history file is non-existent');
}
{
    my $hist = Munin::Node::Configure::History->new(
	history_file => '/foo/blort',
    );
    eval { $hist->load };
    unlike($@, qr/./, 'File is not read when --newer was not specified');
}
{
    my $hist = Munin::Node::Configure::History->new(
	history_file => $history_file,
	newer  => '1.3.3',
    );
    $hist->load;

    is_deeply(
    	[ sort keys %{$hist->{valid_plugins}} ],
	[qw/colour_tester squid_objectsize/],
	'Got the right plugins'
    );
}
{
    my $hist = Munin::Node::Configure::History->new(
	history_file => $history_file,
	newer  => '31.3.3',
    );
    eval { $hist->load };
    ok($@, 'Dies with invalid version number.');
}

# TODO: test platform-detection


### too_old



