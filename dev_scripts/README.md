# Munin Developer Scripts

Scripts for local development and testing. All scripts source `common.sh` for shared paths.

## Quick Start

```bash
# Install dependencies (Debian/Ubuntu)
./deps

# Set up a full sandbox (node + master + plugins)
./install node

# Run everything in the foreground
./all

# Or run individual components
./start_munin-node
./start_munin-httpd
```

## Scripts

### Setup

| Script | Description |
|--------|-------------|
| `install` | Main sandbox installer. Modes: `clean`, `node`, `master`, `debug`, `lib` |
| `deps` | Install all Debian dependencies via apt-get |
| `noop` | C pause() program. Used as Docker CMD |

### Running

| Script | Description |
|--------|-------------|
| `run` | Run a munin binary from sandbox with perl -T and correct PERL5LIB |
| `all` | Run munin-node, munin-update loop, and munin-httpd together |
| `start_munin-node` | Start munin-node and tail the log |
| `stop_munin-node` | Stop munin-node via PID file |
| `restart_munin-node` | Stop + start munin-node |
| `start_munin-httpd` | Start httpd on port 4946 |
| `start_munin-sched` | Start the scheduler daemon |
| `stop_munin-sched` | Stop the scheduler via PID file |
| `start_rrdcached` | Start rrdcached with unix socket |

### Plugins

| Script | Description |
|--------|-------------|
| `plugin` | Run a single plugin. Usage: `plugin run <name>` or `plugin run_as <name> <user>` |
| `run_debug_node` | Dump config and run munin-node-debug |

### TLS

| Script | Description |
|--------|-------------|
| `enable_tls` | Set `tls paranoid` in both node and master configs |
| `disable_tls` | Set `tls disabled` in both configs |

### Database

| Script | Description |
|--------|-------------|
| `dump_sql` | Dump SQLite database to SQL text file |
| `empty_db.sql` | SQL to DELETE all rows from state database and VACUUM |

### RRDCached

| Script | Description |
|--------|-------------|
| `enable_rrdcached` | Write rrdcached config to sandbox |
| `disable_rrdcached` | Remove rrdcached config |

### Debugging

| Script | Description |
|--------|-------------|
| `disable_taint` | Remove `-T` flag from all sandbox binaries |
| `query_munin_node` | Send commands to munin-node via nc |

## Environment Variables

All scripts source `common.sh` which sets:

- `SANDBOX` - Path to sandbox directory
- `PERL5LIB` - Perl library path (includes lib/)
- `CONFDIR` - Config directory (sandbox/etc)
- `RUNDIR` - Runtime directory (sandbox/var/run)
- `PORT` - munin-node port (4949)
- `HTTP_PORT` - munin-httpd port (4946)
- `MUNIN_DBURL` - SQLite database URL

## Sample Config

See `nested-munin.conf.sample` for a config with nested groups for testing.
