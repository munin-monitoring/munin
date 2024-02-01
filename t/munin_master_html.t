use strict;
use warnings;

use lib qw(t/lib);

use Test::More tests => 2;
use Test::Differences;
use Test::Exception;


use Getopt::Long;

require_ok( 'Munin::Master::Static::HTML' );
require_ok( 'Munin::Master::Config' );


my $config = Munin::Master::Config->instance()->{"config"};
$config->parse_config_from_file("t/config/munin.conf");

$config->{dbdir} .= "/html/$$";
$config->{tmpldir} = "web/templates/";

system("mkdir", "-p", $config->{dbdir});
system("mkdir", "-p", $config->{dbdir} . "/_site");

Munin::Common::Logger::configure(
	"output" => "screen",
	"level" => "info",
);

# Restore sample data
system("cp -r t/sample_data/* $config->{dbdir}"); # need shell expansion

Munin::Master::Static::HTML::create(0, $config->{dbdir} . "/_site");

# cleanup the update dir
system("rm", "-Rf", $config->{dbdir});


# We need to start a new line before done_testing(), otherwise the testing
# framework cannot correclty parse the test results output
print "\n";

done_testing();

1;

__DATA__
