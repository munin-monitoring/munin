#!/usr/bin/perl
# Tests for Munin::Master::HTML
#
# Tests from first principles:
# - Static file serving (with path traversal prevention)
# - 404s (invalid URL, missing service)
# - Redirects (paths without trailing slash)
# - Overview page (empty path)
# - Dynazoom page
# - Problems page
# - Category views
# - Group views (domainview)
# - Node views
# - Service views
# - Comparison views
# - JSON/XML output format
# - Graph extension from cookies/query params
# - Helper functions: url_to_path, url_absolutize

use strict;
use warnings;

use lib qw(lib t/lib);

use Test::More;
use TestUtils;    # setup_test_config, generate_sample_data, mock_update_get_param
use CGI;
use File::Path qw(remove_tree);
use DBI;

use Munin::Common::Logger;
use Munin::Master::HTML;

# ============================================================================
# SETUP
# ============================================================================

my ($config, $dbdir) = TestUtils::setup_test_config();
$config->{staticdir} = "$dbdir/static";

system("mkdir", "-p", "$dbdir/_site");
system("mkdir", "-p", "$dbdir/static");

Munin::Common::Logger::configure(
	output => "screen",
	level  => "info",
);

# Generate sample data
my $dbfile = TestUtils::generate_sample_data($dbdir);

# Mock Munin::Master::Update
my $mock_update = TestUtils::mock_update_get_param($config);

my $dbh = DBI->connect("dbi:SQLite:dbname=$dbfile", "", "", {
	RaiseError => 1,
	AutoCommit => 1,
});

# Get valid paths for testing
my ($valid_service_path) = $dbh->selectrow_array("SELECT path FROM url WHERE service_id IS NOT NULL LIMIT 1");
my ($valid_group_path) = $dbh->selectrow_array("SELECT path FROM url WHERE grp_id IS NOT NULL LIMIT 1");
my ($valid_node_path) = $dbh->selectrow_array("SELECT path FROM url WHERE node_id IS NOT NULL LIMIT 1");

diag("service: $valid_service_path, group: $valid_group_path, node: $valid_node_path");

unless ($valid_service_path) {
	diag("No services in test DB");
	done_testing();
	exit(0);
}

my $tmpdir = TestState::state_dir();

# ============================================================================
# HELPER: Capture handle_request output
# ============================================================================

sub capture_request {
	my (%opts) = @_;
	my $path = $opts{path} // "";
	my $graph_ext = $opts{graph_ext} // "png";
	my $query_string = $opts{query} // "";

	$ENV{PATH_INFO} = $path;
	$ENV{QUERY_STRING} = $query_string;

	# Set up cookies for graph_ext
	delete $ENV{HTTP_COOKIE};
	if ($graph_ext ne "png") {
		$ENV{HTTP_COOKIE} = "graph_ext=$graph_ext";
	}

	my $cgi = CGI->new();

	my $outfile = "$tmpdir/capture_$$.txt";
	local *STDOUT;
	open(STDOUT, '>', $outfile) or die "Cannot redirect STDOUT: $!";
	eval { Munin::Master::HTML::handle_request($cgi) };
	warn "handle_request died: $@" if $@;
	close STDOUT;

	open my $in, '<', $outfile or die "Cannot read $outfile: $!";
	local $/;
	my $output = <$in>;
	close $in;
	unlink $outfile;
	return $output;
}

# ============================================================================
# TESTS: Helper functions
# ============================================================================

subtest 'url_absolutize' => sub {
	is(Munin::Master::HTML::url_absolutize(""), "/", "empty string");
	is(Munin::Master::HTML::url_absolutize("test"), "/test", "simple path");
	is(Munin::Master::HTML::url_absolutize("a/b/c"), "/a/b/c", "nested path");
	is(Munin::Master::HTML::url_absolutize("", 1), "", "empty with omit_first_slash");
	is(Munin::Master::HTML::url_absolutize("test", 1), "test", "simple with omit_first_slash");
};

subtest 'url_to_path' => sub {
	my @paths = Munin::Master::HTML::url_to_path("acme.com/localhost/cpu");
	is(scalar @paths, 3, "three path components");
	is($paths[0]{pathname}, "acme.com", "first component name");
	is($paths[1]{pathname}, "localhost", "second component name");
	is($paths[2]{pathname}, "cpu", "third component name");
	ok($paths[0]{switchable}, "switchable flag set");
};

# ============================================================================
# TESTS: Static file serving
# ============================================================================

subtest 'static - path traversal blocked' => sub {
	my $output = capture_request(path => "/static/../../etc/passwd");
	like($output, qr/HTTP\/1\.[01] 404/, "path traversal returns 404");
};

subtest 'static - not found' => sub {
	my $output = capture_request(path => "/static/nonexistent.css");
	like($output, qr/HTTP\/1\.[01] 404/, "missing static file returns 404");
};

subtest 'static - CSS served' => sub {
	system("echo 'body {}' > $dbdir/static/test.css");
	my $output = capture_request(path => "/static/test.css");
	like($output, qr/HTTP\/1\.[01] 200/, "CSS returns 200");
	like($output, qr/text\/css/, "correct content type");
};

