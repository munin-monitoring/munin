use strict;
use warnings;

use lib qw(lib t/lib);

use Test::More;
use Test::MockModule;
use TestUtils;    # rglob, setup_test_config, generate_sample_db_and_rrds, mock_update_get_param

require_ok( 'Munin::Master::Static::Graph' );
require_ok( 'Munin::Master::Config' );

my ($config, $dbdir) = TestUtils::setup_test_config();

system("mkdir", "-p", "$dbdir/_site");

Munin::Common::Logger::configure(
	"output" => "screen",
	"level" => "info",
);

# Generate sample RRDs and DB at test time
my $dbfile = TestUtils::generate_sample_db_and_rrds($dbdir);

my $mock_update = TestUtils::mock_update_get_param($config);

# Mock RRDs::graph: log every call and write a fixed PNG instead of
# rendering. The DB is synthetic and deterministic, so the command lines
# are fully determined by the fixture -- but rendering 25 services x 5
# periods with real rrdtool is the entire cost of this test. RRDs::error
# is mocked alongside: RRDs_graph() consults it after every graph call,
# and without the paired mock the real library's error state would leak
# into the mocked path. RRDs::last stays real (reads RRD headers only,
# and validates that the SampleRRD files exist).
my $FIXED_PNG = pack("H*",
	"89504e470d0a1a0a0000000d4948445200000001000000010806000000"
	. "1f15c4890000000d4944415478da63f8ffff3f03000501012b87c1a8"
	. "0000000049454e44ae426082");

my @graph_calls;    # one arrayref per RRDs::graph invocation (args after outfile)
my $mock_rrds = Test::MockModule->new("RRDs");
$mock_rrds->redefine("graph", sub {
	my @args = @_;
	my $outfile = shift @args;
	push @graph_calls, [@args];
	open my $fh, ">", $outfile or die "cannot write $outfile: $!";
	binmode $fh;
	print $fh $FIXED_PNG;
	close $fh;
	return (1, 1);
});
$mock_rrds->redefine("error", sub { return undef; });

Munin::Master::Static::Graph::create(0, $dbdir . "/_site");

# Verify PNGs were produced (verifies the STDOUT-redirect plumbing,
# not rrdtool -- the content is the fixed PNG from the mock)
my @pngs = TestUtils::rglob("$dbdir/_site", qr/\.png\z/);
ok(scalar(@pngs) > 0, "graph create produced PNG files");

# Verify we have year/month/week/day/hour for at least one service
my $has_all = 1;
for my $period (qw(year month week day hour)) {
	my @found = TestUtils::rglob("$dbdir/_site", qr/-\Q$period\E\.png\z/);
	if (scalar(@found) == 0) {
		$has_all = 0;
		last;
	}
}
ok($has_all, "graph create produced all time periods");

# Every rendered file carries the mock's fixed PNG, not empty output
my $nonempty = 0;
for my $png (@pngs) {
	$nonempty++ if -s $png;
}
is($nonempty, scalar(@pngs), "every produced PNG has content");

# The fixture has 25 service paths (5 hosts x 5 services) x 5 time
# periods. The call count pins the render loop: one RRDs::graph per
# output file, no more (a regression that re-renders or skips would
# show up here without any rrdtool cost).
is(scalar(@graph_calls), 125, "RRDs::graph called once per service path per period");

print "\n";

done_testing();

1;
