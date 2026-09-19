.. _howto-remote-hosts:

====================================
How to monitor remote hosts
====================================

This howto covers the different ways to monitor hosts that are not
directly accessible from the Munin master.

Scenario 1: SSH Tunneling
==========================

If the master can reach the node's network via SSH but not directly,
use SSH tunneling.

On the master, add to ``/etc/munin/munin.conf``:

::

   [remote-server.example.com]
     address ssh://bastion.example.com/bin/nc remote-server.example.com 4949

This tells munin-update to connect to ``bastion.example.com`` via SSH
and then ``nc`` to the remote node on port 4949.

Configure SSH keys so the ``munin`` user can connect without a
password. See the :ref:`SSH transport examples <example-transport-ssh>`
for details.

Scenario 2: Port Forwarding
============================

If you can set up port forwarding on a firewall or NAT device,
forward port 4949 on the intermediate host to the node's port 4949.

On the master, add to ``/etc/munin/munin.conf``:

::

   [remote-server.example.com]
     address 192.0.2.100
     port 5001

Where 192.0.2.100 is the intermediate host and 5001 is the forwarded port.

Scenario 3: Munin Async
========================

For nodes on unreliable or high-latency links, use ``munin-asyncd``.
This daemon runs on the node, collects data locally, and spools it.
The master retrieves the spooled data via SSH without waiting for
plugins to run.

On the node, install and configure ``munin-asyncd``:

.. code-block:: bash

   sudo apt-get install munin-async

Edit ``/etc/munin/munin-asyncd.conf`` if needed (the defaults usually work).

Start the daemon:

.. code-block:: bash

   sudo systemctl start munin-asyncd

On the master, configure the node to use async transport:

::

   [slow-node.example.com]
     address ssh://slow-node.example.com/usr/share/munin/munin-async

Scenario 4: SNMP via Proxy
===========================

To monitor devices that speak SNMP (routers, switches, printers) but
not Munin, use SNMP plugins on a Munin node that can reach the device.

See :ref:`tutorial-snmp` for the full setup.

Scenario 5: Bouncing via inetd/xinetd
======================================

If SSH is not available, you can use ``netcat`` via ``inetd`` or
``xinetd`` to forward connections.

On the intermediate host, add to ``/etc/services``:

::

   munin-server-a   5001/tcp

And in ``/etc/inetd.conf``:

::

   munin-server-a   stream  tcp     nowait  root  /usr/bin/nc /usr/bin/nc -w 30 remote-server 4949

On the master:

::

   [remote-server.example.com]
     address bouncer.example.com
     port 5001

.. note::

   In this setup, the node's ``allow`` list must accept connections from
   the bouncer's IP, not the master's IP.

Verifying Connectivity
=======================

From the master, test that you can reach the node:

.. code-block:: bash

   # Direct connection
   nc -z node.example.com 4949

   # Via SSH tunnel
   ssh bastion.example.com nc remote-server.example.com 4949

Then run a manual update:

.. code-block:: bash

   sudo -u munin /usr/share/munin/munin-update --debug --nofork --host remote-server.example.com
