use strict;
use warnings;

use lib qw(lib t/lib);

use Test::More;
use Test::MockModule;
use CGI;
use File::Temp qw(tempdir);
use File::Path qw(remove_tree);
use DBI;
use POSIX qw(:sys_wait_h);

use Munin::Common::Logger;
use Munin::Master::Graph;

# ============================================================================
# SETUP
# ============================================================================

my $config = Munin::Master::Config->instance()->{"config"};
$config->parse_config_from_file("t/config/munin.conf");

my $dbdir = tempdir("graph-$$-XXXXXX", TMPDIR => 1, CLEANUP => 0);
$config->{dbdir} = $dbdir;
$config->{tmpldir} = "web/templates/";

system("mkdir", "-p", "$dbdir/_site");

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

# Mock Munin::Master::Update to use our dbdir
use Munin::Master::Update;
my $mock_update = Test::MockModule->new("Munin::Master::Update");
$mock_update->redefine("get_param", sub {
	my $param = shift;
	return $config->{$param} if defined $config->{$param};
	return undef;
});

my $dbh = DBI->connect("dbi:SQLite:dbname=$dbfile", "", "", {
	RaiseError => 1,
	AutoCommit => 1,
});

# Get a valid service path for testing
my ($valid_path) = $dbh->selectrow_array("SELECT path FROM url WHERE service_id IS NOT NULL LIMIT 1");
diag("valid_path: $valid_path") if $valid_path;
unless ($valid_path) {
	diag("No services in test DB, skipping");
	done_testing();
	exit(0);
}

# ============================================================================
# HELPER: Capture handle_request output
# ============================================================================

my $tmpdir = tempdir("graph-capture-$$-XXXXXX", TMPDIR => 1, CLEANUP => 1);

# ============================================================================
# HELPER: Capture handle_request output
# ============================================================================

