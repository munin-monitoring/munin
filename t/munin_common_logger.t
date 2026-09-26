use strict;
use warnings;

use lib qw(lib t/lib);

use Test::More;
use Test::Exception;
use File::Temp qw(tempfile);

# Load Logger
use Munin::Common::Logger;

# Configure to log to a temp file for testing
my ($logfh, $logfile) = tempfile(CLEANUP => 1);
close $logfh;

Munin::Common::Logger::configure(
    output => 'file',
    level  => 'debug',
    logfile => $logfile,
);

# ============================================================================
# TEST: WARN logs at WARNING level
# ============================================================================

subtest 'WARN logs message' => sub {
    WARN "test warning message";
    
    open my $fh, '<', $logfile or die "Cannot read $logfile: $!";
    my $content = do { local $/; <$fh> };
    close $fh;
    
    like($content, qr/test warning message/, "WARN message logged");
    like($content, qr/\bwarning\b/i, "Logged at warning level");
};

# ============================================================================
# TEST: FATAL logs and dies
# ============================================================================

subtest 'FATAL logs and dies' => sub {
    # Clear log file
    open my $fh, '>', $logfile or die "Cannot write $logfile: $!";
    close $fh;
    
    dies_ok {
        FATAL "test fatal error"
    } "FATAL dies";
    
    like($@, qr/test fatal error/, "FATAL error message in die");
    
    open $fh, '<', $logfile or die "Cannot read $logfile: $!";
    my $content = do { local $/; <$fh> };
    close $fh;
    
    like($content, qr/test fatal error/, "FATAL message logged");
    like($content, qr/\bcritical\b/i, "Logged at critical level");
};

# ============================================================================
# TEST: _remove_label strips all prefixes
# ============================================================================

subtest '_remove_label strips all prefixes' => sub {
    my @test_cases = (
        "[DEBUG] test"    => "test",
        "[INFO] test"     => "test",
        "[NOTICE] test"   => "test",
        "[WARNING] test"  => "test",
        "[ERROR] test"    => "test",
        "[CRITICAL] test" => "test",
        "[FATAL] test"    => "test",
        "[ALERT] test"    => "test",
        "[EMERGENCY] test" => "test",
    );
    
    while (my ($input, $expected) = splice(@test_cases, 0, 2)) {
        my $result = Munin::Common::Logger::_remove_label($input);
        is($result, $expected, "_remove_label strips '$input'");
    }
};

# ============================================================================
# TEST: Levels are ordered correctly
# ============================================================================

subtest 'Log levels exist' => sub {
    can_ok('Munin::Common::Logger', qw(INFO NOTICE WARN ERROR CRITICAL FATAL ALERT EMERGENCY));
};

done_testing();

1;
