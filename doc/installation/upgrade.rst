.. _upgrade:

===============
 Upgrade Notes
===============

Database schema upgrades
========================

Schema changes to munin's SQL database are applied by a dedicated
offline tool, ``munin-upgrade-db``, invoked once during package
upgrade -- never by the running daemons.  The administrator stops
Munin, upgrades, restarts; the tool runs in between and its outcome
is verified before any daemon touches data.

Runtime code verifies the schema version at every database handle
(``Munin::Master::Update::get_dbh``) and dies with an actionable
message on any mismatch: daemons never repair, migrate or guess.  A
mismatch is always fatal for a running process -- running against a
stale schema risks silent data corruption.

The schema version is tracked in the ``version_history`` table: one
row per applied migration step (version, unix epoch, human-readable
comment).  Failure messages cite the newest entry, so a mismatch
report immediately shows what the database last went through.

Downstream packagers own the postinst wiring.  The contract they must
honor (a non-zero exit must fail the package upgrade -- starting new
daemons against an old schema is the data-corruption scenario this
exists to prevent):

.. code-block:: sh

    # Debian: debian/munin-common.postinst, after unpack, before services start
    if command -v munin-upgrade-db >/dev/null 2>&1; then
        munin-upgrade-db --check >/dev/null 2>&1 || munin-upgrade-db
    fi

``munin-upgrade-db --check`` exits 0 when the schema is current, 2
when an upgrade is needed and 1 on error/incompatible databases, so
monitoring can also detect a pre-upgrade mismatch.  ``--yolo`` is an
explicit, admin-only escape hatch for ancient or hand-modified
databases (additive-only, verification still mandatory); it must NOT
be wired into automatic upgrades, and no runtime path may ever call
it.

Upgrading Munin from 2.0.x to 2.1.x
===================================

Munin HTTPD
-----------

:ref:`munin-httpd` replaces FastCGI.  It is a basic webserver capable
of serving pages and graphs.

To add transport layer security or authentication, use a webserver
with more features as a proxy.

If you choose to use :ref:`munin-httpd`, set :option:`graph_strategy`
and :option:`html_strategy` to "cgi".

FastCGI
-------

…is gone.  It was hard to set up, hard to debug, and hard to support.

Upgrading Munin from 1.x to 2.x
===============================

This is a compilation of items you need to pay attention to when
upgrading from Munin 1.x to munin 2.x

FastCGI
-------

Munin graphing is now done with FastCGI.

Munin HTML generation is optionally done with FastCGI.

Logging
-------

The web server needs write access to the munin-cgi-html and
munin-cgi-graph logs.
