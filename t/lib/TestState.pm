package TestState;

# Per-test state directory -- prescriptive paths, no runtime magic.
#
# Layout (rigid on purpose):
#   $MUNIN_TEST_STATE_ROOT/<pid>-<testname>-<n>/
#   root default: /dev/shm/munin-var-lib
#
# Rules:
#   - The root must be creatable and writable, or the test dies here. No
#     silent fallback to /tmp: state on disk instead of tmpfs changes what
#     the tests measure, and a test that quietly runs in the wrong place is
#     a false signal. Set MUNIN_TEST_STATE_ROOT explicitly for other setups.
#   - Names are deterministic: pid (collides only with dead runs), test
#     name (greppable in failure output), call counter (a test may ask for
#     several directories; each gets its own, in order).
#   - A directory starts empty -- leftovers from a crashed run with the
#     same pid are removed first.
#   - Created directories are removed at process exit (END runs on die;
#     kill -9 leaks, visibly, not silently).
#
#   my $dbdir = TestState::state_dir();
#   # .../1234-munin_master_html-1   then later   .../1234-munin_master_html-2

use strict;
use warnings;

use File::Path qw(make_path remove_tree);

my $ROOT  = $ENV{MUNIN_TEST_STATE_ROOT} || "/dev/shm/munin-var-lib";
my $CALLS = 0;
my @created;

END { remove_tree($_) for @created }

sub state_dir {
    make_path($ROOT) unless -d $ROOT;
    die "TestState: '$ROOT' is not a writable directory; "
      . "set MUNIN_TEST_STATE_ROOT to a tmpfs path\n"
        unless -d $ROOT && -w $ROOT;

    my ($test) = $0 =~ m{([^/]+)\.\w+\z};
    $test = defined $test ? $test : "unknown";
    $test =~ s/[^\w.-]/_/g;

    my $dir = sprintf("%s/%d-%s-%d", $ROOT, $$, $test, ++$CALLS);
    remove_tree($dir);    # clean slate: crashed run with same pid
    make_path($dir);
    push @created, $dir;
    return $dir;
}

1;
