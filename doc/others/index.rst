.. _others-index:

==========
Other docs
==========

.. _contributing:

Contributing
============

We welcome contributions to Munin. Here are the main ways to help:

Plugin Gallery
--------------

We need help completing the `Munin Gallery <https://gallery.munin-monitoring.org/>`_.
A lot of plugins don't have their documentation in POD style format.
And the Gallery needs more screenshots!

See the `hints for plugin contributions <https://github.com/munin-monitoring/contrib/blob/master/plugins/README.md>`_
for more details.

Code Contributions
------------------

Munin is hosted on `GitHub <https://github.com/munin-monitoring/munin>`_.
To contribute code:

1. Fork the repository.
2. Create a feature branch.
3. Make your changes with tests.
4. Submit a pull request.

See :ref:`develop-environment` for instructions on setting up a
development environment.

Documentation
-------------

The Munin Guide is written in reStructuredText and built with Sphinx.
You can edit pages directly on GitHub and submit a pull request.
See :ref:`documentation-index` for details.


.. _dev-talk:

Project Resources
=================

- `Munin Wiki <http://munin-monitoring.org/wiki/>`_ — community documentation
- `Munin Contrib <https://github.com/munin-monitoring/contrib>`_ — contributed plugins
- `Munin Gallery <https://gallery.munin-monitoring.org/>`_ — plugin catalog with screenshots
- `Mailing lists <http://munin-monitoring.org/documentation.html>`_ — user and developer lists


.. _dirtyconfig-overview:

Dirty Config
============

The "dirty config" optimization allows plugins to output both configuration
and data values in a single ``config`` call, eliminating the need for a
separate ``fetch``. This can halve the execution time for expensive plugins.

How it works
------------

Normally, ``munin-update`` calls ``config <plugin>`` and then ``fetch <plugin>``
for each plugin on every run. Plugins that do expensive work to gather their
numbers end up doing that work twice.

With dirty config, a plugin outputs its values as part of the ``config`` response.
``munin-update`` detects this (the config output contains ``.value`` lines) and
skips the separate ``fetch`` call.

Implementation
--------------

The master advertises the capability with ``cap dirtyconfig``. If the node
supports it, it sets the environment variable ``MUNIN_CAP_DIRTYCONFIG`` before
running plugins.

A plugin that supports dirty config checks this variable and, if set, includes
its values in the ``config`` output. Plugins that don't support dirty config
continue to work normally — old masters simply ignore the extra output during
``config`` and call ``fetch`` as usual.

See :ref:`plugin-protocol-dirtyconfig` for the protocol details.
