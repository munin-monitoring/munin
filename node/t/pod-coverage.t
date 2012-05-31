use strict;
use warnings;

use Test::More;

plan skip_all => 'set TEST_POD to enable this test' unless $ENV{TEST_POD};

eval 'use Test::Pod::Coverage';
plan (
    skip_all => "Test::Pod::Coverage required for testing POD coverage"
) if $@;
all_pod_coverage_ok();
