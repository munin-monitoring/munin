use strict;
use warnings;

use lib qw(t/lib);


use Test::More tests => 12;
use Test::Differences;
use Test::Exception;

my $c = new Mock::Config();

is($c->_parse_bool("1"), 1);
is($c->_parse_bool("0"), 0);

is($c->_parse_bool("true"), 1);
is($c->_parse_bool("false"), 0);

is($c->_parse_bool("on"), 1);
is($c->_parse_bool("off"), 0);

is($c->_parse_bool("yes"), 1);
is($c->_parse_bool("no"), 0);

dies_ok { $c->_parse_bool("eoizeoijfze") };
dies_ok { $c->_parse_bool("") };

is($c->_parse_bool("TRUE"), 1);
is($c->_parse_bool("FALSE"), 0);

done_testing();

package Mock::Config;

use base qw(Munin::Common::Config);

sub new {
	my $class = shift;
	return bless {}, $class;
}

1;
