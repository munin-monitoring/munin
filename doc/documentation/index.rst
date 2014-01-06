.. _documentation-index:

===================
 Documenting Munin
===================

This document is rather meta, it explains how to document Munin.

More than one place for docs
=============================

Plugin Docs
  are included in the plugins code files. We use POD [#]_. style format there and deliver a 
  command line utility ``munindoc`` to display the info pages about the plugins.
  Call ``munindoc buddyinfo`` to get the documentation for plugin ``buddyinfo``
  
  Have a look at the `munindoc instruction page in our Trac wiki <http://munin-monitoring.org/wiki/munindoc>`_ 
  and edit or add the pod section in the plugins code file accordingly. Send a patch or a pull request on github 
  to help us improve the plugins documentation.

Unix Manual Pages
  are also part of the distributed munin packages. Most Munin commands 
  (such as munin-run, and munindoc itself) are only documented through the usual Unix man command.

Munin Guide
  The pages you are just viewing ;) We use RST [#]_. format here. If you have a github account, you can edit the pages online and send a pull request to contribute your work to the Munin master repository.

Munin's Wiki
  Currently it contains a mixture of all sorts of documentation listed above.
  In the future the `wiki <http://munin-monitoring.org/wiki/>`_ 
  shall be the place for docs concerning anything *around* Munin, 
  whilst the things to say about the *Munin software* shall be placed here in the 
  `Munin Guide <https://munin.readthedocs.org/>`_.

.. _instructions http://munin-monitoring.org/wiki/munindoc
.. [#] Plain Old Documentation, abbreviated pod, is a lightweight markup language used to document the Perl programming language. Source Wikipedia: http://en.wikipedia.org/wiki/Perldoc
.. [#] The reStructuredText (frequently abbreviated as reST) project is part of the Python programming language Docutils project of the Python Doc-SIG (Documentation Special Interest Group). Source Wikipedia: http://en.wikipedia.org/wiki/ReStructuredText

Nomenclature
============

.. toctree::
   :maxdepth: 2

   nomenclature.rst
