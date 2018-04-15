.. _vetted-plugins:

=================================
Requirements for 'Vetted Plugins'
=================================

.. index::
   single: vetted plugin
   pair: development; plugin
   pair: plugin; contribution

This is a draft paper written in 2009 by niclan and dipohl. It should be reviewed, completed (at least merged with the `docs for plugin contributors <https://github.com/munin-monitoring/contrib/tree/master/plugins#contributed-munin-plugins>`_, that were published on github)  and then decreed by the developer team.

Purpose is to define requirements for quality plugins that get starred / recommended in the `plugin gallery <http://gallery.munin-monitoring.org>`_ and also may be accepted for the official distribution of munin-node.

Usability
=========

Vetted plugins should work well out of the box, and should autoconf correctly in most cases. The :ref:`Concise guide to plugin authoring <plugin-concise>` describes plugins methods :ref:`autoconf <plugin-concise-autoconf>` and :ref:`suggest <plugin-concise-suggest>`.

Their graph should be significant and easy to comprehend. See the :ref:`Guide for good plugin graphs <plugin-bcp>`.

Security
========

*Important demands should be added here..*

Documentation
=============

POD Style documentation in the plugin (See :ref:`Munin documentation <plugin-documentation>` for the details)

Examples on what information should be included in a plugin POD can be found in `apache <https://raw.githubusercontent.com/munin-monitoring/munin/master/plugins/node.d/apache>`_ and `buddyinfo <http://gallery.munin-monitoring.org/distro/svn/munin-stable-2.0/plugins/node.d.linux/buddyinfo.html>`_ (here contribution includes also example graph images for the :ref:`Munin Plugin Gallery <plugin-gallery>` :-)

Packaging
=========

Vetted plugins shouldn't conflict with plugins in other packages as well (ie: plugins in munin-node or munin-plugins-extra).

These plugins can go in ``$(DESTDIR)/usr/share/munin/plugins``.
