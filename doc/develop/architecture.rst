.. _develop-architecture:

=====================
 Code Architecture
=====================

This page describes the high-level structure of the Munin codebase
to help developers navigate the code.

Directory Layout
================

::

  munin/
  ├── lib/                    # Perl modules (the core library)
  │   ├── Munin/
  │   │   ├── Common/         # Shared utilities (TLS, config, logging)
  │   │   ├── Master/         # Master-side components
  │   │   ├── Node/           # Node-side components
  │   │   └── Plugin/         # Plugin helper modules
  │   └── Munin.pm            # Top-level module
  ├── script/                 # Executable scripts (installed to PATH)
  ├── plugins/                # Built-in plugins (organized by category)
  ├── t/                      # Test suite
  ├── doc/                    # Documentation (Sphinx/RST)
  ├── web/                    # Static web assets (CSS, JS, images)
  ├── dev_scripts/            # Developer sandbox tools
  ├── contrib/                # Contributed tools and plugins
  └── etc/                    # Sample configuration files

Key Modules
===========

Munin::Common::*
-----------------

Shared infrastructure used by both master and node:

- ``Config`` — base class for configuration parsing
- ``Defaults`` — installation paths and version (generated at build time)
- ``Logger`` — logging via Log::Dispatch
- ``TLS``, ``TLSClient``, ``TLSServer`` — TLS support
- ``Timeout`` — execution timeout handling
- ``Daemon`` — daemonization helpers
- ``SyncDictFile`` — synchronized dictionary file for spooling

Munin::Node::*
---------------

Node-side components:

- ``Server`` — the main node daemon (extends ``Net::Server::Fork``)
- ``Service`` — plugin execution, privilege dropping, environment setup
- ``Config`` — node configuration parsing (``munin-node.conf``)
- ``Session`` — per-connection session state
- ``OS`` — OS-level operations (permission checks, user/group resolution)
- ``SNMPConfig`` — SNMP plugin auto-configuration
- ``SpoolReader``, ``SpoolWriter`` — async spool I/O

Munin::Master::*
-----------------

Master-side components:

- ``Update`` — orchestrates data collection from nodes
- ``UpdateWorker`` — per-node data collection worker
- ``Worker`` — process management for parallel updates
- ``Config`` — master configuration parsing (``munin.conf``)
- ``ConfigDB`` — SQLite database for storing configuration and state
- ``ConfigParser`` — parses the ``munin.conf`` hierarchy
- ``Node`` — represents a remote node during update
- ``Group``, ``Host`` — configuration tree objects
- ``Limits`` — threshold checking and alert dispatch
- ``Graph`` — RRD graph generation
- ``HTML`` — HTML page generation
- ``Utils`` — miscellaneous utilities

Munin::Plugin::*
-----------------

Helper modules for plugin authors:

- ``Munin::Plugin`` — state file management, thresholds, utilities
- ``Munin::Plugin::SNMP`` — SNMP plugin framework
- ``Munin::Plugin::HTTP`` — HTTP plugin framework
- ``Munin::Plugin::Pgsql`` — PostgreSQL plugin framework
- ``Munin::Plugin::Framework`` — base framework for plugins

Data Flow
=========

::

  ┌─────────┐      ┌──────────┐      ┌─────────┐
  │  cron   │─────→│munin-    │─────→│munin-   │
  │         │      │update    │      │limits   │
  └─────────┘      └────┬─────┘      └────┬────┘
                        │                  │
                   ┌────▼─────┐      ┌────▼─────┐
                   │  node    │      │  alerts  │
                   │  plugins │      │          │
                   └──────────┘      └──────────┘

1. ``munin-cron`` invokes ``munin-update`` and ``munin-limits`` every 5 minutes.

2. ``munin-update`` connects to each node, runs plugins via the network
   protocol, and stores data in RRD files and the SQLite database.

3. ``munin-limits`` reads the database, checks thresholds, and dispatches
   alerts via configured contacts.

4. ``munin-httpd`` serves the web interface, generating graphs on demand
   from RRD files.

Plugin Execution
================

When ``munin-node`` receives a ``config`` or ``fetch`` command:

1. ``Munin::Node::Service::fork_service`` spawns a child process.
2. The child drops privileges to the configured user/group.
3. Environment variables are set (``MUNIN_PLUGSTATE``, ``MUNIN_CAP_*``, etc.).
4. The plugin script is executed via ``exec``.
5. stdout is captured and returned to the master.

The node caches the list of available plugins at startup. Restarting
``munin-node`` is required to pick up new plugins.

Building
========

::

  perl Build.PL       # Generate Build script
  ./Build             # Compile
  ./Build test        # Run tests
  ./Build install     # Install (as root)

For development, use the sandbox instead of installing system-wide::

  dev_scripts/install node    # Install into sandbox
  dev_scripts/start_munin-node
  dev_scripts/run munin-update
  dev_scripts/run munin-httpd

See :ref:`develop-environment` for the full development setup instructions.
