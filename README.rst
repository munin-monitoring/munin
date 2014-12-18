This is Munin
=============

Munin is distributed under the GNU GPL version 2.  Munin is copyrighted
2002-2012 by its various authors as identified in the source files.

Munin is homed at http://munin-monitoring.org/.  After you have completed 
the INSTALL all the documentation can be found there.

Information on developing Munin with GitHub, such as how branches are used
and the version numbering scheme, can be found in `Munin's GitHub Wiki`__.

.. __ : https://github.com/munin-monitoring/munin/wiki/_pages

Note to contributors
--------------------

By sending us patches, you automatically license the code under the same terms
as Munin.

We also might edit your commits metadata (the comment part) for clarifications,
but we'll leave the diff part intact (except for whitespace edits). So in case
there's a problem with the commit diff, we either commit another patch
thereafter or plainly ask you to rework it. We might eventually squash some of
your commits into one.

Please always rebase your pull requests on a released version, ideally the
latest one. This makes the merging process much easier. The default branch,
``master``, automatically tracks the latest released version, so it is a very
good starting point.

If you request a pull against ``master``, your pull will be automatically closed
upon release. If you request against ``devel``, your pull will be automatically
closed upon merge.

Building status
---------------

stable-2.0 : |build-stable2.0|

devel : |build-devel|

docs : |docs-latest|

.. |build-stable2.0| image:: https://travis-ci.org/munin-monitoring/munin.png?branch=stable-2.0
   :target: https://travis-ci.org/munin-monitoring/munin

.. |build-devel| image:: https://travis-ci.org/munin-monitoring/munin.png?branch=devel
   :target: https://travis-ci.org/munin-monitoring/munin

.. |docs-latest| image:: https://readthedocs.org/projects/munin/badge/?version=latest
   :target: http://guide.munin-monitoring.org/

