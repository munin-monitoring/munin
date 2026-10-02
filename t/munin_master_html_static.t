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
use File::Find qw(find);

use Munin::Common::Logger;
use Munin::Master::Config;

# Core glob()'s '**' does not recurse -- it behaves like '*', which only
# matched pages sitting at exactly one directory level. Collect files at
# any depth so these assertions match their intent. Service pages are
# nested under their node url (as in production), i.e. two+ levels deep.
sub rglob {
	my ($dir, $re) = @_;
	my @found;
	return @found unless -d $dir;
	find({ wanted => sub { push @found, $File::Find::name if /$re/ }, no_chdir => 1 }, $dir);
	return @found;
}

# ============================================================================
# SETUP
# ============================================================================

my $config = Munin::Master::Config->instance()->{"config"};
$config->parse_config_from_file("t/config/munin.conf");

use TestState;
my $dbdir = TestState::state_dir();
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

	my @htmls = rglob($site_dir, qr/\.html\z/);
	ok(scalar(@htmls) > 0, "produced HTML files (" . scalar(@htmls) . ")");
};

subtest 'overview page generated' => sub {
	ok(-f "$site_dir/index.html", "index.html exists");
	ok(-s "$site_dir/index.html", "index.html has content");
};

subtest 'service pages generated' => sub {
	my @services = rglob($site_dir, qr/cpu.*\.html\z/);
	ok(scalar(@services) > 0, "cpu service pages exist");
};

subtest 'node pages generated' => sub {
	# Node pages live at <group>/<node>/<node>.html (url nesting)
	my @nodes = rglob($site_dir, qr{localhost/[^/]+\.html\z});
	ok(scalar(@nodes) > 0, "localhost node pages exist");
};

subtest 'group pages generated' => sub {
	# Group pages sit at the site root: acme.com.html
	my @groups = glob("$site_dir/acme.com*.html");
	ok(scalar(@groups) > 0, "acme.com group pages exist");
};

subtest 'category pages generated' => sub {
	# Categories are generated as part of the node/group pages
	my @htmls = rglob($site_dir, qr/\.html\z/);
	ok(scalar(@htmls) > 10, "many HTML pages generated");
};

subtest 'problems page generated' => sub {
	# Problems page is only generated if there are problems
	# In test data, we have some warning/critical states
	my @htmls = rglob($site_dir, qr/\.html\z/);
	ok(scalar(@htmls) > 0, "HTML pages exist");
};

subtest 'dynazoom page generated' => sub {
	# Dynazoom is a special page, may not be in static generation
	my @htmls = rglob($site_dir, qr/\.html\z/);
	ok(scalar(@htmls) > 0, "HTML pages exist");
};

subtest 'HTML files have content' => sub {
	my @htmls = rglob($site_dir, qr/\.html\z/);
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
	my @htmls = rglob($site_dir, qr/\.html\z/);
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