subtest 'static - PNG served' => sub {
	system("echo 'PNG' > $dbdir/static/test.png");
	my $output = capture_request(path => "/static/test.png");
	like($output, qr/HTTP\/1\.[01] 200/, "PNG returns 200");
	like($output, qr/image\/png/, "correct content type");
};

# ============================================================================
# TESTS: 404s
# ============================================================================

subtest '404 - non-existent service' => sub {
	my $output = capture_request(path => "/nonexistent.html");
	like($output, qr/HTTP\/1\.[01] 404/, "returns 404 for missing path");
};

# ============================================================================
# TESTS: Redirects
# ============================================================================

subtest 'redirect - without trailing slash' => sub {
	my $output = capture_request(path => "/problems");
	like($output, qr/HTTP\/1\.[01] 301/, "returns 301 redirect");
};

subtest 'redirect - without .html' => sub {
	my $output = capture_request(path => "/dynazoom");
	like($output, qr/HTTP\/1\.[01] 301/, "returns 301 redirect");
};

# ============================================================================
# TESTS: Overview page
# ============================================================================

subtest 'overview page' => sub {
	my $output = capture_request(path => "/");
	like($output, qr/HTTP\/1\.[01] 200/, "returns 200");
	like($output, qr/Overview|munin/, "contains overview content");
};

# ============================================================================
# TESTS: Dynazoom page
# ============================================================================

subtest 'dynazoom page' => sub {
	my $output = capture_request(path => "/dynazoom.html");
	like($output, qr/HTTP\/1\.[01] 200/, "returns 200");
};

subtest 'dynazoom content_only' => sub {
	my $output = capture_request(path => "/dynazoom.html", query => "content_only=1");
	like($output, qr/HTTP\/1\.[01] 200/, "returns 200 with content_only");
};

# ============================================================================
# TESTS: Problems page
# ============================================================================

subtest 'problems page' => sub {
	my $output = capture_request(path => "/problems.html");
	like($output, qr/HTTP\/1\.[01] 200/, "returns 200");
};

# ============================================================================
# TESTS: Category views
# ============================================================================

subtest 'category view - all time periods' => sub {
	my ($category) = $dbh->selectrow_array("SELECT category FROM service_categories LIMIT 1");
	if ($category) {
		for my $time (qw(day week month year)) {
			my $output = capture_request(path => "/$category-$time.html");
			like($output, qr/HTTP\/1\.[01] 200/, "returns 200 for $category-$time");
		}
	} else {
		pass('No categories in test DB');
		pass('No categories in test DB');
		pass('No categories in test DB');
		pass('No categories in test DB');
	}
};

# ============================================================================
# TESTS: Group views
# ============================================================================

subtest 'group view' => sub {
	if ($valid_group_path) {
		my $output = capture_request(path => "/$valid_group_path/");
		like($output, qr/HTTP\/1\.[01] 200/, "returns 200 for group");
	} else {
		pass('No groups in test DB');
	}
};

# ============================================================================
# TESTS: Node views
# ============================================================================

subtest 'node view' => sub {
	if ($valid_node_path) {
		my $output = capture_request(path => "/$valid_node_path/");
		like($output, qr/HTTP\/1\.[01] 200/, "returns 200 for node");
	} else {
		pass('No nodes in test DB');
	}
};

# ============================================================================
# TESTS: Service views
# ============================================================================

subtest 'service view' => sub {
	my $output = capture_request(path => "/$valid_service_path.html");
	like($output, qr/HTTP\/1\.[01] 200/, "returns 200 for service");
};

# ============================================================================
# TESTS: Comparison views
# ============================================================================

subtest 'comparison view' => sub {
	if ($valid_group_path) {
		my $output = capture_request(path => "/$valid_group_path/comparison-day.html");
		like($output, qr/HTTP\/1\.[01] 200/, "returns 200 for comparison");
	} else {
		pass('No groups in test DB');
	}
};

# ============================================================================
# TESTS: Graph extension from query params
# ============================================================================

subtest 'graph_ext from query param' => sub {
	for my $ext (qw(png svg)) {
		my $output = capture_request(path => "/$valid_service_path.html", query => "graph_ext=$ext");
		like($output, qr/HTTP\/1\.[01] 200/, "returns 200 with graph_ext=$ext");
	}
};

# ============================================================================
# TESTS: JSON/XML output format
# ============================================================================

subtest 'JSON output' => sub {
	my $output = capture_request(path => "/$valid_service_path.json");
	like($output, qr/HTTP\/1\.[01] 200/, "returns 200 for JSON");
};

subtest 'XML output' => sub {
	my $output = capture_request(path => "/$valid_service_path.xml");
	like($output, qr/HTTP\/1\.[01] 200/, "returns 200 for XML");
};

# ============================================================================
# TESTS: Dump parameter
# ============================================================================

subtest 'dump parameter' => sub {
	my $output = capture_request(path => "/$valid_service_path.html", query => "dump=1");
	like($output, qr/HTTP\/1\.[01] 200/, "returns 200 with dump");
};

# ============================================================================
# CLEANUP
# ============================================================================

$dbh->disconnect();
remove_tree($dbdir);
remove_tree($tmpdir);

print "\n";

done_testing();

1;
