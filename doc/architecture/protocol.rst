.. _protocol-index:

===================
The Munin Protocols
===================

Here we describe the rules for collaboration and communication between :ref:`Munin's components <architecture-overview>`.

Introduction
------------

Contents on this page will focus on already implemented features. For *proposals* and *ideas*
look in the `Wiki <http://www.munin-monitoring.org/wiki/development>`_.

Concepts
--------

Fetching Data
=============

Poller-based monitoring infrastructure

.. graphviz::

   digraph  {
       graph [ rankdir="LR" ];
       node [style=filled, fillcolor="white:lightgrey"];

       "master" [label="munin\nmaster", fillcolor="white:lightblue"];

       "master" -> "node1";
       "master" -> "node2";
       "master" -> "node3";
   }

Using the :ref:`node-async`:

.. graphviz::

   digraph  {
       graph [ rankdir="LR" ];
       node [style=filled, fillcolor="white:lightgrey"];

       subgraph cluster_munin_node {
           label = "node1";
           "munin-asyncd" -> "munin-node" [label="read"];
           "munin-asyncd" -> "spool" [label="write"];
           "munin-async"  -> "spool";
       }

       "master" [label="munin\nmaster", fillcolor="white:lightblue"];

       "master" -> "munin-async" [label="ssh"];
       "master" -> "node2";
       "master" -> "node3";

   }

Using :ref:`plugin-snmp`.

.. graphviz::

   digraph {
       graph [ rankdir="LR" ];
       node [style=filled, fillcolor="white:lightgrey"];

       "master" [label="munin\nmaster", fillcolor="white:lightblue"];

       "master" -> "node1";
       "node1"  -> "switch" [label="snmp"];
       "node1"  -> "router" [label="snmp"];
       "node1"  -> "access\npoint" [label="snmp"];

       "master" -> "node2";
       "master" -> "node3";
   }

Network Protocol
----------------

Common Plugins
==============

- See :ref:`Protocol for data exchange between master and node <network-protocol>`


Multigraph Plugins
==================

- See :ref:`Protocol for Multigraph Plugins <plugin-protocol-multigraph>`

Dirtyconfig plugins
===================

- See :ref:`plugin-protocol-dirtyconfig`

Plugins with custom sample rate
===============================

- See :ref:`plugin-supersampling`
