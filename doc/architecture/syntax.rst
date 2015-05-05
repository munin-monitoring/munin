.. _syntax:

=========================
Munin's Syntax
=========================

POD style documentation
=======================

**Wiki Pages:**

- `munindoc <http://munin-monitoring.org/wiki/munindoc>`_

Configuration
=============

- For the :ref:`Munin master <master-index>` in :ref:`/etc/munin/munin.conf <munin.conf>`.
- For the :ref:`Munin node <node-index>` daemon in :ref:`/etc/munin/munin-node.conf <munin-node.conf>`.
- For the :ref:`Munin plugins <plugin-index>` in :ref:`/etc/munin/plugin-conf.d/.. <plugin-conf.d>`.

.. index::
   pair: plugin; magic marker

.. _magic-markers:

Magic Markers
=============

Munin can only autoconfigure plugins that have the corresponding (optional) magic markers.
Magic markers are prefixed with ``#%#`` and consists of a keyword, an equal sign, and one or more whitespace-separated values.

For a plugin that is part of munin, you should expect to see:

.. code-block:: perl

 #%# family=auto
 #%# capabilities=autoconf suggest

.. index::
   pair: magic marker; family

family
^^^^^^

For the magic marker ``family``, the following values may be used.

.. index::
   triple: magic marker; family; auto

auto
    This is a plugin that can be automatically installed and configured by ``munin-node-configure``

.. index::
   triple: magic marker; family; snmpauto

snmpauto
    This is a plugin that can be automatically installed and configured by ``munin-node-configure`` if called with ``--snmp`` (and related arguments)

.. index::
   triple: magic marker; family; manual

manual
    This is a plugin that is to be manually configured and installed

.. index::
   triple: magic marker; family; contrib

contrib
    This is a plugin which has been contributed to the munin project by others, and has not been checked for conformity to the plugin standard.

.. index::
   triple: magic marker; family; test

test
    This is a test plugin. It does used when testing munin.

.. index::
   triple: magic marker; family; example

example
    This is an example plugin. It serves as a starting point for writing new plugins.

.. index::
   pair: magic marker; capabilities

capabilities
^^^^^^^^^^^^
For the magic marker "capabilities", the following values may be used.

.. index::
   triple: magic marker; capability; autoconf

autoconf
    The plugin may be automatically configured by "munin-node-configure".

.. index::
   triple: magic marker; capability; suggest

suggest
    The plugin is a wildcard plugin, and may suggest a list of link names for the plugin.

Datatypes
=========

GAUGE
^^^^^

DERIVE
^^^^^^
