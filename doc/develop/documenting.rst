.. _documentation-index:

===================
 Documenting Munin
===================

.. index::
   triple: contributing; munin; documentation

This document is rather meta, it explains how to document Munin.

More than one place for docs
=============================

Plugin Docs
  are included in the plugins code files. We use POD [#]_. style format there and deliver a
  command line utility ``munin-doc`` to display the info pages about the plugins.
  Call ``munin-doc buddyinfo`` to get the documentation for plugin ``buddyinfo``.

  We use this POD sections also in the `Munin Gallery <http://gallery.munin-monitoring.org>`_.
  See our `Wiki page <http://munin-monitoring.org/wiki/PluginGallery>`_ for instructions
  how to contribute also example images for the gallery.

  Have a look at the `munin-doc instruction page in our Trac wiki <http://munin-monitoring.org/wiki/munindoc>`_
  and edit or add the pod section in the plugins code file accordingly. See the `perlpod Manual <http://perldoc.perl.org/perlpod.html>`_
  for help on the syntax. Finally send a patch or a pull request on github
  to help us improve the plugins documentation.

Unix Manual Pages
  are also part of the distributed munin packages. Most Munin commands
  (such as munin-run, and munin-doc itself) are only documented through the usual Unix man command.

Munin Guide
  The pages you are just viewing ;) We use RST [#]_. format here. If you have a
  GitHub_ account, you can even edit the pages online and send a pull request to
  contribute your work to the official Munin repository.

Munin's Wiki
  Currently it contains a mixture of all sorts of documentation listed above.
  In the future, the wiki_ shall be the place for docs concerning anything *around* Munin,
  whilst the things to say about the *Munin software* shall be placed here in the
  `Munin Guide`_.

.. _instructions: http://munin-monitoring.org/wiki/munindoc
.. [#] Plain Old Documentation, abbreviated pod, is a lightweight markup language used to document the Perl programming language. Source Wikipedia: http://en.wikipedia.org/wiki/Perldoc
.. [#] The reStructuredText (frequently abbreviated as reST) project is part of the Python programming language Docutils project of the Python Doc-SIG (Documentation Special Interest Group). Source Wikipedia: http://en.wikipedia.org/wiki/ReStructuredText

.. _GitHub: https://github.com/
.. _Munin Guide: https://munin.readthedocs.org/
.. _wiki: http://munin-monitoring.org/wiki/
