.. _others-index:

==========
Other docs
==========

.. _contributing:

Contributing
============

We need help with completing the `Munin Gallery <http://gallery.munin-monitoring.org/>`_.
A lot of plugins don't have their documentation in POD style format.
And the Gallery needs more pics!

See our wiki page with `instructions for gallery contributors <http://munin-monitoring.org/wiki/PluginGallery>`_.

.. _dev-talk:

Developer Talk
==============

- `Proposed extensions <http://munin-monitoring.org/wiki/ProposedExtensions>`_

Specifications
--------------

- `Munin Relay : a multiplexing relay <http://munin-monitoring.org/wiki/munin-relay>`_ (not yet implemented)
- `REST API <http://munin-monitoring.org/wiki/RestApi>`_ (RFC)
- `Stream plugin <http://munin-monitoring.org/wiki/api-stream>`_ (RFC)

Ideas
-----

- Some thoughts about `Tags <http://munin-monitoring.org/wiki/Tags>`_
- Some thoughts about `basic module API for plugins written in Perl, Python and Ruby <http://munin-monitoring.org/wiki/PluginFramework>`_

Snippets
--------

Dirty config
^^^^^^^^^^^^

A *dirty* fetch is not desirable because some plugins (rightly) assume that
``config`` is done first and then ``fetch`` and updates the state file accordingly.
This should be accommodated since we can.  Therefore the feature will be called
*dirty config* instead.

Today, for each plugin, on every run, munin-update first does ``config $plugin``
and then a ``fetch $plugin``.

Some plugins do a lot of work to gather their numbers.  Quite a few of these
need to do the same amount of work for the value fetching and printing
as for the ``config`` output.

We could halve the execution time if ``munin-update`` detects that
``config $plugin`` produces .value and from that deducts that the
``fetch $plugin`` is superfluous.  If so the ``fetch`` will not be executed
thus halving the total execution time.  A ``config`` with ``fetch``-time output
in would be called a ``dirty config`` since it not only contains
``config``-time output.  If the ``config`` was not dirty a old fashioned
``fetch`` must be executed.

So: Versions of ``munin-update`` that understands a dirty config emits
``cap dirtyconfig`` to the node, if the node understands the capability
it will set the environment variable ``MUNIN_CAP_DIRTYCONFIG`` before executing plugins.

A plugin that understands ``MUNIN_CAP_DIRTYCONFIG`` can simply do something
like (very pseudo code) ``if ( is_dirtyconfig() ) then do_fetch(); endif;``
at the end of the ``do_config()`` procedure.  ``Plugin.sh`` and ``Plugin.pm`` needs
to implement a ``is_dirtyconfig`` - or similarly named - procedure
to let plugins test this easily.

Plugins that do dirty config to a master that does not understand it
should still work OK: old ``munin-updates`` would do a good deal of
error logging during the ``config``, but since they do not understand
the point of all this config in the ``fetch`` they would also do
``config`` and everything would work as before.

Plugins that want to be polite could check the masters capabilities
before executing a dirty ``config`` as explained above.

After 2.0 has been published with this change in plugins would be
simpler and combined with some other extensions it would greatly
reduce the need for many plugin state files and such complexity.
Should make plugin author lives much easier all together.
