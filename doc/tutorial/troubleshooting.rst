.. _tutorial-troubleshooting:

================
Troubleshooting
================

This page lists some general troubleshooting strategies and methods for Munin.


Check node agent
================

Is the :ref:`munin-node` process (daemon) running on the host you want to monitor?

Did you restart the :ref:`munin-node` process after you made changes to its configuration?


Check connectivity
==================

The examples show a :ref:`munin-node` agent running on 127.0.0.1; replace it with your node address.

.. note::

  You can use `netcat <http://netcat.sourceforge.net/>`_ to port 4949.

  Using ``telnet`` was the previous recommended way as it was a fairly standard install.
  We don't recommend it anymore since ``netcat`` is now almost as ubiquitous as ``telnet``
  and it offers a real native TCP connection, whereas ``telnet`` 
  `does not <http://stackoverflow.com/questions/12730293/how-does-telnet-differ-from-a-raw-tcp-connection>`_. 
  Note that using `socat` also works perfectly, but it is not as mainstream.


Does the :ref:`munin-node` agent allow connections from your munin master?

Here we try to connect manually to the :ref:`munin-node` that runs on the Munin master host. It can be reached via IP address ``127.0.0.1`` or hostname ``localhost`` and port ``4949``. 

Output of a ``netcat`` session should be something like this:

::

  # nc localhost 4949
  Trying 127.0.0.1...
  Connected to localhost.
  Escape character is '^]'.
  # munin node at [your hostname]

Does the above output give the same hostname that should be expected upon configuration in :ref:`munin.conf`?

.. note::

 If you have a fully qualified domain name (FQDN) in :ref:`munin-node.conf`, the host you're monitoring has to identify itself with FQDN as well.


E.g. if the masters node tree has the following entry:

::

  [foo.example.com]
    address foo.example.com

...then a netcat session to the node should give you the following output:

::

  # munin node at foo.example.com


.. note::

 If the connection test fails, check the :ref:`allow directive <initial_configuration>` in :ref:`munin-node.conf` and make sure any firewalls allow contact on destination port 4949.

.. _debugging-plugins:

Debugging Plugins
=======================

Which plugins are enabled on the node?
--------------------------------------

Does :ref:`munin-node` recognize any plugins? Try issuing the command ``list`` (being connected to the agent) and a (long) list of plugins should show.

::

  # nc localhost 4949
  Trying 127.0.0.1...
  Connected to localhost.
  Escape character is '^]'.
  # munin node at foo.example.com
  list
  open_inodes irqstats if_eth0 df uptime [...]

Check a particular plugin
-------------------------

**Check on agent host**

.. note::

 All the commands here need to be run as user ``root``. A common method of becoming ``root`` is via the ``sudo`` command, but refer to your local documentation for a more specific instruction.

Restart :ref:`munin-node`, as it only reads the plugin list upon start. (Good to test a plugin with :ref:`munin-run`, without enabling it right away.)

::

  /etc/init.d/munin-node restart

Call :ref:`munin-run` on the monitored host to see whether the plugin runs through . 

Try with and without the ``config`` plugin argument. Both runs should not emit any error message. 

.. note::

 You can also use the ``--debug`` flag, as it shows if the configuration file 
 is correctly parsed, mostly for UID & environment variables.

Regular run:

::

  # munin-run df
  _dev_hda1.value 83

Config run:

::

  # munin-run df config
  graph_title Filesystem usage (in %)
  graph_args --upper-limit 100 -l 0
  graph_vlabel %
  graph_category disk
  graph_info This graph shows disk usage on the machine.
  _dev_hda1.label /
  _dev_hda1.info / (ext3) -> /dev/hda1
  _dev_hda1.warning 92
  _dev_hda1.critical 98


**Check from Munin master**


Does the plugin run through :ref:`munin-node`, with and without config? 

Regular run:

::

  # nc foo.example.com 4949
  Trying foo.example.com...
  Connected to foo.example.com.
  Escape character is '^]'.
  # munin node at foo.example.com
  fetch df
  _dev_hda1.value 83
  [...]
  .

With config:

::

  # nc foo.example.com 4949
  Trying foo.example.com...
  Connected to foo.example.com.
  Escape character is '^]'.
  # munin node at foo.example.com
  config df
  graph_title Filesystem usage (in %)
  graph_args --upper-limit 100 -l 0
  graph_vlabel %
  graph_category disk
  graph_info This graph shows disk usage on the machine.
  _dev_hda1.label /boot
  _dev_hda1.info /boot (ext3) -> /dev/hda1
  _dev_hda1.warning 92
  _dev_hda1.critical 98
  [...]
  .

