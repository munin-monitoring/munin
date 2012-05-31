use strict;
use warnings;

use Test::More;

use FindBin;
use lib "$FindBin::Bin/../lib";

plan skip_all => 'set TEST_POD to enable this test' unless $ENV{TEST_POD};

eval 'use Test::Perl::Critic';
plan (
    skip_all => "Test::Perl::Critic required for testing coding standard"
) if $@;

plan (
    skip_all => "Only tested in dev environment (\$ENV{MUNIN_ENVIRONMENT} eq 'dev')"
) if $ENV{MUNIN_ENVIRONMENT} && $ENV{MUNIN_ENVIRONMENT} ne 'dev';

all_critic_ok();
