.. _network-protocol:

=====================================
Data exchange between master and node
=====================================

Connect to the node
===================

::

  # telnet localhost 4949
  Trying 127.0.0.1...
  Connected to localhost.
  Escape character is '^]'.
  # munin node at foo.example.com
  help
  # Unknown command. Try cap, list, nodes, config, fetch, version or quit
  .
  Connection closed by foreign host.

Node commands
=============

The :ref:`Munin node <munin-node>` daemon will understand and answer to the following inquiries.

.. index::
   triple: protocol; command; cap

cap
    Lists the capabilities of the node, e.g. ``multigraph dirtyconfig``

.. index::
   triple: protocol; command; list

list [node]
    Simply lists items available for gathering for this host.
    E.g. load, cpu, memory, df, et alia.
    If no *host* is given, default to host that runs the munin-node.

.. index::
   triple: protocol; command; nodes

nodes
    Lists hosts available on this node.

.. index::
   triple: protocol; command; config

config *<query-item>*
    Shows the plugins configuration items. See the config protocol for a full description.

.. index::
   triple: protocol; command; fetch

fetch *<query-item>*
    Fetches values

.. index::
   triple: protocol; command; version

version
    Print version string

.. index::
   triple: protocol; command; quit

quit
    Close the connection. Also possible to use a point ".".

capabilities
------------

The master can exchange capabilities with the node using the "cap"
keyword, and a list of capabilities.  For each capability supported by
both the master and node, the node setes an environment variable
"MUNIN_CAP_CAPABILITY", where CAPABILITY is the capability in upper case.

Capabilities used so far by munin node and master:

dirtyconfig
~~~~~~~~~~~

If the node and master support the "dirtyconfig" capability, the
MUNIN_CAP_DIRTYCONFIG environment variable is set for all plugins.

This allows plugin to send config and data when the master asks for
"config" for this plugin, reducing the round trip time.

multigraph
~~~~~~~~~~

If the node and master support the "multigraph" capability, the
MUNIN_CAP_MULTIGRAPH environment variable is set for all plugins.

This allows plugins to use the "multigraph" format.

See also :ref:`plugin-protocol-multigraph`

spoolfetch
~~~~~~~~~~

If the node and master support the "spoolfetch" capability, the master
can use the "spoolfetch" command to retrieve a spool of all plugin
output since a given time.

This is used by :ref:`node-async`.

Example outputs
===============

config
------

::

  > config load
  < graph_args --title "Load average"
  < load.label Load
  < .
  > config memory
  < graph_args --title "Memory usage" --base 1024
  < used.label Used
  < used.draw AREA
  < shared.label Shared
  < shared.draw STACK
  < buffers.label Buffers
  < buffers.draw STACK
  < cache.label Cache
  < cache.draw STACK
  < free.label Free
  < free.draw STACK
  < swap.label Swap
  < swap.draw STACK


fetch
-----

Fetches the current values.

Returned data fields:

::

    <field>.value

Numeric value, or 'U'.

::

  > fetch load
  < load.value 0.42
  < .
  > fetch memory
  < used.value 98422784
  < shared.value 1058086912
  < buffers.value 2912256
  < cache.value 8593408
  < free.value 235753472
  < swap.value 85053440
