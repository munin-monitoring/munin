.. _preface-index:

=========
 Preface
=========

.. toctree::
   :maxdepth: 2

   whatis.rst
   history.rst
   conventions.rst
   moreinfo.rst
   bugreport.rst

This guide is the official documentation of Munin. It has been written by the
Munin developers and other volunteers in parallel to the development of the
Munin software. It describes all the functionality that the current version of
Munin officially supports.

To make the large amount of information about Munin manageable, this guide has
been organized in several parts. Each part is targeted at a different class of
users, or at users in different stages of their Munin experience:

`Part I <install-index>`_ is an informal introduction for new users.

`Part II <install-index>`_ documents the query language environment, including
data types and functions, as well as user-level performance tuning. Every Munin
user should read this.

`Part III <install-index>`_ describes the installation and administration of
the server. Everyone who runs a Munin server, be it for private use or for
others, should read this part.

`Part IV <install-index>`_ describes the programming interfaces for Munin
client programs.

`Part V <install-index>`_ contains information for advanced users about the
extensibility capabilities of the server. Topics include user-defined data
types and functions.

`Part VI <install-index>`_ contains reference information about Munin commands,
client and server programs. This part supports the other parts with structured
information sorted by command or program.

`Part VII <install-index>`_ contains assorted information that might be of use
to Munin developers.

.. Note::
        If you think that our Guide looks quite familiar, it is done on
        purpose, as we took a great inspiration of `PostgreSQL's Manual`__. We even
        copied some generic sentences that were already very well worded.

        In fact, the PostgreSQL project was, and still is, of a great guidance,
        as it does so many things right. The parts that were *imported* from
        PostgreSQL are obviously still under the `PostgreSQL license`__ [#]_.

__ http://www.postgresql.org/docs/devel/static/index.html
__ http://www.postgresql.org/about/licence/
.. [#] We are not license experts, so if a PostgreSQL license guru has some
       issues with that, we'll be happy to resolve them together.

