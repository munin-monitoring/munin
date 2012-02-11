use strict;
use warnings;

use Test::More;

use FindBin;
use lib "$FindBin::Bin/../lib";

plan skip_all => 'set TEST_POD to enable this test' unless $ENV{TEST_POD};

eval 'use Test::Pod';
plan (
    skip_all => "Test::Pod required for testing for POD errors"
) if $@;
all_pod_files_ok();
