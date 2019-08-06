==============
 Nomenclature
==============

To be able to use Munin, to understand the documentation, and - not to
be neglected - to be able to write documentation that is consistent
with Munin behaviour, we need a common nomenclature.

Common terms
============

+--------------+--------------------------------------------+------------------------------+
| Term         | Explanation                                | Also referred to as as       |
+==============+============================================+==============================+
| Munin Master | The central host / server where Munin      | master, server, munin server |
|              | gathers all data.                          |                              |
|              | The machine runs munin-cron                |                              |
+--------------+--------------------------------------------+------------------------------+
| Munin Node   | The daemon /  network service running      | In SNMP terms                |
|              | on each host to be contacted by the        | it may be called an          |
|              |                                            | agent.                       |
+--------------+--------------------------------------------+------------------------------+
| Plugin       | Each munin node handles one or more        | service                      |
|              | plugins to monitor stuff on hosts          |                              |
+--------------+--------------------------------------------+------------------------------+
| Host         | A machine monitored by Munin,              |                              |
|              | maybe by proxy on a munin node,            |                              |
|              | or via a SNMP plugin                       |                              |
+--------------+--------------------------------------------+------------------------------+
| Field        | Each plugin presents data from one         | Data source                  |
|              | or more data sources. Each found,          |                              |
|              | read or calculated value corresponds       |                              |
|              | to a field.attribute tuple.                |                              |
+--------------+--------------------------------------------+------------------------------+
| Attribute    | Description found in output from plugins,  |                              |
|              | both general (global) to the plugin, and   |                              |
|              | also specific for each Field.              |                              |
+--------------+--------------------------------------------+------------------------------+
| Environment  | Set up by munin node, used to control      |                              |
| variable     | plugin behaviour.  Found in the plugin     |                              |
|              | configuration directory.                   |                              |
|              | (/etc/munin/plugin-conf.d/)                |                              |
+--------------+--------------------------------------------+------------------------------+
| Global       | Used in the global context in the          |                              |
| (plugin)     | configuration output from a plugin.        |                              |
| attribute    | (Note: The attribute is considered         |                              |
|              | "global" only to the plugin (and the       |                              |
|              | node), and only when executed.             |                              |
+--------------+--------------------------------------------+------------------------------+
| Datasource   | Used in the datasource-specific context in |                              |
| specific     | the output of a plugin                     |                              |
| plugin       |                                            |                              |
| attribute    |                                            |                              |
+--------------+--------------------------------------------+------------------------------+
| Global       | Used in munin.conf                         |                              |
| directive    |                                            |                              |
+--------------+--------------------------------------------+------------------------------+
| Node level   | Used in munin.conf                         |                              |
| directive    |                                            |                              |
+--------------+--------------------------------------------+------------------------------+
| Group level  | Used in munin.conf                         |                              |
| directive    |                                            |                              |
+--------------+--------------------------------------------+------------------------------+
| Field level  | Used in munin.conf                         |                              |
| directive    |                                            |                              |
+--------------+--------------------------------------------+------------------------------+


Examples
========

To shed some light on the nomenclature, consider the examples below:

Global plugin attribute
-----------------------

Global plugin attributes are in the plugins output when run with the
config argument. The full list of these attributes is found on the
protocol config page. This output does not configure the plugin, it
configures the plugins graph.

::

    graph_title Load average
    ----------- ------------
         |           `------ value
         `------------------ attribute


Datasource specific plugin attribute
------------------------------------

These are found both in the config output of a plugin and in the
normal readings of a plugin. A plugin may provide data from one or
more data sources. Each data source needs its own set of
field.attribute tuples to define how the data source should be
presented.

::

    load.warning 100
    ---- ------- ---
      |     |     `- value
      |     `------- one of several attributes used in config output
      `------------- field

    load.value 54
    ---- ----- --
      |    |    `- value
      |    `------ only attribute when getting values from a plugin
      `----------- field

Configuration files
-------------------

This one is from the global section of munin.conf:

::

    dbdir       /var/lib/munin/
    -----       ---------------
      |                `--------- value
      `-------------------------- global directive


And then one from the node level section:

::

    [foo.example.org]
      address localhost
      ------- ---------
         |        `----- value
         `-------------- node level directive
