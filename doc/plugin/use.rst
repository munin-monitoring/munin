.. _plugin-use:

=====================
 Using munin plugins
=====================

.. index::
   pair: plugin; installing

Installing
==========

The default plugin directory is /etc/munin/plugins/.

To install a plugin, place it in the plugin directory, and make it
executable.

You can also place the plugin elsewhere, and install a symbolic link
in the plugin directory. All the plugins provided with munin are
installed in this way.

.. index::
   pair: plugin; configuration

Configuring
===========

The plugin configuration directory is /etc/munin/plugin-conf.d/. The
syntax is:

user <username>
  The user the plugin will run as.

  Default: munin

group <groupname>
  The group the plugin will run as

  Default: munin

env.variablename <variable content>
  Defines and exports an environment variable called "variablename"
  with the content set to <variable content>.

  There is no need to quote the variable content.

.. note::

   When configuring a munin plugin, add the least amount of extra
   privileges needed to run the plugin. For instance, do not run a
   plugin with "user root" to read syslogs, when it may be sufficient
   to set "group adm" instead.

Example:

.. index::
   triple: example; plugin; configuration

::

   [pluginname]
   user             username
   group            groupname
   env.variablename some content for the variable
   env.critical     92
   env.warning      95

Plugin configuration is optional.

.. index::
   pair: plugin; testing

Testing
=======

To test if the plugin works when executed by munin, you can use the
:ref:`munin-run` command.

.. code-block:: bash

   # munin-run myplugin config

   # munin-run myplugin


Download munin plugins
======================

The munin project maintains a set of core plugins that are distributed in munin's releases.
Additionally the munin project maintains the
`contrib <https://github.com/munin-monitoring/contrib>`_ repository. It contains more than a
thousand plugins contributed by a wide range of people.
In order to use these plugins they can either be downloaded manually or managed via the
:ref:`munin-get` plugin tool.

Additionally the munin plugins in the `contrib <https://github.com/munin-monitoring/contrib>`_
repository can be browsed via the `Munin Plugin Gallery <http://gallery.munin-monitoring.org>`_.