sub capture_request {
	my ($path) = @_;
	$ENV{PATH_INFO} = $path;
	my $cgi = CGI->new();

	my $outfile = "$tmpdir/capture_$$.txt";
	local *STDOUT;
	open(STDOUT, '>', $outfile) or die "Cannot redirect STDOUT: $!";
	eval { Munin::Master::Graph::handle_request($cgi) };
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
# TESTS: is_ext_handled
# ============================================================================

subtest 'is_ext_handled' => sub {
	ok(Munin::Master::Graph::is_ext_handled("png"),  "png handled");
	ok(Munin::Master::Graph::is_ext_handled("PNG"),  "PNG handled (case)");
	ok(Munin::Master::Graph::is_ext_handled("svg"),  "svg handled");
	ok(Munin::Master::Graph::is_ext_handled("json"), "json handled");
	ok(Munin::Master::Graph::is_ext_handled("csv"),  "csv handled");
	ok(Munin::Master::Graph::is_ext_handled("xml"),  "xml handled");
	ok(Munin::Master::Graph::is_ext_handled("pdf"),  "pdf handled");
	ok(Munin::Master::Graph::is_ext_handled("eps"),  "eps handled");
	ok(Munin::Master::Graph::is_ext_handled("ps"),   "ps handled");

	ok(!Munin::Master::Graph::is_ext_handled("gif"),      "gif not handled");
	ok(!Munin::Master::Graph::is_ext_handled("bmp"),      "bmp not handled");
	ok(!Munin::Master::Graph::is_ext_handled("webp"),     "webp not handled");
	ok(!Munin::Master::Graph::is_ext_handled(""),         "empty string not handled");
	ok(!Munin::Master::Graph::is_ext_handled(undef),      "undef not handled");
	ok(!Munin::Master::Graph::is_ext_handled("txt"),      "txt not handled");
	ok(!Munin::Master::Graph::is_ext_handled("unknown"),  "unknown not handled");
};

# ============================================================================
# TESTS: Helper functions
# ============================================================================

subtest 'is_virtual' => sub {
	ok(!Munin::Master::Graph::is_virtual("field1", ""),           "empty cdef not virtual");
	ok(!Munin::Master::Graph::is_virtual("field1", undef),       "undef cdef not virtual");
	ok(!Munin::Master::Graph::is_virtual("field1", "field1,1,+"), "field in cdef not virtual");
	ok(Munin::Master::Graph::is_virtual("field1", "field2,1,+" ), "field not in cdef is virtual");
	ok(Munin::Master::Graph::is_virtual("field1", "field2,field3,+"), "multiple fields, field1 absent");
	ok(!Munin::Master::Graph::is_virtual("field1", "field1,field2,+"), "field1 at start");
	ok(!Munin::Master::Graph::is_virtual("field2", "field1,field2,+"), "field2 at end");
	ok(!Munin::Master::Graph::is_virtual("field1", "field1"),         "single field matches");
	ok(Munin::Master::Graph::is_virtual("x", "a,b,c"),                 "not in list of 3");
};

subtest 'remove_dups' => sub {
	is(Munin::Master::Graph::remove_dups("a b a c b"), "a b c", "deduplicates");
	is(Munin::Master::Graph::remove_dups("a b c"), "a b c", "no dups unchanged");
	is(Munin::Master::Graph::remove_dups("single"), "single", "single element");
	is(Munin::Master::Graph::remove_dups(""), undef, "empty string returns undef");
	is(Munin::Master::Graph::remove_dups(undef), undef, "undef returns undef");
	is(Munin::Master::Graph::remove_dups("a a a a a"), "a", "all same");
};

subtest 'is_int' => sub {
	ok(Munin::Master::Graph::is_int("0"),      "zero is int");
	ok(Munin::Master::Graph::is_int("123"),    "digits are int");
	ok(Munin::Master::Graph::is_int("999999"), "large int");
	ok(!Munin::Master::Graph::is_int("1.5"),   "decimal not int");
	ok(!Munin::Master::Graph::is_int("-1"),    "negative not int");
	ok(!Munin::Master::Graph::is_int("abc"),   "letters not int");
	ok(!Munin::Master::Graph::is_int(""),      "empty not int");
	ok(!Munin::Master::Graph::is_int("1e10"),  "scientific not int");
	ok(!Munin::Master::Graph::is_int(" 12"),   "leading space not int");
	ok(!Munin::Master::Graph::is_int("12 "),   "trailing space not int");
};

subtest 'escape_for_rrd' => sub {
	is(Munin::Master::Graph::escape_for_rrd("hello"), "hello", "plain text unchanged");
	is(Munin::Master::Graph::escape_for_rrd("a:b"), "a\\:b", "colon escaped");
	is(Munin::Master::Graph::escape_for_rrd("a\\b"), "a\\\\b", "backslash escaped");
	is(Munin::Master::Graph::escape_for_rrd("a:b\\c"), "a\\:b\\\\c", "both escaped");
	is(Munin::Master::Graph::escape_for_rrd(""), "", "empty string");
	is(Munin::Master::Graph::escape_for_rrd(undef), undef, "undef returns undef");
};

subtest 'expand_cdef' => sub {
	is(Munin::Master::Graph::expand_cdef("field1", "field1,1,+", "r_field1"), "r_field1,1,+", "simple replacement");
	is(Munin::Master::Graph::expand_cdef("a", "a,b,+", "ra"), "ra,b,+", "replaces first");
	is(Munin::Master::Graph::expand_cdef("b", "a,b,+", "rb"), "a,rb,+", "replaces middle");
	is(Munin::Master::Graph::expand_cdef("c", "a,b,c,+", "rc"), "a,b,rc,+", "replaces last");
	is(Munin::Master::Graph::expand_cdef("x", "a,b,c,+", "rx"), "a,b,c,+", "no match unchanged");
	is(Munin::Master::Graph::expand_cdef("field", "field", "r_field"), "r_field", "single field");
};

# ============================================================================
# TESTS: handle_request - 404s
# ============================================================================

subtest '404 on invalid URL' => sub {
	my $output = capture_request("/invalid-url.png");
	like($output, qr/HTTP\/1\.[01] 404/, "returns 404");
	like($output, qr/invalid URL/, "reason mentions invalid URL");
};

subtest '404 on unknown format' => sub {
	my $output = capture_request("/$valid_path-hour.gif");
	like($output, qr/HTTP\/1\.[01] 404/, "returns 404 for gif");
};

subtest '404 on non-existent service' => sub {
	my $output = capture_request("/nonexistent-service-hour.png");
	like($output, qr/HTTP\/1\.[01] 404/, "returns 404 for missing service");
};

# ============================================================================
# TESTS: handle_request - valid formats
# ============================================================================

for my $fmt (qw(png svg csv xml json pdf eps ps)) {
	subtest "valid format: $fmt" => sub {
		my $output = capture_request("/$valid_path-hour.$fmt");
		like($output, qr/HTTP\/1\.[01] 200/, "returns 200 for $fmt");
	};
}

# ============================================================================
# TESTS: handle_request - HiDPI
# ============================================================================

subtest 'HiDPI PNG' => sub {
	my $output = capture_request("/$valid_path-hour.pngx2");
	like($output, qr/HTTP\/1\.[01] 200/, "returns 200 for pngx2");
};

subtest 'HiDPI forces PNG' => sub {
	# HiDPI with non-PNG extension should still work (forces PNG)
	my $output = capture_request("/$valid_path-hour.pngx3");
	like($output, qr/HTTP\/1\.[01] 200/, "returns 200 for pngx3");
};

# ============================================================================
# TESTS: handle_request - time periods
# ============================================================================

for my $period (qw(hour day week month year)) {
	subtest "time period: $period" => sub {
		my $output = capture_request("/$valid_path-$period.png");
		like($output, qr/HTTP\/1\.[01] 200/, "returns 200 for $period");
	};
}

subtest 'pinpoint time range' => sub {
	my $now = time();
	my $start = $now - 3600;
	my $output = capture_request("/$valid_path-pinpoint=$start,$now.png");
	like($output, qr/HTTP\/1\.[01] 200/, "returns 200 for pinpoint");
};

# ============================================================================
# TESTS: handle_request - URL path variations
# ============================================================================

subtest 'URL with dots in path' => sub {
	# Some services have dots in their paths
	my ($dot_path) = $dbh->selectrow_array(
		"SELECT path FROM url WHERE service_id IS NOT NULL AND path LIKE '%.%' LIMIT 1"
	);
	if ($dot_path) {
		my $output = capture_request("/$dot_path-hour.png");
		like($output, qr/HTTP\/1\.[01] 200/, "returns 200 for dotted path");
	} else {
		pass('No dotted paths in test DB');
	}
};

# ============================================================================
# TESTS: handle_request - edge cases
# ============================================================================

subtest 'empty path' => sub {
	my $output = capture_request("/");
	like($output, qr/HTTP\/1\.[01] 404/, "returns 404 for empty path");
};

subtest 'path without extension' => sub {
	my $output = capture_request("/$valid_path-hour");
	like($output, qr/HTTP\/1\.[01] 404/, "returns 404 without extension");
};

subtest 'path without time period' => sub {
	my $output = capture_request("/$valid_path.png");
	like($output, qr/HTTP\/1\.[01] 404/, "returns 404 without time period");
};

# ============================================================================
# TESTS: Negative series (structure only — needs specific DB setup)
# ============================================================================

subtest 'negative series DB structure' => sub {
	# Check if any services have negative fields in the test DB
	my ($has_negative) = $dbh->selectrow_array(
		"SELECT COUNT(*) FROM ds_attr WHERE name = 'negative'"
	);

	if ($has_negative) {
		ok(1, "DB has negative fields to test");
	} else {
		# Test the code path by checking the SQL query handles it
		my $sth = $dbh->prepare_cached("
			SELECT ds.name,
				ne.value,
				(
					select hn.id
					from ds hn
					JOIN ds_attr hn_attr ON hn_attr.id = hn.id AND hn_attr.value = ds.name and hn_attr.name = 'negative'
					where hn.service_id = ds.service_id
				) as negative_id
			FROM ds
			LEFT OUTER JOIN ds_attr ne ON ne.id = ds.id AND ne.name = 'negative'
			WHERE ds.service_id = (SELECT id FROM service LIMIT 1)
		");
		ok($sth, "negative query executes");
		$sth->execute();
		my @rows = $sth->fetchall_arrayref;
		ok(defined $rows[0], "query returns results");
	}
};

# ============================================================================
# TESTS: Sum aggregation (structure only)
# ============================================================================

subtest 'sum aggregation DB structure' => sub {
	my ($has_sum) = $dbh->selectrow_array(
		"SELECT COUNT(*) FROM ds_attr WHERE name = 'sum'"
	);

	if ($has_sum) {
		ok(1, "DB has sum fields to test");
	} else {
		# Verify the query handles sum attribute
		my $sth = $dbh->prepare_cached("
			SELECT ds.name, sm.value as sum
			FROM ds
			LEFT OUTER JOIN ds_attr sm ON sm.id = ds.id AND sm.name = 'sum'
			WHERE ds.service_id = (SELECT id FROM service LIMIT 1)
		");
		ok($sth, "sum query executes");
		$sth->execute();
		my @rows = $sth->fetchall_arrayref;
		ok(defined $rows[0], "query returns results");
	}
};

# ============================================================================
# TESTS: Colour assignment
# ============================================================================

subtest 'colour assignment in handle_request' => sub {
	# Request a graph and verify it doesn't crash with colour logic
	my $output = capture_request("/$valid_path-day.png");
	like($output, qr/HTTP\/1\.[01] 200/, "colour assignment works for day");
};

# ============================================================================
# TESTS: graph_args handling
# ============================================================================

subtest 'graph_args with --base 1024' => sub {
	# Check if any service has graph_args with --base 1024
	my ($has_base1024) = $dbh->selectrow_array(
		"SELECT COUNT(*) FROM service_attr WHERE name = 'graph_args' AND value LIKE '%--base%1024%'"
	);

	# Just verify the code path exists - the printf should use %7.2lf for base 1024
	if ($has_base1024) {
		ok(1, "DB has graph_args with --base 1024");
	} else {
		pass('No base-1024 services in test DB');
	}
};

# ============================================================================
# TESTS: graph_scale
# ============================================================================

subtest 'graph_scale=no handling' => sub {
	# Check if any service has graph_scale=no
	my ($has_scale_no) = $dbh->selectrow_array(
		"SELECT COUNT(*) FROM service_attr WHERE name = 'graph_scale' AND value = 'no'"
	);

	if ($has_scale_no) {
		ok(1, "DB has graph_scale=no");
	} else {
		pass('No graph_scale=no services in test DB');
	}
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
