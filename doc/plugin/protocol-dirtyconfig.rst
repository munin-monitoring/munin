.. _plugin-protocol-dirtyconfig:

.. index::
   triple: protocol; extension; dirtyconfig
   pair: capability; dirtyconfig

=================================
 Protocol extension: dirtyconfig
=================================

The dirtyconfig capability is implemented in munin 2.0 and on.

Objective
---------

Reduce execution time for plugins.

Description
-----------

Munin plugins are usually run twice.  Once to provide configuration,
and once to provide values.

Plugins which have to fetch data in order to provide meaningful
configuration can use the "dirtyconfig" capability to send both
configuration and values in the same run.

Using "dirtyconfig", plugins no longer have to be run twice. There is
no longer a need to keep a state file to keep state between "config"
and "fetch" invocations for plugins with long execution times.


Network protocol
----------------

::

   >> command from master to node
   << response from node to master

::

   << # munin node at somewhere.example.com
   >> cap dirtyconfig
   << cap dirtyconfig
   >> list
   << lorem ...
   >> config lorem
   << graph_title Lorem ipsum
   << lorem.label Lorem
   << lorem.value 1


The master and node exchange capabilities with the ``cap`` command,
with an argument list containing supported capabilities.

The server must send ``cap`` with ``dirtyconfig`` as one of the
arguments.

The node must respond with ``cap``, and include ``dirtyconfig`` as one
of the capabilities.

Effects
-------

The munin node will sets the ``MUNIN_CAP_DIRTYCONFIG`` variable to
``1`` in the plugin environment.

The munin master will call the plugin once with ``config plugin``, and
if the output includes .value fields, it will skip the ``fetch
plugin`` step.

Using dirtyconfig
-----------------

In a plugin, check the environment variable ``MUNIN_CAP_DIRTYCONFIG``,
ensure it has a value of ``1``.

If this is correct, you can emit values when the plugin is called with
the ``config`` argument.

sample plugin
-------------

.. code-block:: bash

   #!/bin/sh

   emit_config() {
     echo "graph_title test with single word"
     echo "graph_category test"
     echo "test.label test"
   }

   emit_values() {
     echo "test.value 1"
   }

   case "$1" in
     config)
       emit_config
       if [ "$MUNIN_CAP_DIRTYCONFIG" = "1" ]; then
         emit_values
       fi
       ;;
     *)
       emit_values
       ;;
   esac
