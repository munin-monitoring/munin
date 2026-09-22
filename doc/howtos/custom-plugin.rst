.. _howto-custom-plugin:

=================================
How to add a custom plugin
=================================

This walkthrough shows how to create, install, and test a custom Munin
plugin from scratch.

Step 1: Write the Plugin
========================

Create a file called ``myapp_status`` with the following content:

.. code-block:: bash

   #!/bin/sh

   case "$1" in
       config)
           echo "graph_title My Application Status"
           echo "graph_args --base 1000 -l 0"
           echo "graph_vlabel requests/sec"
           echo "graph_category application"
           echo "graph_info This graph shows requests per second for MyApp."
           echo "requests.label requests"
           echo "requests.type DERIVE"
           echo "requests.min 0"
           echo "errors.label errors"
           echo "errors.type DERIVE"
           echo "errors.min 0"
           echo "errors.warning 10"
           echo "errors.critical 50"
           ;;
       *)
           # Read from a hypothetical log file or API
           # Replace these with your actual data collection logic
           requests=$(tail -n 100 /var/log/myapp/access.log | wc -l)
           errors=$(tail -n 100 /var/log/myapp/error.log | wc -l)
           echo "requests.value $requests"
           echo "errors.value $errors"
           ;;
   esac

Make it executable:

.. code-block:: bash

   chmod +x myapp_status

Step 2: Test Locally
=====================

Run the plugin from the command line to verify it works:

.. code-block:: bash

   # Test config output
   sudo munin-run --servicedir /path/to/dir myapp_status config

   # Test value output
   sudo munin-run --servicedir /path/to/dir myapp_status

Both commands should produce clean output with no errors.

Step 3: Install the Plugin
===========================

Copy the plugin to the system plugin directory:

.. code-block:: bash

   sudo cp myapp_status /usr/share/munin/plugins/myapp_status
   sudo chmod +x /usr/share/munin/plugins/myapp_status

Create a symlink to activate it:

.. code-block:: bash

   sudo ln -s /usr/share/munin/plugins/myapp_status /etc/munin/plugins/myapp_status

Step 4: Configure the Plugin (Optional)
========================================

If your plugin needs environment variables or special user/group
settings, create a configuration file:

.. code-block:: bash

   sudo vi /etc/munin/plugin-conf.d/myapp

Add:

::

   [myapp_status]
     env.LOG_DIR /var/log/myapp
     user www-data
     group www-data

Step 5: Restart and Verify
===========================

Restart munin-node to pick up the new plugin:

.. code-block:: bash

   sudo systemctl restart munin-node

Verify it works through the node:

.. code-block:: bash

   # Check the plugin list
   nc localhost 4949
   list

   # Test the plugin via the network
   nc localhost 4949
   config myapp_status
   fetch myapp_status

Step 6: Wait for Graphs
========================

After the next ``munin-cron`` run (up to 5 minutes), the plugin will
appear in the web interface. The first graph will show data once RRD
has enough data points (usually 2-3 collection cycles).

Key Points
==========

- Plugins must output ``key.value NUMBER`` for data and ``key value``
  for config.
- The ``config`` output must include ``graph_title``.
- Field names must match between ``config`` and value output.
- Use ``type DERIVE`` for counters, ``type GAUGE`` for absolute values.
- Set ``min 0`` for counters to avoid negative spikes on reset.
- Use ``munin-run`` to test before deploying.
