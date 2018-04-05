.. _preface-index:

=========
 Preface
=========

.. toctree::
   :maxdepth: 1

   whatis.rst
   conventions.rst
   moreinfo.rst
   bugreport.rst
   ../develop/documenting.rst

This guide is **the** official documentation of Munin. It has been written by the
Munin developers and other volunteers in parallel to the development of the
Munin software. It aims to describe all the functionality that the current
version of Munin officially supports.

To make the large amount of information about Munin manageable, this guide has
been organized in several parts. Each part is targeted at a different class of
users, or at users in different stages of their Munin experience. It is nevertheless
still designed to be read as a book, sequentially, for the 3 first parts.

Further parts can be read in a more random manner, as one will search for a
specific thing in it. Extensive care has been taken to fully leverage the
hyperlinking abilities of modern documentation readers.

:ref:`Preface <preface-index>`

        *This is the part you are currently reading.*

        It focus on very generic
        information about Munin, and also gives some guidelines on how to
        interact with the Munin ecosystem.

        **Every Munin user should read this.**

:ref:`Part I - Tutorial <tutorial-index>`

        This part is an informal introduction for new users. It will try to
        cover most of what a user is expected to know about Munin. The focus
        here is really about taking the user by the hand and showing him
        around, while getting his hands a little wet.

	**Every Munin user should read this.**

:ref:`Part II - Architecture <architecture-index>`

        This part documents the various syntax that are used all throughout
        Munin.  It is about every thing a normal user can look himself without
        being considered as a developer. It means the syntax of the various
        config files, and the protocol on the network.

	**Every Munin user should read this.**

:ref:`Part III - Install <install-index>`

        This part describes the installation and administration of the server.
        It is about the OS part of Munin, which would be UID, path for the
        various components, how upgrades should be handled. It is also about
        how Munin interacts with its environment, such as how to secure a Munin
        install [#]_, how to enhance the performance of it.

	**Everyone who runs a Munin server, be it for private use or for
	others, should read this part.**

:ref:`Part IV - API <api-index>`

        This part describes the programming interfaces for Munin for advanced
        users, such as the SQL schema of the metadata, or the structure of the
        spool directories. It should cover everything that isn't covered by
        :ref:`Part II <protocol-index>`.

:ref:`Part V - Advanced use <advanced-index>`

        This part contains information for really advanced users about the
        obscure capabilities of Munin. Topics include undocumented stuff or
        even unwritten stuff that is still only in RFC phase.

:ref:`Part VI - Reference <reference-index>`

        This part contains reference information about Munin commands, client
        and server programs. This part supports the other parts with structured
        information sorted by command or program. This also serves as a
        repository for the full sample configs that are studied in the
        :ref:`Part I <tutorial-index>`

:ref:`Part VII - Others <others-index>`

        This part contains assorted information that might be of use to Munin
        developers. This section serves usually as incubator for elements
        before they migrate to the previous parts.


.. Note::
        If you think that our Guide looks quite familiar, it is done on
        purpose, as we took a great inspiration of `PostgreSQL's Manual`__. We even
        copied some generic sentences that were already very well worded.

        In fact, the PostgreSQL project was, and still is, of a great guidance,
        as it does so many things right. The parts that were *imported* from
        PostgreSQL are obviously still under the `PostgreSQL license`__ [#]_.

__ http://www.postgresql.org/docs/devel/static/index.html
__ http://www.postgresql.org/about/licence/


.. [#] Even how to configure SELinux with Munin !

.. [#] We are not license experts, so if a PostgreSQL license guru has some
       issues with that, we'll be happy to resolve them together.
