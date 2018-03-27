.. _documentation-index:

===================
 Documenting Munin
===================

.. index::
   triple: contributing; munin; documentation

Munin Guide
===========

The pages you are just viewing ;)

The guide contains documentation about the Munin software.

It is written using reStructuredText [#]_.

If you have a GitHub_ account, you can even edit the pages online and
send a pull request to contribute your work to the official Munin
repository.

Plugin Documentation
====================

Plugin documentation is included in each plugin, written using the POD
[#]_ style format

The command line utility :ref:`munindoc` can be used to display the
info pages about the plugins.  Call ``munindoc buddyinfo`` to get the
documentation for plugin ``buddyinfo``.

Have a look at the `munindoc instruction page in our Trac wiki
<http://munin-monitoring.org/wiki/munindoc>`_ and edit or add the pod
section in the plugins code file accordingly.

Finally send a patch or a pull request on github to help us improve
the plugins documentation.

.. _munin-gallery:

Munin Gallery
=============

The plugin documentation is also included in the `Munin Gallery
<http://gallery.munin-monitoring.org>`_.

See our `Wiki page <http://munin-monitoring.org/wiki/PluginGallery>`_
for instructions how to contribute also example images for the
gallery.

Unix Manual Pages
=================

The manual pages are included in, and generated from, the :ref:`man
pages in the Munin Guide <man-pages>`.

Munin's Wiki
============

The wiki_ contains documentation concerning anything *around* munin,
whilst the documentation of the *Munin software* is here in the `Munin
Guide`_.

.. _instructions: http://munin-monitoring.org/wiki/munindoc
.. [#] Pod is a simple-to-use markup language used for writing
       documentation for Perl, Perl programs, and Perl modules. (And
       Munin plugins)

       See the `perlpod Manual
       <http://perldoc.perl.org/perlpod.html>`_ for help on the
       syntax.

.. [#] The reStructuredText (frequently abbreviated as reST) project
       is part of the Python programming language Docutils project of
       the Python Doc-SIG (Documentation Special Interest
       Group). Source Wikipedia:
       http://en.wikipedia.org/wiki/ReStructuredText

       See the `reSTructuredText Primer
       <http://sphinx-doc.org/rest.html>`_ for help on the syntax.

.. _GitHub: https://github.com/
.. _Munin Guide: https://guide.munin-monitoring.org/
.. _wiki: http://munin-monitoring.org/wiki/
