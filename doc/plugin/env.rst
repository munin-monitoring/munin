.. _plugin-env:

=============================================
 Environment variables accessible in plugins
=============================================

.. index::
   pair: plugin; environment

The node automatically defines some environment vars. All the munin-related
vars do begin with the ``MUNIN_`` prefix and are all capitals.

Munin related
=============

``MUNIN_DEBUG``
  Defines the debug level the plugin should run in.

  Default: ``0``

``MUNIN_MASTER_IP``
  Contains the IP of the connecting master. If using ``munin-run``, it is equal
  to the ``"-"`` string.

``MUNIN_CAP_DIRTYCONFIG``
  Indicates whether the master is able to understand the :ref:`dirtyconfig protocol <plugin-protocol-dirtyconfig>`.

.. csv-table:: Values
	:header: "Value", "Description"

	"0", "Master does not understand ``value`` lines that are returned within a ``config`` response."
	"1", "Master is able to consume ``value`` lines right after reading the configuration from a plugin."

``MUNIN_CAP_MULTIGRAPH``
  Indicates whether the master is able to understand the :ref:`multigraph <plugin-protocol-multigraph>` keyword.

.. csv-table:: Values
	:header: "Value", "Description"

	"0", "Master does not understand the ``multigraph`` keyword."
	"1", "Master does understand the ``multigraph`` keyword."

.. _plugin-env-MUNIN_PLUGSTATE:

``MUNIN_PLUGSTATE``
  Defines the directory that a plugin must use if it wants to store
  stateful data that is shared with other plugins.

  Default: ``/var/lib/munin-node/$USER``

.. note::

  Only the plugins that execute themselves as the same user can exchange data,
  for obvious security reasons.

.. _plugin-env-MUNIN_STATEFILE:

``MUNIN_STATEFILE``
  Defines a file that the plugin must use if it wants to store
  stateful data for himself.

  It is guaranteed to be unique, per plugin **and** per master. Therefore 2
  masters will have 2 different state files for the same plugin.

Config related
==============

Here is a list of other environment vars, that are derived from the ``Munin::Common::Defaults`` package.

::

	MUNIN_PREFIX
	MUNIN_CONFDIR
	MUNIN_BINDIR
	MUNIN_SBINDIR
	MUNIN_DOCDIR
	MUNIN_LIBDIR
	MUNIN_HTMLDIR
	MUNIN_CGIDIR
	MUNIN_CGITMPDIR
	MUNIN_DBDIR
	MUNIN_PLUGSTATE
	MUNIN_SPOOLDIR
	MUNIN_MANDIR
	MUNIN_LOGDIR
	MUNIN_STATEDIR
	MUNIN_USER
	MUNIN_GROUP
	MUNIN_PLUGINUSER
	MUNIN_VERSION
	MUNIN_PERL
	MUNIN_PERLLIB
	MUNIN_GOODSH
	MUNIN_BASH
	MUNIN_PYTHON
	MUNIN_RUBY
	MUNIN_OSTYPE
	MUNIN_HOSTNAME
	MUNIN_HASSETR

System related
==============

Munin does redefine some system environment vars :

``PATH``
	This is redefined for security. It does provide a safe environment so
	that shell scripts are able to launch regular commands such as ``cat``,
	``grep`` without having to be explicit in their location.


``LC_ALL`` & ``LANG``
	This is redefined to ease the work of plugin authors. It enables a
	standard output when parsing common commands output.

See also
========

 * :ref:`Environment variables in plugin configuration <plugin-conf.d>`
