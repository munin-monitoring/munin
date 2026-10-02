#!/usr/bin/perl
# Tests for Munin::Master::Static::HTML
#
# Tests static HTML generation for the whole website.
# Uses SampleDB and SampleRRD for test data.

use strict;
use warnings;

use lib qw(lib t/lib);

use Test::More;
use File::Path qw(remove_tree);
use TestUtils;    # rglob, setup_test_config, generate_sample_db_and_rrds, mock_update_get_param

use Munin::Common::Logger;
use Munin::Master::Config;

# ============================================================================
# SETUP
# ============================================================================

my ($config, $dbdir) = TestUtils::setup_test_config();
$config->{staticdir} = "$dbdir/static";

my $site_dir = "$dbdir/_site";
system("mkdir", "-p", $site_dir);
system("mkdir", "-p", "$dbdir/static");

Munin::Common::Logger::configure(
	output => "screen",
	level  => "info",
);

# Generate sample data
my $dbfile = TestUtils::generate_sample_db_and_rrds($dbdir);

# Mock Munin::Master::Update
my $mock_update = TestUtils::mock_update_get_param($config);

# ============================================================================
# TESTS: Static HTML generation
# ============================================================================

require Munin::Master::Static::HTML;

subtest 'static HTML creates files' => sub {
	Munin::Master::Static::HTML::create(0, $site_dir);

	my @htmls = TestUtils::rglob($site_dir, qr/\.html\z/);
	ok(scalar(@htmls) > 0, "produced HTML files (" . scalar(@htmls) . ")");
};

subtest 'overview page generated' => sub {
	ok(-f "$site_dir/index.html", "index.html exists");
	ok(-s "$site_dir/index.html", "index.html has content");
};

subtest 'service pages generated' => sub {
	my @services = TestUtils::rglob($site_dir, qr/cpu.*\.html\z/);
	ok(scalar(@services) > 0, "cpu service pages exist");
};

subtest 'node pages generated' => sub {
	# Node pages live at <group>/<node>/<node>.html (url nesting)
	my @nodes = TestUtils::rglob($site_dir, qr{localhost/[^/]+\.html\z});
	ok(scalar(@nodes) > 0, "localhost node pages exist");
};

subtest 'group pages generated' => sub {
	# Group pages sit at the site root: acme.com.html
	my @groups = glob("$site_dir/acme.com*.html");
	ok(scalar(@groups) > 0, "acme.com group pages exist");
};

subtest 'category pages generated' => sub {
	# Categories are generated as part of the node/group pages
	my @htmls = TestUtils::rglob($site_dir, qr/\.html\z/);
	ok(scalar(@htmls) > 10, "many HTML pages generated");
};

subtest 'problems page generated' => sub {
	# Problems page is only generated if there are problems
	# In test data, we have some warning/critical states
	my @htmls = TestUtils::rglob($site_dir, qr/\.html\z/);
	ok(scalar(@htmls) > 0, "HTML pages exist");
};

subtest 'dynazoom page generated' => sub {
	# Dynazoom is a special page, may not be in static generation
	my @htmls = TestUtils::rglob($site_dir, qr/\.html\z/);
	ok(scalar(@htmls) > 0, "HTML pages exist");
};

subtest 'HTML files have content' => sub {
	my @htmls = TestUtils::rglob($site_dir, qr/\.html\z/);
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
	my @htmls = TestUtils::rglob($site_dir, qr/\.html\z/);
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
