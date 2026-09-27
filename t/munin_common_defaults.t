#!/usr/bin/perl
# Tests for Munin::Common::Defaults
#
# Prints all defaults and verifies they exist.

use strict;
use warnings;

use lib qw(lib t/lib);

use Test::More;

require Munin::Common::Defaults;

# ============================================================================
# TESTS: Print all defaults
# ============================================================================

diag("=== Munin::Common::Defaults ===");
my $defaults = Munin::Common::Defaults->get_defaults();
for my $key (sort keys %$defaults) {
    diag("$key = $defaults->{$key}");
}
diag("===============================");

# ============================================================================
# TESTS: Verify all defaults exist
# ============================================================================

subtest 'all defaults exist' => sub {
    ok(defined $Munin::Common::Defaults::MUNIN_CONFDIR, "MUNIN_CONFDIR");
    ok(defined $Munin::Common::Defaults::MUNIN_LIBDIR, "MUNIN_LIBDIR");
    ok(defined $Munin::Common::Defaults::MUNIN_HTMLDIR, "MUNIN_HTMLDIR");
    ok(defined $Munin::Common::Defaults::MUNIN_CGITMPDIR, "MUNIN_CGITMPDIR");
    ok(defined $Munin::Common::Defaults::MUNIN_DBDIR, "MUNIN_DBDIR");
    ok(defined $Munin::Common::Defaults::MUNIN_PLUGSTATE, "MUNIN_PLUGSTATE");
    ok(defined $Munin::Common::Defaults::MUNIN_SPOOLDIR, "MUNIN_SPOOLDIR");
    ok(defined $Munin::Common::Defaults::MUNIN_LOGDIR, "MUNIN_LOGDIR");
    ok(defined $Munin::Common::Defaults::MUNIN_STATEDIR, "MUNIN_STATEDIR");
    ok(defined $Munin::Common::Defaults::MUNIN_USER, "MUNIN_USER");
    ok(defined $Munin::Common::Defaults::MUNIN_GROUP, "MUNIN_GROUP");
    ok(defined $Munin::Common::Defaults::MUNIN_VERSION, "MUNIN_VERSION");
    ok(defined $Munin::Common::Defaults::MUNIN_PERL, "MUNIN_PERL");
    ok(defined $Munin::Common::Defaults::MUNIN_HASSETR, "MUNIN_HASSETR");
};

# ============================================================================
# TESTS: Defaults are FHS compliant
# ============================================================================

subtest 'FHS paths' => sub {
    like($Munin::Common::Defaults::MUNIN_CONFDIR, qr{^/etc/}, "MUNIN_CONFDIR is under /etc");
    like($Munin::Common::Defaults::MUNIN_LIBDIR, qr{^/var/lib/}, "MUNIN_LIBDIR is under /var/lib");
    like($Munin::Common::Defaults::MUNIN_HTMLDIR, qr{^/var/www/}, "MUNIN_HTMLDIR is under /var/www");
    like($Munin::Common::Defaults::MUNIN_LOGDIR, qr{^/var/log/}, "MUNIN_LOGDIR is under /var/log");
    like($Munin::Common::Defaults::MUNIN_STATEDIR, qr{^/run/}, "MUNIN_STATEDIR is under /run");
};

# ============================================================================
# TESTS: get_defaults returns all
# ============================================================================

subtest 'get_defaults' => sub {
    my $defaults = Munin::Common::Defaults->get_defaults();
    is(ref($defaults), "HASH", "returns hash ref");
    ok(scalar(keys %$defaults) > 10, "has more than 10 entries");
};

# ============================================================================
# TESTS: export_to_environment
# ============================================================================

subtest 'export_to_environment' => sub {
    Munin::Common::Defaults->export_to_environment();
    is($ENV{MUNIN_CONFDIR}, $Munin::Common::Defaults::MUNIN_CONFDIR, "exports MUNIN_CONFDIR");
    is($ENV{MUNIN_VERSION}, $Munin::Common::Defaults::MUNIN_VERSION, "exports MUNIN_VERSION");
};

print "\n";

done_testing();

1;
