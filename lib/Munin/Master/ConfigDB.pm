package Munin::Master::ConfigDB;

use warnings;
use strict;

use Carp;
use DBI;

=head1 NAME

Munin::Master::ConfigDB - SQLite schema and queries for Config v3

=head1 SYNOPSIS

    my $db = Munin::Master::ConfigDB->new(dbpath => '/var/lib/munin/config.db');
    $db->ensure_schema();
    $db->insert_global('timeout', '180');
    my $val = $db->get_global('timeout');

=head1 DESCRIPTION

Implements the SQLite-first config storage for Munin Config v3.
Config is imported once from files, then queried from DB at runtime.

=cut

sub new {
    my ($class, %args) = @_;

    my $self = bless {
        dbpath => $args{dbpath} || '/var/lib/munin/config.db',
        dbh    => undef,
    }, $class;

    return $self;
}

sub dbh {
    my ($self) = @_;

    unless ($self->{dbh}) {
        $self->{dbh} = DBI->connect(
            "dbi:SQLite:dbname=$self->{dbpath}",
            '', '',
            {
                RaiseError => 1,
                AutoCommit => 1,
                sqlite_unicode => 1,
            }
        ) or croak "Cannot connect to $self->{dbpath}: $DBI::errstr";
    }

    return $self->{dbh};
}

sub disconnect {
    my ($self) = @_;

    if ($self->{dbh}) {
        $self->{dbh}->disconnect();
        $self->{dbh} = undef;
    }
}

=head1 SCHEMA

=head2 ensure_schema()

Creates config tables if they don't exist.

=cut

sub ensure_schema {
    my ($self) = @_;
    my $dbh = $self->dbh;

    $dbh->do(<<'SQL');
CREATE TABLE IF NOT EXISTS config (
    name VARCHAR PRIMARY KEY,
    value VARCHAR
)
SQL

    $dbh->do(<<'SQL');
CREATE TABLE IF NOT EXISTS config_hierarchy (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    p_id INTEGER REFERENCES config_hierarchy(id),
    name VARCHAR NOT NULL,
    type VARCHAR NOT NULL,
    UNIQUE(p_id, name)
)
SQL

    $dbh->do(<<'SQL');
CREATE TABLE IF NOT EXISTS config_host (
    hierarchy_id INTEGER REFERENCES config_hierarchy(id),
    name VARCHAR,
    value VARCHAR,
    PRIMARY KEY (hierarchy_id, name)
)
SQL

    $dbh->do(<<'SQL');
CREATE TABLE IF NOT EXISTS config_override (
    ds_id INTEGER,
    name VARCHAR,
    value VARCHAR,
    PRIMARY KEY (ds_id, name)
)
SQL

    $dbh->do(<<'SQL');
CREATE TABLE IF NOT EXISTS config_glob (
    pattern VARCHAR NOT NULL,
    context VARCHAR NOT NULL,
    name VARCHAR NOT NULL,
    value VARCHAR,
    PRIMARY KEY (pattern, context, name)
)
SQL

    return;
}

=head1 GLOBAL CONFIG

=head2 insert_global($name, $value)

Insert or replace a global config setting.

=cut

sub insert_global {
    my ($self, $name, $value) = @_;
    my $dbh = $self->dbh;

    $dbh->do(
        'INSERT OR REPLACE INTO config (name, value) VALUES (?, ?)',
        undef, $name, $value
    );

    return;
}

=head2 get_global($name)

Get a global config value. Returns undef if not set.

=cut

sub get_global {
    my ($self, $name) = @_;
    my $dbh = $self->dbh;

    my ($value) = $dbh->selectrow_array(
        'SELECT value FROM config WHERE name = ?',
        undef, $name
    );

    return $value;
}

=head2 get_all_global()

Returns hashref of all global settings.

=cut

sub get_all_global {
    my ($self) = @_;
    my $dbh = $self->dbh;

    my $sth = $dbh->prepare('SELECT name, value FROM config');
    $sth->execute();

    my %config;
    while (my ($name, $value) = $sth->fetchrow_array) {
        $config{$name} = $value;
    }

    return \%config;
}

