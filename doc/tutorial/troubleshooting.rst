.. _tutorial-troubleshooting:

================
Troubleshooting
================

This page lists some general troubleshooting strategies and methods for Munin.

The examples show a munin-node agent running on 127.0.0.1; replace it with your node address.


Check node agent
================

 #. Is the :ref:`munin-node` process (daemon) running on the host you want to monitor?

 #. Did you restart the :ref:`munin-node` process after you made changes to its configuration?


Check master to node connectivity
=================================

Does the :ref:`munin-node` agent allow connections from your munin master?

.. note::

 If the connection test (see example below) fails, check the :ref:`allow directive <initial_configuration>` in :ref:`munin-node.conf` and make sure any firewalls allow contact on destination port 4949.

Here we try to connect manually to the ``munin-node`` that runs on the Munin master host. It can be reached via IP address ``127.0.0.1`` or hostname ``localhost`` and port ``4949``. 

Output of a ``telnet`` session should be something like this:

::

  # telnet localhost 4949
  Trying 127.0.0.1...
  Connected to localhost.
  Escape character is '^]'.
  # munin node at [your hostname]

Does the above output give the same hostname that should be expected upon configuration in :ref:`munin.conf`?

E.g. if the masters node tree has the following entry:

::

  [foo.example.com]
    address foo.example.com

...then a telnet session to the node should give you the following output:

::

  # munin node at foo.example.com


.. note::

 If you have a fully qualified domain name (FQDN) in :ref:`munin-node.conf`, the host you're monitoring has to identify itself with FQDN as well.


Check Plugins
=============

Does :ref:`munin-node` recognize any plugins? Try issuing the command ``list`` when telnetting to the agent, and a (long) list of plugins should show.

::

  # telnet localhost 4949
  Trying 127.0.0.1...
  Connected to localhost.
  Escape character is '^]'.
  # munin node at foo.example.com
  list
  open_inodes irqstats if_eth0 df uptime [...]

If you're troubleshooting one particular plugin, test it on the Munin node machine with command ":ref:`munin-run` ``<plugin_name>``" called by user ``root``.


Check Munin Master
==================

Do the directories specified by ``dbdir``, ``htmldir``, ``logdir`` and ``rundir`` defined in :ref:`munin.conf` have the correct permissions? (If you first run munin as root, maybe they're not readable/writeable by the user that runs the cron job)

Is :ref:`munin-cron` established as a cron controlled process, run as the Munin user?

Does the output when running :ref:`munin-update` as the Munin user on the server node show any errors?

Try running "``munin-cron  --debug > /tmp/munin-cron.debug``" and check the output file ``/tmp/munin-cron.debug``.

See Also
========

 * `No Graph FAQ <http://munin-monitoring.org/wiki/FAQ_no_graphs>`_
 * :ref:`Upgrade notes <upgrade>`
