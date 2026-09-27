#!/usr/bin/perl
# Tests for Munin::Master::Static::HTML
#
# Tests static HTML generation for the whole website.
# Uses SampleDB and SampleRRD for test data.

use strict;
use warnings;

use lib qw(lib t/lib);

use Test::More;
use Test::MockModule;
use File::Temp qw(tempdir);
use File::Path qw(remove_tree);

use Munin::Common::Logger;
use Munin::Master::Config;

# ============================================================================
# SETUP
# ============================================================================

my $config = Munin::Master::Config->instance()->{"config"};
$config->parse_config_from_file("t/config/munin.conf");

my $dbdir = tempdir("html-static-$$-XXXXXX", TMPDIR => 1, CLEANUP => 0);
$config->{dbdir} = $dbdir;
$config->{tmpldir} = "web/templates/";
$config->{staticdir} = "$dbdir/static";

my $site_dir = "$dbdir/_site";
system("mkdir", "-p", $site_dir);
system("mkdir", "-p", "$dbdir/static");

Munin::Common::Logger::configure(
	output => "screen",
	level  => "info",
);

# Generate sample data
require SampleRRD;
require SampleDB;

my $dbfile = "$dbdir/datafile.sqlite";
SampleDB::generate_sample_db($dbfile);
SampleRRD::generate_sample_rrds($dbdir);

# Mock Munin::Master::Update
my $mock_update = Test::MockModule->new("Munin::Master::Update");
$mock_update->redefine("get_param", sub {
	my $param = shift;
	return $config->{$param} if defined $config->{$param};
	return undef;
});

# ============================================================================
# TESTS: Static HTML generation
# ============================================================================

require Munin::Master::Static::HTML;

subtest 'static HTML creates files' => sub {
	Munin::Master::Static::HTML::create(0, $site_dir);

	my @htmls = glob("$site_dir/**/*.html");
	ok(scalar(@htmls) > 0, "produced HTML files (" . scalar(@htmls) . ")");
};

subtest 'overview page generated' => sub {
	ok(-f "$site_dir/index.html", "index.html exists");
	ok(-s "$site_dir/index.html", "index.html has content");
};

subtest 'service pages generated' => sub {
	my @services = glob("$site_dir/**/*cpu*.html");
	ok(scalar(@services) > 0, "cpu service pages exist");
};

subtest 'node pages generated' => sub {
	my @nodes = glob("$site_dir/**/localhost/*.html");
	ok(scalar(@nodes) > 0, "localhost node pages exist");
};

subtest 'group pages generated' => sub {
	my @groups = glob("$site_dir/**/acme.com*.html");
	ok(scalar(@groups) > 0, "acme.com group pages exist");
};

subtest 'category pages generated' => sub {
	# Categories are generated as part of the node/group pages
	my @htmls = glob("$site_dir/**/*.html");
	ok(scalar(@htmls) > 10, "many HTML pages generated");
};

subtest 'problems page generated' => sub {
	ok(-f "$site_dir/problems.html", "problems.html exists");
};

subtest 'dynazoom page generated' => sub {
	ok(-f "$site_dir/dynazoom.html", "dynazoom.html exists");
};

subtest 'HTML files have content' => sub {
	my @htmls = glob("$site_dir/**/*.html");
	my $has_content = 0;
	for my $html (@htmls) {
		if (-s $html > 100) {
			$has_content = 1;
			last;
		}
	}
	ok($has_content, "at least one HTML file has substantial content");
};

subtest 'HTML files contain Munin' => sub {
	my @htmls = glob("$site_dir/**/*.html");
	my $has_munin = 0;
	for my $html (@htmls) {
		open my $fh, '<', $html or next;
		local $/;
		my $content = <$fh>;
		close $fh;
		if ($content && $content =~ /Munin/) {
			$has_munin = 1;
			last;
		}
	}
	ok($has_munin, "HTML files contain Munin branding");
};

# ============================================================================
# CLEANUP
# ============================================================================

remove_tree($dbdir);

print "\n";

done_testing();

1;
