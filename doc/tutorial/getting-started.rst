.. _tutorial-getting-started:

===============
 Getting Started
===============

This tutorial walks you through installing Munin, seeing your first graph,
and understanding what happened. It takes about 5 minutes.

.. note::

   This guide assumes a Debian/Ubuntu system. For other distributions,
   substitute ``yum`` or ``dnf`` for ``apt-get``. The concepts are the same.

Prerequisites
=============

You need two machines (or one machine acting as both master and node):

- **Master**: collects data and serves the web interface.
- **Node**: the machine being monitored (runs a small agent).

Both need network connectivity on TCP port 4949 (node) and 4948 (web interface).

Step 1: Install the Packages
=============================

On the **node** (the machine to monitor):

.. code-block:: bash

   sudo apt-get install munin-node

On the **master** (the machine that collects data):

.. code-block:: bash

   sudo apt-get install munin

This installs everything: the master, the web interface, and a node
so Munin can monitor itself.

Step 2: Allow the Master to Query the Node
===========================================

Edit ``/etc/munin/munin-node.conf`` on the **node**. Add the master's
IP address to the access list:

::

   allow ^127\.0\.0\.1$

Replace ``127.0.0.1`` with your master's actual IP if they are on
different machines. Then restart the node:

.. code-block:: bash

   sudo systemctl restart munin-node

Step 3: Tell the Master About the Node
=======================================

Edit ``/etc/munin/munin.conf`` on the **master**. Add a section for
the node you want to monitor:

::

   [myserver.example.com]
     address 127.0.0.1

Use the node's hostname or IP address. If you are monitoring the
master itself, ``127.0.0.1`` is correct.

Step 4: Wait for the First Data Collection
===========================================

Munin collects data every 5 minutes via cron. After installation,
``munin-cron`` is already set up. Wait 5 minutes, or run it manually
to speed things up:

.. code-block:: bash

   sudo -u munin /usr/share/munin/munin-cron

Step 5: View Your First Graph
==============================

Open a web browser and go to:

::

   http://localhost:4948/

You should see the Munin web interface with graphs for your machine.
Click on a host name, then a category (like "system"), then a service
(like "load") to see a graph.

What Just Happened?
====================

Here is what each component did:

1. **munin-node** (on the node) listened on port 4949 and waited for
   connections from the master.

2. **munin-update** (on the master) connected to the node, asked for
   a list of plugins, and ran each one to collect data. The data was
   stored in RRD files under ``/var/lib/munin/``.

3. **munin-limits** (on the master) checked the collected data against
   warning and critical thresholds.

4. **munin-httpd** (on the master) served the web interface on port 4948,
   generating graphs from the RRD files on demand.

Understanding the Plugin System
================================

Munin's power comes from its plugins. Each plugin is a small script that
knows how to collect one type of data (CPU load, disk usage, network
traffic, etc.).

You can see which plugins are active on a node by connecting to it:

.. code-block:: bash

   nc localhost 4949

Then type:

::

   list

You will get a list of plugin names like ``cpu``, ``load``, ``df``,
``if_``, and so on.

To see what a plugin outputs, use ``munin-run``:

.. code-block:: bash

   sudo munin-run load

This prints the current values:

::

   load.value 0.42

To see the plugin's configuration (graph title, labels, thresholds):

.. code-block:: bash

   sudo munin-run load config

Next Steps
==========

- :ref:`Add more nodes <tutorial-getting-started>` by installing
  ``munin-node`` on other machines and adding sections to ``munin.conf``.

- :ref:`Install additional plugins <plugin-use>` to monitor databases,
  web servers, and other services.

- :ref:`Set up alerts <tutorial-alert>` to get notified when values
  exceed thresholds.

- :ref:`Write your own plugin <plugin-writing>` to monitor anything
  that can be expressed as a number.

- Read the :ref:`Architecture <architecture-index>` section to understand
  how the components fit together.
