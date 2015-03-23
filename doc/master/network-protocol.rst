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

cap
    Lists the capabilities of the node, e.g. ``multigraph dirtyconfig``
list [node]
    Simply lists items available for gathering for this host. 
    E.g. load, cpu, memory, df, et alia.
    If no *host* is given, default to host that runs the munin-node.
nodes
    Lists hosts available on this node.
config *<query-item>*
    Shows the plugins configuration items. See the config protocol for a full description.
fetch *<query-item>*
    Fetches values
version
    Print version string
quit
    Close the connection. Also possible to use a point ".".

Example outputs
===============

config
^^^^^^
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
^^^^^
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
