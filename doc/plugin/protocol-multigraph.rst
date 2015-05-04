.. _plugin-protocol-multigraph:

.. index::
   triple: protocol; extension; multigraph
   pair: capability; multigraph

=====================================================
 Protocol extension: multiple graphs from one plugin
=====================================================

Multigraph plugins are implemented in 1.4.0 and on.

Objective
---------

The object of this extension is to help with one issue:

- Quite a few plugins could after execution with very little additional overhead report on several measurable aspects of whatever it is examining. In these cases it will be cheaper to execute one plugin once to produce multiple graphs instead of executing multiple plugins to generate the same graphs.

This one-plugin one-graph property has resulted in the ``if_`` and ``if_err_`` plugins which are basically the same - almost identical code being maintained twice instead of once.  The sensors plugins which reports on temperatures, fan speeds and voltages - running one ``sensors`` command each time (a slow executing program) or caching the results.  There are several plugins that cache execution results because of this.

In all we should be able to maintain fewer plugins with less complexity than we are able to now.

Network protocol
----------------

A server that is capable of handling "multigraph" output MUST announce this to the node - otherwise the node MUST only announce and give access to single-graph plugins.

::

   > # munin node at lookfar.langfeldt.net
   < cap multigraph
   > cap multigraph
   < list
   > if df netstat interrupts ...
   < fetch if
   > multigraph if_eth0
   > out.value 6570
   > in.value 430986
   > multigraph if_err_eth0
   > rcvd.value 0
   > trans.value 0
   > multigraph if_eth1
   > ...
   > multigraph if_err_eth1
   > ...
   > .
   < quit


If the server had not announced ``cap multigraph`` the node MUST NOT respond with the names of multigraph plugins when the server issues a ``list`` command.  This is to stay compatible with old munin masters that do not understand multigraph.

The value of each consecutive multigraph attribute show above was used to preserve compatibility with present ``if_`` and ``if_err_`` wildcard plugins.  The field names in the response likewise.  When combining separate plugins into one please keep this compatibility issue in mind.

The response to the ``config plugin`` protocol command MUST be similarly interspersed with ``multigraph`` attributes.

Node issues
-----------

This introduces the need for the node to know which plugins are multigraph.  Since the node runs each and every plugin with "config" at startup (or when receiving HUP) it can simply examine the output.  If the output contains ``/^multigraph\s+/`` then the plugin is a multigraph plugin and MUST be kept on a separate, additional list of plugins only shown to the masters with multigraph capability.

Plugin issues
-------------

In case a multigraph plugin is attempted installed on a node which does not understand ``multigraph`` capability it will be able to detect this by the lack of the environment variable MUNIN_CAP_MULTIGRAPH that the node uses to communicate that it knows about multigraph plugins.  If this environment variable is absent the plugin SHOULD not make any kind of response to any kind of request.

In the perl and sh libraries support libraries there are functions to detect if the plugin is run by a capable node and if not simply emit dummy graph_title and other graph values to make it obvious that the plugin finds the node/environment lacking.

========================================
Future development of Multigraph plugins
========================================

The features in the following paragraphs are not implemented, and may never be.  They were things and issues that were considered while planning the multigraph feature, but did not make it into 1.4.

Plugin issues
-------------

*This is not implemented or otherwise addressed*

For a multigraph plugin replacing ``if_`` and ``if_err_`` we probably want a static behavior, as network interfaces are easily taken up and down (ppp*, tun*).

To preserve the static behavior of the present wildcard plugins the node can somehow preserve the needed data in ``munin-node.conf`` or ``/etc/munin/plugin-conf.d}`` and pass the response to the plugin in some environment variable to tell it what to do so the same is done each time.  This must be user editable so that it changes when more network interfaces is added, or to enable removing graphing of a specific interface which though present does not actually pass any traffic.

::

   [if]
   multigraph :eth0 :eth1 err:eth0 err:eth1

The separator character may well be something different than ":".  Any character not normally allowed in a plugin name should suffice.

Sample output
-------------

See  :ref:`plugin-multigraphing` for an example.
