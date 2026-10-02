package TestPG;

# PostgreSQL server support for the pg configurations of the test matrix.
#
# The dev image (Dockerfile.dev) ships a postgresql server with trust
# auth on local connections. This module starts the cluster when it is
# not running and hands out scratch databases named munin_test_<pid>_<n>
# (pid-suffixed: parallel prove jobs and concurrent local runs cannot
# collide).
#
# Skip policy -- the whole one: every entry point returns undef when no
# usable server exists (outside the dev image, without DBD::Pg, or with
# a server that refuses to start), and the calling test skips the pg
# configurations. The sqlite configurations run everywhere; the pg configurations run wherever
# postgres exists. No test logic differs per configuration.
#
# Scratch databases are dropped on END when possible. END does not run
# on SIGTERM (see TestState's notes on the same fact), but the dev
# container is ephemeral and the pid-suffixed names cannot collide
# across runs, so a leftover database costs nothing.

use strict;
use warnings;

my $AVAILABLE;    # memoized availability probe: 0/1
my $SEQ = 0;
my @SCRATCH;      # [creator_pid, dbname] pairs, dropped on END by the
                  # creating process only

END {
    # Pid-guarded, for the same reason as TestState: forked children
    # (Parallel::ForkManager workers in the parallel configurations) inherit
    # @SCRATCH and would drop the master's scratch databases when they
    # exit. Only the creating process cleans up.
    for my $db (grep { $_->[0] == $$ } @SCRATCH) {
        my $dbh = eval {
            DBI->connect("dbi:Pg:dbname=postgres", "postgres", undef, {
                RaiseError         => 1,
                AutoCommit         => 1,
                pg_connect_timeout => 3,
            })
        };
        next unless $dbh;
        # DROP DATABASE fails while any handle is still connected; in an
        # ephemeral container a leftover scratch db costs nothing, so
        # failures here are deliberately ignored.
        eval { $dbh->do("DROP DATABASE IF EXISTS $db->[1]") };
    }
}

sub _connects {
    my $dbh = eval {
        DBI->connect("dbi:Pg:dbname=postgres", "postgres", undef, {
            RaiseError       => 1,
            AutoCommit       => 1,
            pg_connect_timeout => 3,
        })
    };
    return $dbh ? 1 : 0;
}

sub _available {
    return $AVAILABLE if defined $AVAILABLE;
    $AVAILABLE = 0;
    return $AVAILABLE unless eval { require DBD::Pg; 1 };
    return $AVAILABLE unless -x "/usr/bin/pg_ctlcluster";

    # Start the cluster if it is down. Errors are silenced: on a host
    # without a local server (or without root) this simply fails and the
    # probe below reports unavailable.
    system("service postgresql start >/dev/null 2>&1") unless _connects();

    # postmaster-up != accepting connections; wait for readiness.
    for (1 .. 50) {
        return $AVAILABLE = 1 if _connects();
        select(undef, undef, undef, 0.1);
    }
    return $AVAILABLE;
}

# Create a fresh scratch database; undef when no server is available
# (caller skips the pg configurations).
sub scratch_db {
    return unless _available();
    # Explicit concatenation, not "..._$$_...": that parses as a
    # scalar-ref deref of $_ (undef here -> "Can't use an undefined
    # value as a SCALAR reference"), not as pid + suffix.
    my $name = "munin_test_" . $$ . "_" . ++$SEQ;
    my $dbh  = DBI->connect("dbi:Pg:dbname=postgres", "postgres", undef, {
        RaiseError => 1,
        AutoCommit => 1,
    });
    $dbh->do("CREATE DATABASE $name");
    $dbh->disconnect;
    push @SCRATCH, [$$, $name];
    return $name;
}

# Plain autocommit handle to a scratch database, for assertions.
sub dbh {
    my ($dbname) = @_;
    return DBI->connect("dbi:Pg:dbname=$dbname", "postgres", undef, {
        RaiseError => 1,
        AutoCommit => 1,
    });
}

1;
