.. index::
   single: fqn
   single: fully qualified name

.. _reference-fqn:

======================
 Fully Qualified Name
======================

The Fully Qualified Name, or "FQN" is the address of a group, node,
service, or a data source in munin.

It is most often used when configuring graphs which has no single
corresponding plugin, but borrow data sources from other services.


.. index::
   pair: fqn; group

.. _group-fqn:

Group FQN
=========

The group FQN consists of one or more components, separated with a
semicolon.

.. note::

   If a node is configured without a group, the domain of the hostname becomes the group.

Examples

::

   example.com
   -----------
       |
       `--- group "example.com"

::

   acme;webservers
   ---- ----------
    |    |
    |    `--- group "webservers"
    `-------- group "acme"

.. index::
   pair: fqn; node

.. _node-fqn:

Node FQN
========

The fully qualified name to a node consists of a group FQN, a
semicolon, and a hostname.

Examples:

::

   example.com;foo.example.com
   ----------- ---------------
    |           |
    |           `--- node "foo.example.com"
    `--------------- group "example.com"

::

   acme;webservers;www1.example.net
   ---- ---------- ----------------
    |    |          |
    |    |          `-------------- node "www1.example.net"
    |    `------------------------- group "webservers"
    `------------------------------ group "acme"


.. index::
   pair: fqn; service
   pair: fqn; plugin

.. _service-fqn:

Service FQN
===========

The fully qualified name to a service consists of a node FQN, a colon,
and a service name.

.. note::

   A simple munin plugin will provide a service with the same name as
   the plugin. A multigraph plugin will provide one or more services,
   with arbitrary names.

Example:

::

   acme;webservers;www1.example.net:https_requests
   ---- ---------- ---------------- --------------
    |    |          |                |
    |    |          |                `--- service "https_requests"
    |    |          `-------------------- node "www1.example.net"
    |    `------------------------------- group "webservers"
    `------------------------------------ group "acme"

.. index::
   pair: fqn; data source
   pair: fqn; ds

.. _ds-fqn:

Data source FQN
===============

The fully qualified name to a data source consists of a service fqn, a
dot, and a data source name.

Note: A data source normally corresponds to one line in a graph.

Example:

::

   acme;webservers;www1.example.net:https_requests.denied
   ---- ---------- ---------------- -------------- ------
    |    |          |                |              |
    |    |          |                |              `--- data source "denied"
    |    |          |                `------------------ service "https_requests"
    |    |          `----------------------------------- node "www1.example.net"
    |    `---------------------------------------------- group "webservers"
    `--------------------------------------------------- group "acme"
