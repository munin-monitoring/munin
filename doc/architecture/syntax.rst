.. _syntax:

=========================
Munin's Syntax
=========================

POD style documentation
=======================

**Wiki Pages:**

- `munindoc <http://munin-monitoring.org/wiki/munindoc>`_

.. _magic-markers:

Magic Markers
=============

Munin can only autoconfigure plugins that have the right (optional) magic markers. 
Magic markers are prefixed with "#%#", and consists of a keyword, an equal sign, and one or more values.

For a plugin that is part of munin, you should expect to see:

 #%# family=auto
 #%# capabilities=autoconf suggest

family
^^^^^^

For the magic marker "family", the following values may be used.

auto
    This is a plugin that can be automatically installed and configured by munin-node-configure 

snmpauto
    This is a plugin that can be automatically installed and configured by munin-node-configure if called with --snmp (and related arguments) 

manual
    This is a plugin that is to be manually configured and installed 

contrib
    This is a plugin which has been contributed to the munin project by others, and has not been checked for conformity to the plugin standard. 

test
    This is a test plugin. It does used when testing munin. 

example
    This is an example plugin. It serves as a starting point for writing new plugins. 

capabilities
^^^^^^^^^^^^
For the magic marker "capabilities", the following values may be used.

autoconf
    The plugin may be automatically configured by "munin-node-configure". 

suggest
    The plugin is a wildcard plugin, and may suggest a list of link names for the plugin. 

Datatypes
=========

GAUGE
^^^^^

DERIVE
^^^^^^
