#!/usr/bin/perl
# Generate sample SQLite database for tests.
# Replaces committed datafile.sqlite that may be stale.

use strict;
use warnings;
use DBI;
use Time::HiRes;

package SampleDB;

sub generate_sample_db {
    my ($dbfile) = @_;

    my $dbh = DBI->connect("dbi:SQLite:dbname=$dbfile", "", "", {
        RaiseError => 1,
        AutoCommit => 1,
    });

    # Full schema matching Update.pm
    my $db_serial_type = "INTEGER";
    $dbh->do("CREATE TABLE IF NOT EXISTS param (name VARCHAR PRIMARY KEY, value VARCHAR)");
    $dbh->do("CREATE TABLE IF NOT EXISTS grp (id $db_serial_type PRIMARY KEY, p_id INTEGER REFERENCES grp(id), name VARCHAR, path VARCHAR)");
    $dbh->do("CREATE TABLE IF NOT EXISTS node (id $db_serial_type PRIMARY KEY, grp_id INTEGER REFERENCES grp(id), name VARCHAR, path VARCHAR, spoolepoch INTEGER)");
    $dbh->do("CREATE TABLE IF NOT EXISTS node_attr (id INTEGER REFERENCES node(id), name VARCHAR, value VARCHAR)");
    $dbh->do("CREATE TABLE IF NOT EXISTS service (id $db_serial_type PRIMARY KEY, node_id INTEGER REFERENCES node(id), name VARCHAR, path VARCHAR, service_title VARCHAR, graph_info VARCHAR, subgraphs INTEGER)");
    $dbh->do("CREATE TABLE IF NOT EXISTS service_attr (id INTEGER REFERENCES service(id), name VARCHAR, value VARCHAR)");
    $dbh->do("CREATE TABLE IF NOT EXISTS ds (id $db_serial_type PRIMARY KEY, service_id INTEGER REFERENCES service(id), name VARCHAR, path VARCHAR, type VARCHAR DEFAULT 'GAUGE', ordr INTEGER DEFAULT 0, unknown INTEGER DEFAULT 0, warning INTEGER DEFAULT 0, critical INTEGER DEFAULT 0)");
    $dbh->do("CREATE TABLE IF NOT EXISTS ds_attr (id INTEGER REFERENCES ds(id), name VARCHAR, value VARCHAR)");
    $dbh->do("CREATE TABLE IF NOT EXISTS url (id INTEGER NOT NULL, type VARCHAR NOT NULL, path VARCHAR NOT NULL, PRIMARY KEY(id,type))");
    $dbh->do("CREATE TABLE IF NOT EXISTS state (id INTEGER, type VARCHAR, last_epoch INTEGER, last_value VARCHAR, prev_epoch INTEGER, prev_value VARCHAR, alarm VARCHAR, num_unknowns INTEGER DEFAULT 0)");
    $dbh->do("CREATE UNIQUE INDEX IF NOT EXISTS pk_state ON state (type, id)");
    $dbh->do("CREATE TABLE IF NOT EXISTS contact (id $db_serial_type PRIMARY KEY, name VARCHAR UNIQUE)");
    $dbh->do("CREATE TABLE IF NOT EXISTS contact_attr (id INTEGER REFERENCES contact(id), name VARCHAR, value VARCHAR)");
    $dbh->do("CREATE TABLE IF NOT EXISTS notification (id $db_serial_type PRIMARY KEY, contact_id INTEGER REFERENCES contact(id), service_id INTEGER REFERENCES service(id), severity VARCHAR, sent_at INTEGER, num_messages INTEGER DEFAULT 0)");
    $dbh->do("CREATE UNIQUE INDEX IF NOT EXISTS u_notification ON notification (contact_id, service_id)");
    $dbh->do("CREATE TABLE IF NOT EXISTS override (ds_id INTEGER REFERENCES ds(id), name VARCHAR, value VARCHAR)");
    $dbh->do("CREATE UNIQUE INDEX IF NOT EXISTS pk_override ON override (ds_id, name)");
    $dbh->do("CREATE TABLE IF NOT EXISTS service_categories (id INTEGER REFERENCES service(id), category VARCHAR NOT NULL, PRIMARY KEY (id,category))");
    $dbh->do("CREATE TABLE IF NOT EXISTS stats (runid VARCHAR NOT NULL, tstp TIMESTAMPTZ, type VARCHAR, name VARCHAR, duration NUMERIC)");

    # Insert a global default contact
    $dbh->do("INSERT OR IGNORE INTO param (name, value) VALUES ('contacts', 'testcontact')");

    # Create a test contact with a safe command
    $dbh->do("INSERT OR IGNORE INTO contact (id, name) VALUES (1, 'testcontact')");
    $dbh->do("INSERT OR IGNORE INTO contact_attr (id, name, value) VALUES (1, 'command', '/bin/true')");
    $dbh->do("INSERT OR IGNORE INTO contact_attr (id, name, value) VALUES (1, 'text', '\${var:group} :: \${var:host} :: \${var:graph_title} \${var:worst}')");

    my @hosts = ("localhost", "acme.com", "aesir", "asynjur", "svartalfar");
    my @services = ("cpu", "memory", "disk", "network", "load");

    # DS definitions with thresholds
    my @ds_defs = (
        { name => "idle",    type => "GAUGE",   warn => "80",     crit => "95",     value => "50" },
        { name => "user",    type => "GAUGE",   warn => "70",     crit => "90",     value => "85" },
        { name => "system",  type => "GAUGE",   warn => "60",     crit => "80",     value => "30" },
        { name => "used",    type => "GAUGE",   warn => "80000",  crit => "90000",  value => "75000" },
        { name => "free",    type => "GAUGE",   warn => "10000",  crit => "5000",   value => "25000" },
        { name => "cached",  type => "GAUGE",   warn => undef,    crit => undef,    value => "1000" },
        { name => "rx",      type => "DERIVE",  warn => "1000",   crit => "5000",   value => "2000", prev => "1000" },
        { name => "tx",      type => "DERIVE",  warn => "1000",   crit => "5000",   value => "500",  prev => "100" },
        { name => "in",      type => "GAUGE",   warn => undef,    crit => undef,    value => "100" },
        { name => "out",     type => "GAUGE",   warn => undef,    crit => undef,    value => "200" },
        { name => "value1",  type => "GAUGE",   warn => "50",     crit => "80",     value => "U" },
        { name => "value2",  type => "GAUGE",   warn => "50",     crit => "80",     value => "60" },
        { name => "value3",  type => "GAUGE",   warn => "50",     crit => "80",     value => "40" },
        { name => "value4",  type => "COUNTER", warn => "100",    crit => "500",    value => "300", prev => "200" },
        { name => "value5",  type => "GAUGE",   warn => "50",     crit => "80",     value => "99" },
    );

    # Scenarios per service index to vary results across hosts
    # 0=normal, 1=critical, 2=warning, 3=unknown, 4=recovery
    my @service_scenarios = (0, 1, 2, 3, 4);

    my $grp_id = 1;
    my $node_id = 1;
    my $svc_id = 1;
    my $ds_id = 1;
    my $now = int(Time::HiRes::time());
    my $prev_time = $now - 60;

    for my $host (@hosts) {
        my $grp_name = ($host eq "localhost") ? "acme.com" : "";
        my $path = ($host eq "localhost") ? "acme.com/$host" : "$host";

        $dbh->do("INSERT OR IGNORE INTO grp (id, name, path) VALUES (?, ?, ?)",
            undef, $grp_id, $grp_name || $host, $path);

        $dbh->do("INSERT OR IGNORE INTO node (id, grp_id, name, path) VALUES (?, ?, ?, ?)",
            undef, $node_id, $grp_id, $host, $path);

        # Set notify_alias for notification testing
        $dbh->do("INSERT OR IGNORE INTO node_attr (id, name, value) VALUES (?, 'notify_alias', ?)",
            undef, $node_id, "${host}_alias");

        my $svc_idx = 0;
        for my $svc (@services) {
            my $svc_path = "$path/$svc";
            $dbh->do("INSERT OR IGNORE INTO service (id, node_id, name, path) VALUES (?, ?, ?, ?)",
                undef, $svc_id, $node_id, $svc, $svc_path);

            # Set graph_title and contacts
            $dbh->do("INSERT OR IGNORE INTO service_attr (id, name, value) VALUES (?, 'graph_title', ?)",
                undef, $svc_id, "Graph $svc");
            $dbh->do("INSERT OR IGNORE INTO service_attr (id, name, value) VALUES (?, 'contacts', 'testcontact')",
                undef, $svc_id);

            $dbh->do("INSERT OR IGNORE INTO url (type, path) VALUES (?, ?)",
                undef, "service", $svc_path);

            my $scenario = $service_scenarios[$svc_idx % scalar(@service_scenarios)];

            for my $ds (@ds_defs) {
                my $type_id = lc(substr($ds->{type}, 0, 1));
                my $rrd_file = "$path/$svc-$ds->{name}-$type_id.rrd";

                $dbh->do("INSERT OR IGNORE INTO ds (id, service_id, name, type) VALUES (?, ?, ?, ?)",
                    undef, $ds_id, $svc_id, $ds->{name}, $ds->{type});

                # Always add rrd attrs
                $dbh->do("INSERT OR IGNORE INTO ds_attr (id, name, value) VALUES (?, ?, ?)",
                    undef, $ds_id, "rrd:file", $rrd_file);
                $dbh->do("INSERT OR IGNORE INTO ds_attr (id, name, value) VALUES (?, ?, ?)",
                    undef, $ds_id, "rrd:field", "42");

                # Add warning/critical if defined
                if (defined $ds->{warn}) {
                    $dbh->do("INSERT OR IGNORE INTO ds_attr (id, name, value) VALUES (?, 'warning', ?)",
                        undef, $ds_id, $ds->{warn});
                }
                if (defined $ds->{crit}) {
                    $dbh->do("INSERT OR IGNORE INTO ds_attr (id, name, value) VALUES (?, 'critical', ?)",
                        undef, $ds_id, $ds->{crit});
                }

                # Add extinfo for testing
                if ($ds->{name} eq "idle") {
                    $dbh->do("INSERT OR IGNORE INTO ds_attr (id, name, value) VALUES (?, 'extinfo', 'idle CPU usage')",
                        undef, $ds_id);
                }

                # Add state with realistic values
                my $last_val = $ds->{value} // "U";
                my $prev_val = $ds->{prev} // "U";
                my $alarm = "ok";
                my $num_unk = 0;

                # Override state based on scenario and value
                if ($scenario == 1 && $ds->{name} eq "user") {
                    # Critical: value=85 > crit=90? No, but we set value high
                    $last_val = "95";
                } elsif ($scenario == 2 && $ds->{name} eq "user") {
                    # Warning: value=85 > warn=70
                    # user value is 85 which exceeds warn=70
                } elsif ($scenario == 3 && $ds->{name} eq "value1") {
                    # Unknown: value=U
                    $last_val = "U";
                    $alarm = "unknown";
                    $num_unk = 3;
                } elsif ($scenario == 4 && $ds->{name} eq "idle") {
                    # Recovery: was warning, now OK
                    $alarm = "warning";
                }

                $dbh->do("INSERT OR IGNORE INTO state (id, type, last_epoch, last_value, prev_epoch, prev_value, alarm, num_unknowns) VALUES (?, 'ds', ?, ?, ?, ?, ?, ?)",
                    undef, $ds_id, $now, $last_val, $prev_time, $prev_val, $alarm, $num_unk);

                $ds_id++;
            }
            $svc_id++;
            $svc_idx++;
        }
        $node_id++;
        $grp_id++;
    }

    $dbh->disconnect();
}

1;
