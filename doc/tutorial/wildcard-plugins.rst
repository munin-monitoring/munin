.. _tutorial-plugins-wildcard:

================
Wildcard Plugins
================

Wildcard plugins are plugins designed to be able to monitor more than one resource.
By symlinking the plugin to different identifiers, the exact same plugin
will be executed several times and give the associated output.

Operation & Naming Convention
=============================

Our standard example plugin is the ``if_`` plugin, which will collect data
from the different network interfaces on a system. By symlinking ``if_``
to ``if_eth0`` and ``if_eth1``, both interfaces will be monitored,
and creating separate graphs, using the same plugin.

Wildcard plugins should, by nomenclature standards, end with an underscore (``_``).

Installation
============

Because a wildcard plugin normally relies on the symlink name to describe
what item of data it is graphing, the plugin itself should be installed
in the system-wide plugin dir (``/usr/share/munin/plugins`` in Linux).
Then via the :ref:`munin-node-configure <munin-node-configure>` command,
your munin-node will suggest shell commands to setup the required symlinks
in the *servicedir* under ``/etc/munin/plugins``.

For 3rd-Party wildcard plugins We recoomend to install them into an own
directory e.g. ``/usr/local/munin/lib/plugins`` and call
``munin-node-configure`` with flag ``--libdir <your 3rd-party directory>``.

E.g.:

Before the plugin is installed:

::

    # munin-node-configure --shell

Install the new plugin:

::

    # mv /tmp/smart_ /usr/share/munin/plugins/smart_

Rescan for installed plugin:

::

    # munin-node-configure --shell
    ln -s /usr/share/munin/plugins/smart_ /etc/munin/plugins/smart_hda
    ln -s /usr/share/munin/plugins/smart_ /etc/munin/plugins/smart_hdc

You can now either manually paste the symlink commands into a shell,
or pipe the output of ``munin-node-configure --shell`` to a shell
to update in one sequence of commands.

SNMP Wildcard Plugins
=====================

SNMP plugins are a special case, as they have not only one but two parts of
the symlinked filename replaced with host-specific identifiers.

SNMP plugins follow this standard: ``snmp_[hostname]_something_[resource to be monitored]``

E.g.: ``snmp_10.0.0.1_if_6``

which will monitor interface 6 on the host ``10.0.0.1``.
The *unlinked* filename for this plugin is ``snmp__if_``
(note two underscores between ``snmp`` and ``if``).

See `Using SNMP plugins <http://www.munin-monitoring.org/wiki/Using_SNMP_plugins>`_ for information about configuring SNMP plugins.
