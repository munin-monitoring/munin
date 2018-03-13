.. _history:

=========================
A Brief History of Munin
=========================

2002
        Born as LRRD

2004
        Renamed as Munin

2007
        Hacked zooming for 1.2

2009
        1.4 came out

2011
        EOL of :ref:`Munin Exchange website <Munin-Exchange>`, content moved to GitHub branch **contrib**

2012
        Released 2.0, for its 10 years !

2013
        Released 2.1


July 2014
        target for 2.2


Glossary
========

.. index::
   single: Munin Exchange

.. _Munin-Exchange:

Munin Exchange
--------------

Was a web platform in the beginning setup and hosted by Linpro (Bjorn Ruberg?).
Later (when?) a Munin supporter re-invented the `Munin Exchange` website to improve its usablity.
When he left the project (when?) it was not possible to maintain the website any longer,
because it was coded in Python with Django and Steve Schnepp said "we clearly lack skills on that".
So it was decided to move all the plugins over to github branch "contrib".

Github is now the official way of contributing 3rd-party plugins.

These are tagged with **familiy contrib** (see: :option:`--families` in :ref:`munin-node-configure`).

Only if they meet the requirements for `vetted plugins <http://munin-monitoring.org/wiki/requirements-vetted>`_
they can be included in the core plugins collection (distributed as `official` Munin release
by the Munin developer team). They get tagged with **family auto** then
as all core collection plugins should have the command
:ref:`autoconf <plugin-concise-autoconf>`
implemented.


See also: :ref:`munin-gallery`
