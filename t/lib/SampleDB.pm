#!/usr/bin/perl
# Generate sample SQLite database for tests.
# Replaces committed datafile.sqlite that may be stale.

use strict;
use warnings;
use DBI;

sub generate_sample_db {
    my ($dbfile) = @_;

    my $dbh = DBI->connect("dbi:SQLite:dbname=$dbfile", "", "", {
        RaiseError => 1,
        AutoCommit => 1,
    });

    # Create schema
    $dbh->do("CREATE TABLE IF NOT EXISTS grp (id INTEGER PRIMARY KEY, p_id INTEGER, name VARCHAR, path VARCHAR)");
    $dbh->do("CREATE TABLE IF NOT EXISTS node (id INTEGER PRIMARY KEY, grp_id INTEGER, name VARCHAR, path VARCHAR)");
    $dbh->do("CREATE TABLE IF NOT EXISTS service (id INTEGER PRIMARY KEY, node_id INTEGER, name VARCHAR, path VARCHAR)");
    $dbh->do("CREATE TABLE IF NOT EXISTS ds (id INTEGER PRIMARY KEY, service_id INTEGER, name VARCHAR, type VARCHAR)");
    $dbh->do("CREATE TABLE IF NOT EXISTS ds_attr (id INTEGER, name VARCHAR, value VARCHAR)");
    $dbh->do("CREATE TABLE IF NOT EXISTS state (id INTEGER, type VARCHAR, last_epoch INTEGER, last_value VARCHAR, prev_epoch INTEGER, prev_value VARCHAR, alarm VARCHAR, num_unknowns INTEGER)");
    $dbh->do("CREATE TABLE IF NOT EXISTS url (id INTEGER PRIMARY KEY, type VARCHAR, path VARCHAR)");

    my @hosts = ("localhost", "acme.com", "aesir", "asynjur", "svartalfar");
    my @services = ("cpu", "memory", "disk", "network", "load");
    my @ds_defs = (
        { name => "idle",    type => "GAUGE" },
        { name => "user",    type => "GAUGE" },
        { name => "system",  type => "GAUGE" },
        { name => "used",    type => "GAUGE" },
        { name => "free",    type => "GAUGE" },
        { name => "cached",  type => "GAUGE" },
        { name => "rx",      type => "DERIVE" },
        { name => "tx",      type => "DERIVE" },
        { name => "in",      type => "DERIVE" },
        { name => "out",     type => "DERIVE" },
        { name => "value1",  type => "GAUGE" },
        { name => "value2",  type => "GAUGE" },
        { name => "value3",  type => "GAUGE" },
        { name => "value4",  type => "GAUGE" },
        { name => "value5",  type => "GAUGE" },
    );

    my $grp_id = 1;
    my $node_id = 1;
    my $svc_id = 1;
    my $ds_id = 1;

    for my $host (@hosts) {
        my $grp_name = ($host eq "localhost") ? "acme.com" : "";
        my $path = ($host eq "localhost") ? "acme.com/$host" : "$host";

        $dbh->do("INSERT OR IGNORE INTO grp (id, name, path) VALUES (?, ?, ?)",
            undef, $grp_id, $grp_name || $host, $path);

        $dbh->do("INSERT OR IGNORE INTO node (id, grp_id, name, path) VALUES (?, ?, ?, ?)",
            undef, $node_id, $grp_id, $host, $path);

        for my $svc (@services) {
            my $svc_path = "$path/$svc";
            $dbh->do("INSERT OR IGNORE INTO service (id, node_id, name, path) VALUES (?, ?, ?, ?)",
                undef, $svc_id, $node_id, $svc, $svc_path);

            $dbh->do("INSERT OR IGNORE INTO url (type, path) VALUES (?, ?)",
                undef, "service", $svc_path);

            for my $ds (@ds_defs) {
                my $type_id = lc(substr($ds->{type}, 0, 1));
                my $rrd_file = "$path/$svc-$ds->{name}-$type_id.rrd";

                $dbh->do("INSERT OR IGNORE INTO ds (id, service_id, name, type) VALUES (?, ?, ?, ?)",
                    undef, $ds_id, $svc_id, $ds->{name}, $ds->{type});

                $dbh->do("INSERT OR IGNORE INTO ds_attr (id, name, value) VALUES (?, ?, ?)",
                    undef, $ds_id, "rrd:file", $rrd_file);
                $dbh->do("INSERT OR IGNORE INTO ds_attr (id, name, value) VALUES (?, ?, ?)",
                    undef, $ds_id, "rrd:field", "42");

                $ds_id++;
            }
            $svc_id++;
        }
        $node_id++;
        $grp_id++;
    }

    $dbh->disconnect();
}

1;
