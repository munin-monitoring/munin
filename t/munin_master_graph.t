use strict;
use warnings;

use lib qw(t/lib);

use Test::More;
use Test::Differences;
use Test::Exception;
use Test::MockModule;
use File::Temp qw(tempdir);
use File::Path qw(remove_tree);

require_ok( 'Munin::Master::Static::Graph' );
require_ok( 'Munin::Master::Config' );

my $config = Munin::Master::Config->instance()->{"config"};
$config->parse_config_from_file("t/config/munin.conf");

my $dbdir = tempdir("graph-$$-XXXXXX", TMPDIR => 1, CLEANUP => 0);
$config->{dbdir} = $dbdir;
$config->{tmpldir} = "web/templates/";

system("mkdir", "-p", "$dbdir/_site");

Munin::Common::Logger::configure(
	"output" => "file",
	"file" => "/dev/null",
	"level" => "info",
);

# Generate sample RRDs and DB at test time
require SampleRRD;
require SampleDB;

my $dbfile = "$dbdir/datafile.sqlite";
SampleDB::generate_sample_db($dbfile);
SampleRRD::generate_sample_rrds($dbdir);

my $mock = Test::MockModule->new("Munin::Master::Update");
$mock->redefine("get_param", sub {
	my $param = shift;
	return $config->{$param} if defined $config->{$param};
	return undef;
});

Munin::Master::Static::Graph::create(0, $dbdir . "/_site");

# Verify PNGs were generated
my @pngs = glob("$dbdir/_site/**/*.png");
ok(scalar(@pngs) > 0, "graph create produced PNG files");

# Verify we have year/month/week/day/hour for at least one service
my $has_all = 1;
for my $period (qw(year month week day hour)) {
	my @found = glob("$dbdir/_site/**/*-$period.png");
	if (scalar(@found) == 0) {
		$has_all = 0;
		last;
	}
}
ok($has_all, "graph create produced all time periods");

# cleanup
remove_tree($dbdir);

print "\n";

done_testing();

1;
