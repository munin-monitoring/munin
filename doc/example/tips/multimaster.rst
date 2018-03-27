.. _example-tips-masteraggregation:

==================================
 multiple master data aggregation
==================================

This example describes a way to have multiple master collecting
different information, and show all the data in a single presentation.

When you reach some size (probably several hundreds of nodes, several
tousands plugins), 5 minutes is not enough for your single master to
connect and gather data from all hosts, and you end up having holes in
your graph.

Requirements
============

This example requires a shared nfs space for the munin data between the
nodes.

Before going that road, you should make sure to check other options
first, like changing the number of update threads, and having rrdcached.

Another option you might consider, is using munin-async. It requires
modifications on all nodes, so it might not be an option, but I felt
compeled to mention it. If you can't easily have shared nfs, or if you
might have connectivity issues between master and some node, async would
probably be a better approach.

Because there is some rrd path merge required, it is highly recommended
to have **all** nodes in groups.

Overview
========

Munin-Master runs different scripts via the cron script (munin-cron).

``munin-update``
	is the only part actually connecting to the nodes. It gathers
	information and updates the rrd (you'll probably need rrdcached,
	especially via nfs).

``munin-limits``
	checks what was collected, compared to the limits and places
	warning and criticals.

The trick about having multiple master running to update is :

- run ``munin-update`` on different masters (called update-masters there
  after), having ``dbdir`` on nfs
- run ``munin-limits`` on either each of the update-masters, or the
  html-master (see next line)

Of course, all hosts must have access to the shared nfs directory.

Exemples will consider the shared folder /nfs/munin.

Running munin-update
====================

Cange the ``munin-cron`` to only run ``munin-update`` (and
``munin-limits``, if you have alerts you want to be managed directly on
those masters).

Change your ``munin.conf`` to use a dbdir within the shared nfs, (ie:
``/nfs/munin/db/<hostname>``).

To make it easier to see the configuration, you can also update the
configuration with an ``includedir`` on nfs, and declare all your nodes
there (ie: ``/nfs/munin/etc/<hostname>.d/``).

If you configured at least one node, you should have
``/nfs/munin/db/<hostname>`` that starts getting populated with
subdirectories (groups), and a few files, including ``datafile``, and
``datafile.storable`` (and ``limits`` if you also have munin-limits
running here).

Merging data
============

All our update-masters generate update their dbdir including:

- ``datafile`` and ``datafile.storable`` which contain information about
  the collected plugins, and graphs to generate.
- directory tree with the rrd files

Merging files
-------------

``datafile`` is just plain text with lines of ``key value``, so
concatenating all the files is enough.

``datafile.storable`` is a binary representation of the data as loaded
by munin. It requires some munin internal structures knowledge to merge
them.

If you have ``munin-limits`` also running on update-masters, it generate
a ``limits`` files, those are also plain text.

In order to make that part easier, a ``munin-mergedb.pl`` is provided in
contrib.

Merging rrd tree
----------------

The main trick is about rrd. As we are using a shared nfs, we can use
symlinks to get them to point to one an other, and not have to duplicate
them. (Would be hell to keep in sync, that's why we really need shared
nfs storage.)

As we deal with groups, we could just link top level groups to a common
rrd tree.

Example, if you have two updaters (update1 and update2), and 4 groups
(customer1, customer2, customer3, customer4), you could make something
like that::

/nfs/munin/db/shared-rrd/customer1/
/nfs/munin/db/shared-rrd/customer2/
/nfs/munin/db/shared-rrd/customer3/
/nfs/munin/db/shared-rrd/customer4/
/nfs/munin/db/update1/customer1 -> ../shared-rrd/customer1
/nfs/munin/db/update1/customer2 -> ../shared-rrd/customer2
/nfs/munin/db/update1/customer3 -> ../shared-rrd/customer3
/nfs/munin/db/update1/customer4 -> ../shared-rrd/customer4
/nfs/munin/db/update2/customer1 -> ../shared-rrd/customer1
/nfs/munin/db/update2/customer2 -> ../shared-rrd/customer2
/nfs/munin/db/update2/customer3 -> ../shared-rrd/customer3
/nfs/munin/db/update2/customer4 -> ../shared-rrd/customer4
/nfs/munin/db/html/customer1 -> ../shared-rrd/customer1
/nfs/munin/db/html/customer2 -> ../shared-rrd/customer2
/nfs/munin/db/html/customer3 -> ../shared-rrd/customer3
/nfs/munin/db/html/customer4 -> ../shared-rrd/customer4

At some point, an option to get the rrd tree separated from the dbdir,
and should avoid the need of such links.
