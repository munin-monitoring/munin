# vim: sw=4 : ts=4 : et
use warnings;
use strict;

use Test::More tests => 18;
use Test::LongString;

use POSIX ();
use File::Temp qw( tempdir );
use Data::Dumper;
use File::Slurp;

use Munin::Node::SpoolReader;
use Munin::Node::SpoolWriter;


### new
{
    my $dir = POSIX::getcwd();

    my $writer = new_ok('Munin::Node::SpoolReader' => [
        spooldir => $dir,
    ], 'spooldir provided to constructor');

    is($writer->{spooldir}, $dir, 'spooldir key is set');
    isa_ok($writer->{spooldirhandle}, 'GLOB', 'spooldirhandle is a glob');
}
{
    eval { Munin::Node::SpoolReader->new(fnord => 'blort') };
    like($@, qr/./, 'Dies if no spooldir provided');
}


### fetch
{
    my $dir = tempdir(CLEANUP => 1);
    my $writer = Munin::Node::SpoolWriter->new(spooldir => $dir);
    my $reader = Munin::Node::SpoolReader->new(spooldir => $dir);

    # write some data
    $writer->write(1234567890, 'fnord-foo', [
        'graph_title CPU usage',
        'system.label system',
        'system.value 1',
    ]);

    $writer->write(1234567900, 'fnord-foo', [
        'graph_title CPU usage',
        'system.label system',
        'system.value 2',
    ]);

    $writer->write(1234567910, 'fnord-foo', [
        'graph_title CPU usage',
        'system.label system',
        'system.value 3',
    ]);

    is_string($reader->fetch(1234567899), <<EOS, 'Fetched data since the write');
multigraph fnord_foo
graph_title CPU usage
system.label system
system.value 1234567900:2
multigraph fnord_foo
graph_title CPU usage
system.label system
system.value 1234567910:3
EOS

    is_string($reader->fetch(1234567900), <<EOS, 'Start timestamp is not inclusive');
multigraph fnord_foo
graph_title CPU usage
system.label system
system.value 1234567910:3
EOS

    is_string($reader->fetch(1), <<EOS, 'Timestamp predates all result: all results are returned');
multigraph fnord_foo
graph_title CPU usage
system.label system
system.value 1234567890:1
multigraph fnord_foo
graph_title CPU usage
system.label system
system.value 1234567900:2
multigraph fnord_foo
graph_title CPU usage
system.label system
system.value 1234567910:3
EOS

    is_string($reader->fetch(1234567999), '', 'Timestamp postdates the last result: empty string');
}
{
    my $dir = tempdir(CLEANUP => 1);
    my $writer = Munin::Node::SpoolWriter->new(spooldir => $dir);
    my $reader = Munin::Node::SpoolReader->new(spooldir => $dir);

    # write some data
    $writer->write(1234567890, 'fnord-foo', [
        'graph_title CPU usage',
        'system.label system',
        '',
        'system.value 1',
        '',
    ]);

    is_string($reader->fetch(1), <<EOS, 'Blank lines are ignored');
multigraph fnord_foo
graph_title CPU usage
system.label system
system.value 1234567890:1
EOS

}
{
    my $dir = tempdir(CLEANUP => 1);
    my $writer = Munin::Node::SpoolWriter->new(spooldir => $dir);
    my $reader = Munin::Node::SpoolReader->new(spooldir => $dir);

    # write results for two different plugins
    $writer->write(1234567890, 'fnord-foo', [
        'graph_title CPU usage',
        'system.label system',
        'system.value 3',
    ]);

    $writer->write(1234567910, 'blort', [
        'graph_title Memory usage',
        'slab.label slab',
        'slab.value 123',
    ]);

    ok(my $fetched = $reader->fetch(1234567800), 'Several services to fetch');

    my $f1 = <<EOT;
multigraph fnord_foo
graph_title CPU usage
system.label system
system.value 1234567890:3
EOT
    my $f2 = <<EOT;
multigraph blort
graph_title Memory usage
slab.label slab
slab.value 1234567910:123
EOT
    like($fetched, qr(\A$f1$f2|$f2$f1\Z)m, 'Got results for both services, in either order, and nothing else');


    is($reader->fetch(1234567900), <<EOS, 'Several plugins to fetch, but only one is recent enough');
multigraph blort
graph_title Memory usage
slab.label slab
slab.value 1234567910:123
EOS

}
{
    my $dir = tempdir(CLEANUP => 1);
    my $writer = Munin::Node::SpoolWriter->new(spooldir => $dir);
    my $reader = Munin::Node::SpoolReader->new(spooldir => $dir);

    # write two sets of results, with a slightly different config
    $writer->write(1234567890, 'fnord-foo', [
        'graph_title CPU usage',
        'system.label system',
        'system.value 3',
    ]);

    $writer->write(1234567990, 'fnord-foo', [
        'graph_title CPU usage!',  # this line has changed
        'system.label system',
        'system.value 4',
    ]);

    ok(my $fetched = $reader->fetch(1234567800), 'Several sets of results to fetch');

    my $f1 = <<EOT;
multigraph fnord_foo
graph_title CPU usage
system.label system
system.value 1234567890:3
EOT
    my $f2 = <<EOT;
multigraph fnord_foo
graph_title CPU usage!
system.label system
system.value 1234567990:4
EOT
    like($fetched, qr(\A$f1$f2|$f2$f1\Z)m, 'Got results for both services, in either order, and nothing else');
}


### _get_spooled_plugins
### list
{
    my $dir = tempdir(CLEANUP => 1);
    my $writer = Munin::Node::SpoolWriter->new(spooldir => $dir);
    my $reader = Munin::Node::SpoolReader->new(spooldir => $dir);

    is_deeply([ sort $reader->_get_spooled_plugins ], [], 'No spooled plugins to list');
    is($reader->list, "\n", 'No spooled plugins to list');

    # write "results" for several plugins
    $writer->write(1234567890, 'fnord-foo', [
        'graph_title CPU usage',
        'system.label system',
        'system.value 1',
    ]);
    $writer->write(1234567890, 'floop', [
        'graph_title Memory usage',
        'system.label system',
        'system.value 3.14',
    ]);
    $writer->write(1234567890, 'blort', [
        'graph_title Flux capacitance',
        'system.label system',
        'system.value -4',
    ]);
    $writer->write(1334567890, 'blort', [
        'graph_title Flux capacitance',
        'system.label system',
        'system.value -4',
    ]);

    open my $cruft, '>', "$dir/cruft" or die "Unable to create cruft file: $!";
    print $cruft "rubbish\n";
    close $cruft;

    is_deeply([ sort $reader->_get_spooled_plugins ], [ sort qw( fnord_foo floop blort ) ], 'Retrieved list of spooled plugins');
    is($reader->list, "blort floop fnord_foo\n", 'Retrieved stringified list of spooled plugins');
}

