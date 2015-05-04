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
        "master" -> "node1";
        "master" -> "node2";
        "master" -> "node3";
   }

and also - where needed - per async

.. graphviz::

   digraph  {
        "master" -> async1 -> "node1";
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
