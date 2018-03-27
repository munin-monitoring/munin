.. _munin-c:

=======
Munin-C
=======

.. index::
   single: embedded machines;
   single: light-weight node;
   pair: munin-node; munin-c;

``Munin C`` is a ``C`` rewrite of various munin components.
The node is a rewrite of :ref:`munin-node <munin-node>`, and the plugins are a rewrite of commonly used munin plugins a single binary.

Purpose
=======

* reducing resource usage
   - disk space: the binary is smaller than the plugins together
   - more diskspace: it has no dependencies on other programs
   - less forks: it does not fork internally
   - faster startup: it doesn't start perl or shell
   - less memory: just a small C program
   - less file accesses: one binary for many plugins
* no need for Perl
* everything can be run from inetd

It makes it very useful for machines without native support for Perl scripting, mostly because of restricted resources like embedded machines.

Limits
======

* You lose flexibility as it is compiled code
   - plugin modification is not that easy
   - you have to create and distribute binaries
   - you have to care about portability accross architectures.
* Not all the features are implemented
   - root uid is not supported. All plugins are run with a single user, usually nobody.
   - no socket is opened. Everything runs from inetd.

What plugins are included?
==========================
``cpu``
``entropy``
``forks``
``fw_packets``
``interrupts``
``load``
``open_files``
``open_inodes``
``processes``
``swap``
``uptime``
``memory``

Install
=======

After compiling there will be a binary named ``munin-plugins-c``. You can just replace the symlinks in ``/etc/munin/plugins/`` with symlinks to this binary. 

Note that the C version of the plugins do not need the C version of the node. It is just recommended as it gives you the full benefits at no added cost.
