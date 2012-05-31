use strict;
use warnings;

use Test::More;

eval 'use Test::Perl::Critic';
plan (
    skip_all => "Test::Perl::Critic required for testing coding standard"
) if $@;

# Need Perl::Critic newer than 1.096. Older version complains on safe
# pipe open.
eval 'use Perl::Critic 1.096';
plan (
    skip_all => "Perl::Critic newer than 1.096 required for testing coding standard"
) if $@;

all_critic_ok();
