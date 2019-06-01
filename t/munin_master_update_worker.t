use strict;
use warnings;

use lib qw(t/lib);


use Test::More;
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

done_testing();

1;
