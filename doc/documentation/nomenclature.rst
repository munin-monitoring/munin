==============
 Nomenclature
==============

To be able to use Munin, to understand the documentation, and - not to
be neglected - to be able to write documentation that is consistent
with Munin behavior, we need a common nomenclature.

Common terms
============

:Term: **Munin Master**
:Explanation: The central host/server where Munin gathers all data to. This machine runs munin-cron
:Synonyms: master


:Term: **Munin Node**
:Explanation: The daemon/network service running on each host to be contacted by the munin master to gather data.  Each node may monitor several hosts.  The Munin master will likely run a munin-node itself.
:Synonyms: In SNMP this might be called an agent.


:Term: **Plugin**
:Explanation: Each Munin node handles one or more plugins to monitor stuff on hosts
:Synonym: service


:Term: **Host**
:Explanation: A machine monitored by Munin, maybe by proxy on a munin node or via a snmp plugin
:Synonym: N/A


:Term: **Field**
:Explanation: Each plugin presents data from one or more data sources.  Each found, read, calculated value corresponds to a field.attribute tuple
:Synonym: Data source


:Term: **Attribute**
:Explanation: Description found in output from plugins, both general (global) to the plugin and also specific to each field
:Synonym: N/A


:Term: **Directive**
:Explanation: Statements used in configuration files like munin.conf, munin-node.conf and plugin configuration directory (/etc/munin/plugin-conf.d/).
:Synonym: N/A


:Term: **Environment variable**
:Explanation: Set up by munin-node, used to control plugin behaviour, found in plugin configuration directory (/etc/munin/plugin-conf.d/)
:Synonym: N/A


:Term: **Global (plugin) attributes**
:Explanation: Used in the global context in a plugin's configuration output. NB: The attribute is considered "global" only to the plugin (and the node) and only when executed.
:Synonym:


:Term: **Datasource-specific plugin attributes**
:Explanation: Used in the datasource-specific context in a plugin's output.
:Synonym: N/A


:Term: **Node-level directives**
:Explanation: Used in munin.conf.
:Synonym:


:Term: **Group-level directives**
:Explanation: Used in munin.conf.
:Synonym:


:Term: **Field-level directives**
:Explanation: Used in munin.conf.
:Synonym:


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


The relation between directives and attributes
===============================================

Attributes
  A plugin has a given set of data sources, and the data sources present themselves
  through a defined set of field.attributes with corresponding values.
  From a Munin administrator's point of view, these (the names of the fields and attributes) 
  should not be changed as they are part of how the plugins work. 

Directives
  The configuration files, however, are the administrator's domain.
  Here, the administrator may -- through directives -- control the plugins' behavior
  and even override the plugin's attributes if so desired. 
  As such, directives (in configuration files) may override attributes (in plugins). 

The distinction between *attributes* and *directives* defines an
easily understandable separation between how the (for many people) 
shrink-wrapped plugins and the editable configuration files.
