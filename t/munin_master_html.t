use strict;
use warnings;

use lib qw(t/lib);

use Test::More;
use Test::Differences;
use Test::Exception;
use DBI;
use File::Temp qw(tempdir);
use File::Path qw(remove_tree);
use Cwd qw(abs_path);

require_ok( 'Munin::Master::Static::HTML' );
require_ok( 'Munin::Master::Config' );

my $config = Munin::Master::Config->instance()->{"config"};
$config->parse_config_from_file("t/config/munin.conf");

my $dbdir = tempdir("html-$$-XXXXXX", TMPDIR => 1, CLEANUP => 0);
$config->{dbdir} = $dbdir;
$config->{tmpldir} = "web/templates/";

system("mkdir", "-p", "$dbdir/_site");

Munin::Common::Logger::configure(
	"output" => "screen",
	"level" => "info",
);

# Generate sample DB at test time
require SampleDB;
my $dbfile = "$dbdir/datafile.sqlite";
SampleDB::generate_sample_db($dbfile);

# Insert tmpldir into param table (HTML.pm reads it from DB, not config)
my $dbh = DBI->connect("dbi:SQLite:dbname=$dbfile", "", "", {
	RaiseError => 1,
	AutoCommit => 1,
});
my $tmpldir = abs_path("web/templates");
$dbh->do("INSERT OR REPLACE INTO param (name, value) VALUES ('tmpldir', ?)", undef, $tmpldir);
$dbh->disconnect();

Munin::Master::Static::HTML::create(0, $dbdir . "/_site");

# Verify HTML was generated
my @html = glob("$dbdir/_site/*.html");
ok(scalar(@html) > 0, "html create produced HTML files");

# Verify we have index.html
ok(-f "$dbdir/_site/index.html", "html create produced index.html");

# cleanup
remove_tree($dbdir);

print "\n";

done_testing();

1;
