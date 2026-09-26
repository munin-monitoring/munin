use strict;
use warnings;

use lib qw(lib t/lib);

use Test::More;

# Test RRDCACHED branching logic by reading the actual source file

# ============================================================================
# TEST: Verify RRDCACHED branching exists in source
# ============================================================================

my $src_file = "lib/Munin/Master/UpdateWorker.pm";
open my $fh, '<', $src_file or die "Cannot read $src_file: $!";
my $src = do { local $/; <$fh> };
close $fh;

subtest 'RRDCACHED branching structure' => sub {
    # Check that the branching logic exists
    like($src, qr/if\s*\(\$ENV\{RRDCACHED_ADDRESS\}/, "Checks RRDCACHED_ADDRESS env var");
    like($src, qr/scalar\s+\@update_rrd_data\s*>\s*32/, "Threshold is > 32");
    like($src, qr/for\s+my\s+\$update_rrd_data\s+\(\@update_rrd_data\)/, "Loops through updates for RRDCACHED");
    like($src, qr/RRDs::update\(\$rrd_file,\s*\$update_rrd_data\)/, "Single update per iteration");
    like($src, qr/last\s+if\s+RRDs::error/, "Breaks on error");
};

subtest 'Normal path structure' => sub {
    # Check the else branch (normal path)
    like($src, qr/else\s*\{/, "Has else branch");
    like($src, qr/RRDs::update\(\$rrd_file,\s*\@update_rrd_data\)/, "Single update with all data");
};

subtest 'NO_UPDATE_RRD guard' => sub {
    like($src, qr/unless\s+\$ENV\{NO_UPDATE_RRD\}/, "Respects NO_UPDATE_RRD");
};

done_testing();

1;
