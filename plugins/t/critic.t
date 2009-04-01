use strict;
use warnings;

use Test::More;

eval 'use Test::Perl::Critic';
plan (
    skip_all => "Test::Perl::Critic required for testing coding standard"
) if $@;

all_critic_ok();
