.. _initial_configuration:

=======================
 Initial Configuration
=======================

Node
====

Plugins
-------

Decide which plugins to use. The munin node runs all plugins present
in CONFDIR/plugins/ (usually /etc/munin/plugins).

The quick auto-plug-and-play solution:

.. code-block:: bash

 munin-node-configure --shell --families=contrib,auto | sh -x

See :ref:`plugin-use` for more details.

Access
------

The munin node listens on all interfaces by default, but has a
restrictive access list. You need to add your master's IP address
to ``/etc/munin/munin-node.conf``.

The ``cidr_allow``, ``cidr_deny``, ``allow`` and ``deny`` directives
are related to access control.

``cidr_allow`` expects the following notation:
syntax (the /32 is not implicit, so for
a single host, you need to add it):

    | cidr_allow 127.0.0.0/8
    | cidr_allow 192.0.2.1/32

Please note, that the prefix length (e.g. ``/32``) is mandatory for
``cidr_allow`` and ``cidr_deny``.

``allow`` uses regular expression matching against the client IP address.

    | allow '^127\.'
    | allow '^192\.0\.2\.1$'

For specific information about the syntax, see `Net::Server
<http://search.cpan.org/dist/Net-Server/lib/Net/Server.pod>`_. Please
keep in mind that ``cidr_allow`` requires the ``Net::CIDR`` perl module.

Startup
-------

Start the node agent (as root) SBINDIR/munin-node. Restart it if it
was already started. The node only discovers new plugins when it is
restarted.

You probably want to use an init-script instead and you might find a
good one under build/dists or in the build/resources directory (maybe
you need to edit the init script, check the given paths in the script
you might use).

Master
======

Add some nodes
--------------

Add some nodes to CONFDIR/munin.conf

[node.example.com]
  address 192.0.2.4

[node2.example.com]
  address node2.example.com

[node3.example.com]
  address 2001:db8::de:caf:bad
