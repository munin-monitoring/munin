.. _tutorial-using-munin:

====================================
 Using Munin Day to Day
====================================

This page covers the practical aspects of working with Munin once it is
installed and collecting data.

Reading Graphs
==============

Munin graphs show data over time. The default view shows the last 24 hours.
You can switch between time ranges using the links at the top of each graph:

- **hour** — last 60 minutes (5-minute resolution)
- **day** — last 24 hours (5-minute resolution)
- **week** — last 7 days (30-minute resolution)
- **month** — last 31 days (2-hour resolution)
- **year** — last 12 days (1-day resolution)

Understanding Graph Types
--------------------------

**Counter / Derive graphs** (network traffic, disk I/O)
   These show rates — bytes per second, operations per second, etc. The
   Y-axis label says "per second" or "per minute" depending on the
   ``graph_period`` setting. Values represent the rate of change since
   the last measurement.

   If you see a flat line at zero, the counter may have been reset or
   the data type may be wrong. If you see sudden spikes, the counter
   may have wrapped or been reset.

**Gauge graphs** (temperature, load, disk usage)
   These show absolute values — degrees, percentage, number of processes.
   The Y-axis label shows the unit directly.

   If you see ``NaN`` (not a number), the plugin may have failed to
   produce a value, or RRDtool does not have enough data points yet.

**Stacked graphs** (disk usage by partition, traffic by interface)
   Multiple data sources are stacked on top of each other. The total
   height represents the sum. Click on a graph to see the individual
   components.

Understanding Colors
---------------------

- **Green** — normal values within thresholds
- **Yellow** — values above the warning threshold
- **Red** — values above the critical threshold
- **Grey** — unknown or missing data

The warning and critical thresholds are set by the plugin or overridden
in ``munin.conf``. See :ref:`tutorial-alert` for details.

Working with Thresholds
========================

Munin plugins define default warning and critical thresholds. You can
override these in ``/etc/munin/munin.conf`` on the master.

Setting Thresholds
------------------

To set a warning level for a specific data source on a specific host:

::

  [webserver.example.com]
    address 192.0.2.10
    cpu.user.warning 80
    cpu.user.critical 95

This sets a warning at 80% and critical at 95% for the ``user`` field
of the ``cpu`` plugin on ``webserver.example.com``.

To set thresholds for all hosts in a group:

::

  [webservers;]
    cpu.user.warning 80

Threshold Syntax
-----------------

A single number sets the upper limit:

::

  cpu.user.warning 80

A colon-separated pair defines a range. Values outside the range trigger
the alert:

::

  cpu.user.warning 20:80

This warns when the value is below 20 or above 80.

Checking Current Thresholds
----------------------------

To see what thresholds are currently set for a plugin:

.. code-block:: bash

   sudo munin-run cpu config

Look for lines like ``cpu.user.warning`` and ``cpu.user.critical``.

Managing Nodes
===============

Adding a New Node
------------------

1. Install ``munin-node`` on the new machine.

2. Edit ``/etc/munin/munin-node.conf`` on the new node and add the
   master's IP to the ``allow`` list.

3. Restart ``munin-node`` on the new machine.

4. Add a section for the new node in ``/etc/munin/munin.conf`` on the
   master:

   ::

     [newserver.example.com]
       address 192.0.2.20

5. Wait for the next ``munin-cron`` run (up to 5 minutes), or run it
   manually:

   .. code-block:: bash

      sudo -u munin /usr/share/munin/munin-cron

Removing a Node
----------------

1. Remove or comment out the node's section in ``/etc/munin/munin.conf``.

2. The RRD files in ``/var/lib/munin/`` are not automatically removed.
   You can delete them manually if desired.

3. Optionally uninstall ``munin-node`` from the removed machine.

Organizing with Groups
-----------------------

Munin uses groups to organize nodes in the web interface. Groups are
defined by the hierarchy in ``munin.conf``:

::

  [dc1;web;web1.example.com]
    address 192.0.2.10

  [dc1;web;web2.example.com]
    address 192.0.2.11

  [dc1;db;db1.example.com]
    address 192.0.2.20

This creates a hierarchy: ``dc1`` → ``web`` → ``web1``, ``dc1`` → ``db`` → ``db1``.

If you use a simple hostname without a semicolon, the domain part becomes
the group:

::

  [web1.example.com]
    address 192.0.2.10

This places ``web1.example.com`` in the group ``example.com``.

Adding Plugins
===============

Installing a Plugin
--------------------

1. Place the plugin script in ``/usr/share/munin/plugins/`` (or any
   directory you prefer).

2. Make it executable:

   .. code-block:: bash

      chmod +x /usr/share/munin/plugins/myplugin

3. Create a symlink in ``/etc/munin/plugins/``:

   .. code-block:: bash

      ln -s /usr/share/munin/plugins/myplugin /etc/munin/plugins/myplugin

4. Restart ``munin-node``:

   .. code-block:: bash

      sudo systemctl restart munin-node

5. Test the plugin:

   .. code-block:: bash

      sudo munin-run myplugin
      sudo munin-run myplugin config

Using Wildcard Plugins
-----------------------

Wildcard plugins monitor multiple instances of the same thing (network
interfaces, disk drives, etc.). They use the symlink name to determine
what to monitor.

For example, the ``if_`` plugin monitors network interfaces:

.. code-block:: bash

   ln -s /usr/share/munin/plugins/if_ /etc/munin/plugins/if_eth0
   ln -s /usr/share/munin/plugins/if_ /etc/munin/plugins/if_eth1

See :ref:`tutorial-plugins-wildcard` for details.

Configuring Plugin Environment
-------------------------------

Some plugins need environment variables (database credentials, SNMP
communities, etc.). Set these in ``/etc/munin/plugin-conf.d/``:

::

  [myplugin]
    env.DB_HOST localhost
    env.DB_USER munin
    env.DB_PASS secret

See :ref:`plugin-conf.d` for the full configuration reference.

Checking Munin's Health
========================

Log Files
----------

Munin writes logs to ``/var/log/munin/``:

- ``munin-update.log`` — data collection from nodes
- ``munin-limits.log`` — threshold checks and alerts
- ``munin-httpd.log`` — web interface requests (if logging is enabled)

Check these logs if something is not working as expected.

Quick Health Check
-------------------

Run this to verify the master can reach a node and collect data:

.. code-block:: bash

   sudo -u munin /usr/share/munin/munin-update --debug --nofork --host <node-address> --service <plugin-name>

This shows the full communication between master and node.

Verifying Data Collection
--------------------------

To check that data is being written to RRD files:

.. code-block:: bash

   rrdtool fetch /var/lib/munin/<domain>/<host>-<plugin>-<field>-g.rrd AVERAGE | tail -5

This shows the last 5 data points for the specified field.