If the plugin works for ``munin-run`` but not through ``netcat``, you might have a ``$PATH`` problem. 

.. note::

 Set {{{env.PATH}}} for the plugin in the plugin's environment file.

Check Munin Master
==================

Do the directories specified by ``dbdir``, ``htmldir``, ``logdir`` and ``rundir`` defined in :ref:`munin.conf` have the correct permissions? (If you first run munin as root, maybe they're not readable/writeable by the user that runs the cron job)

Is :ref:`munin-cron` established as a cron controlled process, run as the Munin user?

Does the output when running :ref:`munin-update` as the Munin user on the server node show any errors?

Try running "``munin-cron  --debug > /tmp/munin-cron.debug``" and check the output file ``/tmp/munin-cron.debug``.

Check data collection
---------------------

This step will tell you whether :ref:`munin-update` (the master) is able to communicate with :ref:`munin-node` (the agent).

Run :ref:`munin-update` as user ``munin`` on the Munin master machine.

::

  # su -s /bin/bash munin
  $ /usr/share/munin/munin-update --debug --nofork --host foo.example.com --service df

You should get a line like this:

::

  Aug 11 22:39:51 - [6846] Updating /var/lib/munin/example.com/foo.example.com-df-_dev_hda1-g.rrd with 57

After this, replace ``df`` with the service you want to check, such as ``hddtemp_smartctl``.

If one of these steps does not work, something is probably wrong with the plugin or how :ref:`munin-node` talks to the plugin.

 #. Does the plugin run when executed directly? If it runs when executed as root and not through :ref:`munin-run` (as described above), the plugin has a permission problem. See this `article on environment files <http://munin-monitoring.org/wiki/munin-node_behaviour_file>`_.

 #. Does the plugin output contain too few, too many and/or illegal characters?

 #. Does Munin (:ref:`munin-cron` and its children) write values into RRD files? Hint: ``rrdtool fetch [rrd file] AVERAGE``

 #. Does the plugin use legal field names?  See :ref:`Notes on Field names <notes-on-fieldnames>`.

 #. In case you `loan data <http://munin-monitoring.org/wiki/LoaningData>`_ from other graphs, check that the `fieldname.type <http://munin-monitoring.org/wiki/fieldname.type>`_ is set properly. See `Munin file names <http://munin-monitoring.org/wiki/MuninFileNames>`_ for a quick reference on what any error messages in the logs might indicate.


Frequent Incidents
==================

SELinux blocks Munin plugins
----------------------------

 * See `the documentation start page <http://munin-monitoring.org/wiki/Documentation#ThirdPartyArticles/Documents>`_ for links to SELinux rules for Munin.

RRD files are filled with 0
---------------------------------------------------------------------

although munin-node seems to show sane values.

 * The plugin's output shows GAUGE values, but were declared as COUNTER or DERIVE in the plugin's config. 

.. note::

  GAUGE is the default data type in Munin! Any other data type for a field must be explicitly declared.

RRD files are filled with ``NaN``
---------------------------------------------------------------------------

although munin-node seems to show sane values.

 * Check that there are no invalid characters in the plugin's output.
 * For new plugins let munin gather data for about 20 minutes and things will unwrinkle

munin-node won't give any data
----------------------------------------------------------

although it is configured properly.

 * Check that there is a ``.value`` directive for every of the plugin's field names (yes, I managed to forget that recently).

munin-node only temporary returns valid data
--------------------------------------------

 * Check that no race conditions occur. A typical race condition is updating a file with crontab while the plugin is trying to read the file.

The graphs are empty
--------------------

 * The plugin's output shows GAUGE values, but were declared as COUNTER or DERIVE in the plugin's config. (GAUGE is default data type in Munin)
 * The files to be updated by Munin are owned by root or another user account
 * The local user browser cache may be corrupt, especially if "most" graphs are displayed correctly and "some" graphs are blank. In Firefox (or your browser of choice) go to tools and clear recent history, then check to see if the graphs are now properly displayed.

Other mumbo-jumbo
-----------------

 * Run the different stages in :ref:`munin-cron` manually, using ``--debug``, ``--nofork``, something like this:

::

  # su - munin -c "/usr/lib/munin/munin-update \
      --debug --nofork \
      --host foo.example.com \
      --service df"


See also
========

 * `No Graph FAQ <http://munin-monitoring.org/wiki/FAQ_no_graphs>`_
 * :ref:`Upgrade notes <upgrade>`
