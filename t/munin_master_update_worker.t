use strict;
use warnings;

use lib qw(t/lib);


use Test::More;
use Test::Differences;

use Munin::Master::UpdateWorker;

# parse_update_rate
sub parse_update_rate { my @ret = Munin::Master::UpdateWorker::parse_update_rate(@_); return \@ret; }

is_deeply(parse_update_rate("5"), [ 5, 0 ], "update_rate: 5");
is_deeply(parse_update_rate("5s"), [ 5, 0 ], "update_rate: 5s");
is_deeply(parse_update_rate("5m"), [ 300, 0 ], "update_rate: 5m");
is_deeply(parse_update_rate("5t"), [ 13392000, 0 ], "update_rate: 5t");
is_deeply(parse_update_rate("5m aligned"), [ 300, " aligned" ], "update_rate: 5m aligned");

sub parse_custom_resolution { my @ret = Munin::Master::UpdateWorker::parse_custom_resolution(@_); return \@ret; }

is_deeply(parse_custom_resolution("42", 300), [ [1, 42] ], "graph_data_size: 42");
is_deeply(parse_custom_resolution("42, 10 10", 300), [ [1, 42], [10, 10] ], "graph_data_size: 42,10 10");

is_deeply(parse_custom_resolution("1h", 300), [ [1, 12], ], "graph_data_size: 1h");
is_deeply(parse_custom_resolution("1h, 1h for 1t, 5m for 1y", 300), [ [1, 12], [12, 744], [1, 105120], ], "graph_data_size: 1h");

sub round_to_granularity { my $ret = Munin::Master::UpdateWorker::round_to_granularity(@_); return $ret; }

use Time::Local;
# timegm($sec,$min,$hours,$day,$month,$year);
my $time_20190101_010501 = timegm(01, 05, 01, 01, 01, 2019);
my $time_20190101_010500 = timegm(00, 05, 01, 01, 01, 2019);
my $time_20190101_010000 = timegm(00, 00, 01, 01, 01, 2019);
my $time_20190101_000000 = timegm(00, 00, 00, 01, 01, 2019);
is(round_to_granularity($time_20190101_010501, 300),   $time_20190101_010500, "time_20190101_010501: rounded to 5 min");
is(round_to_granularity($time_20190101_010501, 3600),  $time_20190101_010000, "time_20190101_010501: rounded to 1 hour");
is(round_to_granularity($time_20190101_010501, 86400), $time_20190101_000000, "time_20190101_010501: rounded to 1 day");

done_testing();

1;
