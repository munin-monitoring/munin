This is Munin
=============

Munin is distributed under the GNU GPL version 2.  Munin is copyrighted
2002-2017 by its various authors as identified in the source files.

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

Please always rebase your pull requests on a released version tag, one of the
stable branches, or the default branch, ``master``.

If you request a pull against ``master``, your pull will be automatically closed
upon merge. If you request against one of the stable release branches, your pull will be
automatically closed upon the next release.

Building status
---------------

stable-2.0 : |build-stable2.0|

master : |build-master|  |coverage-master|

docs : |docs-latest|

.. |build-stable2.0| image:: https://travis-ci.org/munin-monitoring/munin.svg?branch=stable-2.0
   :target: https://travis-ci.org/munin-monitoring/munin

.. |build-master| image:: https://travis-ci.org/munin-monitoring/munin.svg?branch=master
   :target: https://travis-ci.org/munin-monitoring/munin

.. |coverage-master| image:: https://coveralls.io/repos/munin-monitoring/munin/badge.svg?branch=master&service=github
   :target: https://coveralls.io/github/munin-monitoring/munin?branch=master

.. |docs-latest| image:: https://readthedocs.org/projects/munin/badge/?version=latest
   :target: http://guide.munin-monitoring.org/

