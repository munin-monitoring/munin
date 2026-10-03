-- Golden v0 DDL: the pre-versioning create_schema body, minus ds_rrd,
-- minus the ds.deleted column, minus version_history (which did not
-- exist yet). This is the schema munin-upgrade-db's v0 -> v1 step is
-- defined against; t/munin_master_schema_migration.t builds upgrade
-- fixtures by executing this file.
--
-- Provenance: rendered from lib/Munin/Master/Schema.pm's canonical
-- table specs (the same structure create_schema renders from), with
-- ds_rrd and ds.deleted filtered out. Regenerate with:
--   perl -Ilib -e 'require Munin::Master::Schema; ...' (see mission log)
--
-- sqlite flavor (golden). The pg cell of the test matrix substitutes
-- "id SERIAL PRIMARY KEY" for "id INTEGER PRIMARY KEY" -- the only
-- per-driver difference in this DDL.
CREATE TABLE IF NOT EXISTS param (
    name VARCHAR PRIMARY KEY,
    value VARCHAR
);
CREATE TABLE IF NOT EXISTS grp (
    id INTEGER PRIMARY KEY,
    p_id INTEGER REFERENCES grp(id),
    name VARCHAR,
    path VARCHAR
);
CREATE UNIQUE INDEX IF NOT EXISTS r_g_grp ON grp (p_id, name);
CREATE TABLE IF NOT EXISTS node (
    id INTEGER PRIMARY KEY,
    grp_id INTEGER REFERENCES grp(id),
    name VARCHAR,
    path VARCHAR,
    spoolepoch INTEGER
);
CREATE INDEX IF NOT EXISTS r_n_grp ON node (grp_id);
CREATE TABLE IF NOT EXISTS node_attr (
    id INTEGER REFERENCES node(id),
    name VARCHAR,
    value VARCHAR
);
CREATE UNIQUE INDEX IF NOT EXISTS pk_node_attr ON node_attr (id, name);
CREATE TABLE IF NOT EXISTS service (
    id INTEGER PRIMARY KEY,
    node_id INTEGER REFERENCES node(id),
    name VARCHAR,
    path VARCHAR,
    service_title VARCHAR,
    graph_info VARCHAR,
    subgraphs INTEGER
);
CREATE UNIQUE INDEX IF NOT EXISTS u_service_n_n ON service (node_id, name);
CREATE INDEX IF NOT EXISTS r_s_node ON service (node_id);
CREATE TABLE IF NOT EXISTS service_attr (
    id INTEGER REFERENCES service(id),
    name VARCHAR,
    value VARCHAR
);
CREATE UNIQUE INDEX IF NOT EXISTS pk_service_attr ON service_attr (id, name);
CREATE TABLE IF NOT EXISTS service_categories (
    id INTEGER REFERENCES service(id),
    category VARCHAR NOT NULL,
    PRIMARY KEY (id, category)
);
CREATE TABLE IF NOT EXISTS ds (
    id INTEGER PRIMARY KEY,
    service_id INTEGER REFERENCES service(id),
    name VARCHAR,
    path VARCHAR,
    type VARCHAR DEFAULT 'GAUGE',
    ordr INTEGER DEFAULT 0,
    unknown INTEGER DEFAULT 0,
    warning INTEGER DEFAULT 0,
    critical INTEGER DEFAULT 0
);
CREATE INDEX IF NOT EXISTS r_d_service ON ds (service_id);
CREATE TABLE IF NOT EXISTS ds_attr (
    id INTEGER REFERENCES ds(id),
    name VARCHAR,
    value VARCHAR
);
CREATE UNIQUE INDEX IF NOT EXISTS pk_ds_attr ON ds_attr (id, name);
CREATE TABLE IF NOT EXISTS url (
    path VARCHAR PRIMARY KEY,
    grp_id INTEGER REFERENCES grp(id),
    node_id INTEGER REFERENCES node(id),
    service_id INTEGER REFERENCES service(id),
    CHECK (CAST((grp_id IS NOT NULL) AS INTEGER) + CAST((node_id IS NOT NULL) AS INTEGER) + CAST((service_id IS NOT NULL) AS INTEGER) = 1)
);
CREATE TABLE IF NOT EXISTS state (
    ds_id INTEGER REFERENCES ds(id),
    node_id INTEGER REFERENCES node(id),
    last_epoch INTEGER,
    last_value VARCHAR,
    prev_epoch INTEGER,
    prev_value VARCHAR,
    alarm VARCHAR,
    num_unknowns INTEGER DEFAULT 0,
    prev_alarm VARCHAR,
    eval_value VARCHAR,
    extinfo VARCHAR,
    CHECK (CAST((ds_id IS NOT NULL) AS INTEGER) + CAST((node_id IS NOT NULL) AS INTEGER) = 1)
);
CREATE UNIQUE INDEX IF NOT EXISTS pk_state_ds ON state (ds_id);
CREATE UNIQUE INDEX IF NOT EXISTS pk_state_node ON state (node_id);
CREATE TABLE IF NOT EXISTS stats (
    runid VARCHAR NOT NULL,
    tstp TIMESTAMPTZ,
    type VARCHAR,
    name VARCHAR,
    duration NUMERIC
);
CREATE TABLE IF NOT EXISTS contact (
    id INTEGER PRIMARY KEY,
    name VARCHAR UNIQUE
);
CREATE TABLE IF NOT EXISTS contact_attr (
    id INTEGER REFERENCES contact(id),
    name VARCHAR,
    value VARCHAR
);
CREATE UNIQUE INDEX IF NOT EXISTS pk_contact_attr ON contact_attr (id, name);
CREATE TABLE IF NOT EXISTS notification_tracking (
    id INTEGER PRIMARY KEY,
    contact_id INTEGER REFERENCES contact(id),
    service_id INTEGER REFERENCES service(id),
    severity VARCHAR,
    sent_at INTEGER,
    num_messages INTEGER DEFAULT 0
);
CREATE UNIQUE INDEX IF NOT EXISTS u_notification_tracking ON notification_tracking (contact_id, service_id);
CREATE TABLE IF NOT EXISTS override (
    ds_id INTEGER REFERENCES ds(id),
    name VARCHAR,
    value VARCHAR
);
CREATE UNIQUE INDEX IF NOT EXISTS pk_override ON override (ds_id, name);
CREATE TABLE IF NOT EXISTS config_override (
    host_name VARCHAR NOT NULL,
    service_name VARCHAR NOT NULL DEFAULT '',
    field_name VARCHAR NOT NULL DEFAULT '',
    name VARCHAR NOT NULL,
    value VARCHAR,
    PRIMARY KEY (host_name, service_name, field_name, name)
);
