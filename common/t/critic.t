use strict;
use warnings;

use Test::More;

use FindBin;
use lib "$FindBin::Bin/../lib";

eval 'use Test::Perl::Critic';
plan (
    skip_all => "Test::Perl::Critic required for testing coding standard"
) if $@;
all_critic_ok();
