.. index::
   triple: protocol; extension; cap
   pair: capability; cap

.. _plugin-protocol-dirtyconfig:

=================================
 Protocol extension: cap
=================================

The "config cap" capability is implemented in munin 3.0 and later.

Objective
---------

Reduce plugin execution time for node startup.

Description
-----------

When the node starts up, it launches every plugin once in order to
discover their capabilities:

#. if it is part of a virtual host (for example SNMP plugins)
#. if it requires a multigraph master (for example the diskstats plugin)

That information is almost always known immediatly to the plugin,
as item 1 is usually either set by the environment or the plugin symlink name
and item 2 is usually hardcoded in the plugin code.

Plugins therefore don't have to any time doing autoconfiguration yet to provide
that information. This is important as during its startup, the node will loop
sequentially over all the active plugins.  Any speedup is welcome, specially if
the node has thousands of plugins, such as a SNMP-rich one.

Network protocol
----------------

The network protocol is fully unchanged. It is purely a node-scoped
optimisation.

Plugin protocol
----------------

During the node startup, the plugin will be called with a "config cap" argument instead of "config".
The plugin can then reply with a reduced set of information, as the node will not use the full output.

Old behavior is still fully supported as we want to preserve backwards compatibility. It will simply not
benefit from any speedup.

sample plugin output
--------------------

When the `cap` subcommand is asked, the output can be *very* small.

::

   $ munin-run my_plugin config cap
   host_name remote.host.lan
   multigraph dummy

   $ munin-run my_plugin config
   host_name remote.host.lan
   multigraph my_plugin_1
   graph_title My Plugin 1
   graph_category sample
   field.label My Field
   multigraph my_plugin_2
   graph_title My Plugin 2
   graph_category sample
   field.label My Field