=head1 HIERARCHY (GROUPS AND HOSTS)

=head2 ensure_hierarchy($path_arrayref)

Ensure hierarchy path exists. Returns the leaf hierarchy_id.

$path_arrayref is ['group', 'host'] or ['group', 'group', 'host'] etc.

=cut

sub ensure_hierarchy {
    my ($self, $path) = @_;
    my $dbh = $self->dbh;

    my $p_id = undef;

    for my $i (0 .. $#$path) {
        my $name = $path->[$i];
        my $type = ($i == $#$path) ? 'host' : 'group';

        # Try to find existing
        my ($id) = $dbh->selectrow_array(
            'SELECT id FROM config_hierarchy WHERE p_id IS ? AND name = ?',
            undef, $p_id, $name
        );

        unless (defined $id) {
            $dbh->do(
                'INSERT INTO config_hierarchy (p_id, name, type) VALUES (?, ?, ?)',
                undef, $p_id, $name, $type
            );
            $id = $dbh->last_insert_id(undef, undef, 'config_hierarchy', 'id');
        }

        $p_id = $id;
    }

    return $p_id;
}

=head2 get_hierarchy_id($path_arrayref)

Get hierarchy_id for a path. Returns undef if not found.

=cut

sub get_hierarchy_id {
    my ($self, $path) = @_;
    my $dbh = $self->dbh;

    my $p_id = undef;

    for my $name (@$path) {
        my ($id) = $dbh->selectrow_array(
            'SELECT id FROM config_hierarchy WHERE p_id IS ? AND name = ?',
            undef, $p_id, $name
        );

        return unless defined $id;
        $p_id = $id;
    }

    return $p_id;
}

=head1 HOST SETTINGS

=head2 insert_host_setting($hierarchy_id, $name, $value)

Insert or replace a host setting.

=cut

sub insert_host_setting {
    my ($self, $hierarchy_id, $name, $value) = @_;
    my $dbh = $self->dbh;

    $dbh->do(
        'INSERT OR REPLACE INTO config_host (hierarchy_id, name, value) VALUES (?, ?, ?)',
        undef, $hierarchy_id, $name, $value
    );

    return;
}

=head2 get_host_setting($hierarchy_id, $name)

Get a host setting value. Returns undef if not set.

=cut

sub get_host_setting {
    my ($self, $hierarchy_id, $name) = @_;
    my $dbh = $self->dbh;

    my ($value) = $dbh->selectrow_array(
        'SELECT value FROM config_host WHERE hierarchy_id = ? AND name = ?',
        undef, $hierarchy_id, $name
    );

    return $value;
}

=head2 get_all_host_settings($hierarchy_id)

Returns hashref of all settings for a host.

=cut

sub get_all_host_settings {
    my ($self, $hierarchy_id) = @_;
    my $dbh = $self->dbh;

    my $sth = $dbh->prepare(
        'SELECT name, value FROM config_host WHERE hierarchy_id = ?'
    );
    $sth->execute($hierarchy_id);

    my %settings;
    while (my ($name, $value) = $sth->fetchrow_array) {
        $settings{$name} = $value;
    }

    return \%settings;
}

=head1 FIELD OVERRIDES

=head2 insert_override($ds_id, $name, $value)

Insert or replace a field-level override (wins over node data).

=cut

sub insert_override {
    my ($self, $ds_id, $name, $value) = @_;
    my $dbh = $self->dbh;

    $dbh->do(
        'INSERT OR REPLACE INTO config_override (ds_id, name, value) VALUES (?, ?, ?)',
        undef, $ds_id, $name, $value
    );

    return;
}

=head2 get_override($ds_id, $name)

Get a field override. Returns undef if not set.

=cut

sub get_override {
    my ($self, $ds_id, $name) = @_;
    my $dbh = $self->dbh;

    my ($value) = $dbh->selectrow_array(
        'SELECT value FROM config_override WHERE ds_id = ? AND name = ?',
        undef, $ds_id, $name
    );

    return $value;
}

=head1 GLOB PATTERNS

=head2 insert_glob($pattern, $context, $name, $value)

Insert or replace a glob pattern setting.

=cut

sub insert_glob {
    my ($self, $pattern, $context, $name, $value) = @_;
    my $dbh = $self->dbh;

    $dbh->do(
        'INSERT OR REPLACE INTO config_glob (pattern, context, name, value) VALUES (?, ?, ?, ?)',
        undef, $pattern, $context, $name, $value
    );

    return;
}

=head2 match_glob($context, $name)

Get all glob settings matching a context and name.
Returns arrayref of [pattern, value] pairs.

=cut

sub match_glob {
    my ($self, $context, $name) = @_;
    my $dbh = $self->dbh;

    # Fetch all glob entries for this name and match in Perl.
    # The context column may itself be a glob (e.g. 'web;app*.com').
    my $sth = $dbh->prepare(
        'SELECT pattern, context, value FROM config_glob WHERE name = ?'
    );
    $sth->execute($name);

    my @matches;
    while (my ($pattern, $stored_ctx, $value) = $sth->fetchrow_array) {
        # Convert stored context glob to regex for matching
        my $re = quotemeta($stored_ctx);
        $re =~ s/\\\*/.*/g;
        $re =~ s/\\\?/./g;
        if ($context =~ /^$re$/) {
            push @matches, [$pattern, $value];
        }
    }

    return \@matches;
}

=head1 QUERY RESOLUTION

=head2 resolve_value($context, $key)

Resolve a config value with full cascade:

1. Exact match in hierarchy (most specific)
2. Glob match
3. Walk up hierarchy
4. Global default

$context is arrayref like ['web', 'app1.com', 'cpu']

=cut

sub resolve_value {
    my ($self, $context, $key) = @_;
    my $dbh = $self->dbh;

    # 1. Exact match in hierarchy
    my $val = $self->_get_exact($context, $key);
    return $val if defined $val;

    # 2. Glob match
    $val = $self->_get_glob($context, $key);
    return $val if defined $val;

    # 3. Walk up hierarchy
    my @ctx = @$context;
    while (@ctx) {
        pop @ctx;
        $val = $self->_get_exact(\@ctx, $key);
        return $val if defined $val;
    }

    # 4. Global default
    return $self->get_global($key);
}

=head2 resolve_field_attr($ds_id, $attr, $node_value)

Resolve a field attribute with override cascade:

1. config_override (field-level from config files)
2. $node_value (node-reported, passed in)
3. config_hierarchy (host/group settings)
4. config (global defaults)

=cut

sub resolve_field_attr {
    my ($self, $ds_id, $attr, $node_value) = @_;

    # 1. config_override wins
    my $val = $self->get_override($ds_id, $attr);
    return $val if defined $val;

    # 2. Node-reported value (passed in by caller)
    return $node_value if defined $node_value;

    # 3. Fall back to hierarchy - caller must handle
    # 4. Fall back to global
    return $self->get_global($attr);
}

sub _get_exact {
    my ($self, $context, $key) = @_;
    my $dbh = $self->dbh;

    my $hid = $self->get_hierarchy_id($context);
    return unless defined $hid;

    return $self->get_host_setting($hid, $key);
}

sub _get_glob {
    my ($self, $context, $key) = @_;
    my $dbh = $self->dbh;

    # Build context string for matching
    my $ctx_str = join(';', @$context);

    # Get all glob patterns for this context
    my $matches = $self->match_glob($ctx_str, $key);

    # Return first match (could enhance with specificity)
    if (@$matches) {
        return $matches->[0][1];
    }

    return;
}

=head1 UTILITY

=head2 clear()

Delete all config data. For testing.

=cut

sub clear {
    my ($self) = @_;
    my $dbh = $self->dbh;

    $dbh->do('DELETE FROM config_glob');
    $dbh->do('DELETE FROM config_override');
    $dbh->do('DELETE FROM config_host');
    $dbh->do('DELETE FROM config_hierarchy');
    $dbh->do('DELETE FROM config');

    return;
}

1;

__END__

=head1 AUTHOR

Munin Team

=head1 LICENSE

GPLv2+

=cut
