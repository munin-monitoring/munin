use strict;
use warnings;

use Test::More;

use FindBin;
use lib "$FindBin::Bin/../lib";

eval 'use Test::Pod::Coverage';
plan (
    skip_all => "Test::Pod::Coverage required for testing POD coverage"
) if $@;
all_pod_coverage_ok();
