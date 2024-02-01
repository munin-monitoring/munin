use strict;
use warnings;

use lib qw(t/lib);

use Test::More tests => 2;
use Test::Differences;
use Test::Exception;
use Test::MockModule;

require_ok( 'Munin::Master::Static::Graph' );
require_ok( 'Munin::Master::Config' );


my $config = Munin::Master::Config->instance()->{"config"};
$config->parse_config_from_file("t/config/munin.conf");

$config->{dbdir} .= "/graph/$$";
$config->{tmpldir} = "web/templates/";

system("mkdir", "-p", $config->{dbdir});
system("mkdir", "-p", $config->{dbdir} . "/_site");

Munin::Common::Logger::configure(
	"output" => "screen",
	"level" => "info",
);

# Restore sample data
system("cp -r t/sample_data/* $config->{dbdir}"); # need shell expansion

my $mock = Test::MockModule->new("Munin::Master::Graph");
# replace all calls to get_param
$mock->redefine("get_param", sub {
	my $param = shift;
	return $config->{$param} if defined $config->{$param};
	return $mock->original("get_param")->($param);
});


Munin::Master::Static::Graph::create(0, $config->{dbdir} . "/_site");

# cleanup the update dir
system("rm", "-Rf", $config->{dbdir});


# We need to start a new line before done_testing(), otherwise the testing
# framework cannot correclty parse the test results output
print "\n";

done_testing();

1;

__DATA__
