use strict;
use warnings;

use lib qw(t/lib);

use Test::More;
use Test::Differences;
use Test::Exception;
use File::Temp qw(tempdir);
use File::Path qw(remove_tree);

require_ok( 'Munin::Master::Static::HTML' );
require_ok( 'Munin::Master::Config' );

my $config = Munin::Master::Config->instance()->{"config"};
$config->parse_config_from_file("t/config/munin.conf");

my $dbdir = tempdir("html-$$-XXXXXX", TMPDIR => 1, CLEANUP => 0);
$config->{dbdir} = $dbdir;
$config->{tmpldir} = "web/templates/";

system("mkdir", "-p", "$dbdir/_site");

Munin::Common::Logger::configure(
	"output" => "file",
	"file" => "/dev/null",
	"level" => "info",
);

# Generate sample DB at test time
require SampleDB;
my $dbfile = "$dbdir/datafile.sqlite";
SampleDB::generate_sample_db($dbfile);

Munin::Master::Static::HTML::create(0, $dbdir . "/_site");

# Verify HTML was generated
my @html = glob("$dbdir/_site/**/*.html");
ok(scalar(@html) > 0, "html create produced HTML files");

# Verify we have index.html
ok(-f "$dbdir/_site/index.html", "html create produced index.html");

# cleanup
remove_tree($dbdir);

print "\n";

done_testing();

1;
