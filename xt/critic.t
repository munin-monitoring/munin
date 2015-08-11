use strict;
use warnings;

use Test::More;

use FindBin;
use lib "$FindBin::Bin/../lib";

plan skip_all => 'set TEST_CRITIC to enable this test' unless $ENV{TEST_CRITIC};

use Test::Perl::Critic (
    -severity => 'stern',
    -verbose  => "[%p] %m at line %l, near '%r'.  (Severity: %s)\n",
);

all_critic_ok();
