# vim: sw=4 : ts=4 : et
use warnings;
use strict;

use Test::More tests => 25;
use Test::LongString;

use POSIX ();
use File::Temp qw( tempdir );
use Data::Dumper;
use File::Slurp;

use Munin::Node::SpoolWriter;


# like touch(1).
sub touch { open my $fh, '>>', (shift) or die $!; close $fh }


### new
{
    my $dir = POSIX::getcwd();

    my $writer = new_ok('Munin::Node::SpoolWriter' => [
        spooldir => $dir,
    ], 'spooldir provided to constructor');

    is($writer->{spooldir}, $dir, 'spooldir key is set');
    isa_ok($writer->{spooldirhandle}, 'GLOB', 'spooldirhandle is a glob');
}
{
    eval { Munin::Node::SpoolWriter->new(fnord => 'blort') };
    like($@, qr/./, 'Dies if no spooldir provided');
}


### write
{
    my $dir = tempdir( CLEANUP => 1 );
    my $writer = Munin::Node::SpoolWriter->new(spooldir => $dir);

    $writer->write(1234567890, 'fnord', [
        'graph_title CPU usage',
        'graph_order system user nice idle iowait irq softirq',
        'graph_args --base 1000 -r --lower-limit 0 --upper-limit 200',
        'update_rate 86400',
        'system.label system',
        'system.value 999999'
    ]);

    my $data_file = "$dir/munin-daemon.fnord.1234483200" . "." . Munin::Node::SpoolWriter::DEFAULT_TIME;
    ok( -r $data_file, 'spool file is readable') or last;

    my $data = read_file($data_file);
    is_string($data, <<EOC, 'Data was written correctly');
timestamp 1234567890
multigraph fnord
graph_title CPU usage
graph_order system user nice idle iowait irq softirq
graph_args --base 1000 -r --lower-limit 0 --upper-limit 200
update_rate 86400
system.label system
system.value 999999
EOC


### Now a different set of results
    $writer->write(1234567891, 'fnord', [
        'graph_title CPU usage!',  # this line is different
        'graph_order system user nice idle iowait irq softirq',
        'graph_args --base 1000 -r --lower-limit 0 --upper-limit 200',
        'update_rate 86400',
        'system.label system',
        'system.value 999998'
    ]);

    $data = read_file($data_file);
    is_string($data, <<EOC, 'Spool file was appended to');
timestamp 1234567890
multigraph fnord
graph_title CPU usage
graph_order system user nice idle iowait irq softirq
graph_args --base 1000 -r --lower-limit 0 --upper-limit 200
update_rate 86400
system.label system
system.value 999999
timestamp 1234567891
multigraph fnord
graph_title CPU usage!
graph_order system user nice idle iowait irq softirq
graph_args --base 1000 -r --lower-limit 0 --upper-limit 200
update_rate 86400
system.label system
system.value 999998
EOC

}

# writing different types of value.
# values can also include a timestamp: http://munin-monitoring.org/wiki/protocol-multifetch
{
    my @tests = (
        #  timestamp,               value,              expected
        [ 1234567890,            '999999',              '999999', 'Integer without timestamp'  ],
        [ 1234567890, '2134567890:999999',   '2134567890:999999', 'Integer with timestamp'     ],

        [ 1234567890,            'U',                   'U',      'Unknown without timestamp'  ],
        [ 1234567890, '2134567890:U',        '2134567890:U',      'Unknown with timestamp'     ],

        [ 1234567890,            '-2',                  '-2',     'Negative without timestamp' ],
        [ 1234567890, '2134567890:-2',       '2134567890:-2',     'Negative with timestamp'    ],

        [ 1234567890,            '3.141',               '3.141',  'Float without timestamp'    ],
        [ 1234567890, '2134567890:3.141',    '2134567890:3.141',  'Float with timestamp'       ],

        [ 1234567890,            '1.05e-34',            '1.05e-34', 'E-notation without timestamp'   ],
        [ 1234567890, '2134567890:1.05e-34', '2134567890:1.05e-34', 'E-notation with timestamp'      ],
    );

    foreach (@tests) {
        my ($timestamp, $value, $expected, $msg) = @$_;

        my $dir = tempdir( CLEANUP => 1 );
        my $writer = Munin::Node::SpoolWriter->new(spooldir => $dir);

        $writer->write($timestamp, 'fnord', [
            "system.value $value",
        ]);

        my $data_file = "$dir/munin-daemon.fnord.1234483200" . "." . Munin::Node::SpoolWriter::DEFAULT_TIME;
        unless ( -r $data_file) {
            fail("$msg: File not created");
            next
        }

        my $data = read_file($data_file);
        like($data, qr(^system\.value $expected\n$)m, $msg);
    }
}


# writing multigraph results
{
    my $dir = tempdir( CLEANUP => 1 );
    my $writer = Munin::Node::SpoolWriter->new(spooldir => $dir);

    $writer->write(1234567890, 'fnord-foo', [
        'multigraph fnord',
        'graph_title CPU usage',
        'system.label system',
        'system.value 999999',
        'multigraph fnord.one',
        'graph_title subfnord',
        'subsystem.label subsystem',
        'subsystem.value 123',
    ]);

    my $data_file = "$dir/munin-daemon.fnord_foo.1234483200" . "." . Munin::Node::SpoolWriter::DEFAULT_TIME;
    ok( -r $data_file, 'spool file is readable') or last;

    my $data = read_file($data_file);
    is_string($data, <<EOC, 'Data was written correctly');
timestamp 1234567890
multigraph fnord
graph_title CPU usage
system.label system
system.value 999999
multigraph fnord.one
graph_title subfnord
subsystem.label subsystem
subsystem.value 123
EOC

}


### cleanup
{
    my $dir = tempdir( CLEANUP => 1 );
    my $writer = Munin::Node::SpoolWriter->new(spooldir => $dir);

    # one timestamp before the cutoff, one after.
    my $stale  = time - (Munin::Node::SpoolWriter::MAXIMUM_AGE * Munin::Node::SpoolWriter::DEFAULT_TIME) - 100;
    my $fresh = time - (Munin::Node::SpoolWriter::MAXIMUM_AGE * Munin::Node::SpoolWriter::DEFAULT_TIME) + 100; 
    my $interval = Munin::Node::SpoolWriter::DEFAULT_TIME;

    touch("$dir/munin-daemon.stale.$stale.$interval");
    utime time, $stale, "$dir/munin-daemon.stale.$stale.$interval";
    touch("$dir/munin-daemon.fresh.$fresh.$interval");
    utime time, $fresh, "$dir/munin-daemon.stale.$fresh.$interval";
    touch("$dir/cruft");

    ok( -r "$dir/munin-daemon.stale.$stale.$interval", 'created a stale file');
    ok( -r "$dir/munin-daemon.fresh.$fresh.$interval", 'created a fresh file');
    ok( -r "$dir/cruft",                               'created a cruft file');

    $writer->cleanup;

    ok(! -r "$dir/munin-daemon.stale.$stale.$interval", 'stale file is gone');
    ok(  -r "$dir/munin-daemon.fresh.$fresh.$interval", 'fresh file is still there');
    ok(  -r "$dir/cruft",                               'cruft file is still there');
}

