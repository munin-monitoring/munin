====================
Further Information
====================

Besides the official documentation, that is this guide, there are many other
resources about Munin.

The fact that info is scattered around makes it sometimes difficult to find
relevant one. Each source has its purpose, and is usually only well-suited for
some kind of documentation.

Munin Guide
===========

These are the pages you are currently reading. It is aimed at the first read.
The chapters are designed as a walk-through of Munin's components in a very guided
manner. Its read constitutes the **basis** of every documentation available.
Specially when asking live (IRC_, mailing-lists_) channels, users there will
expect that you read the Guide prior to asking.

It is regularly updated, as its sources are directly in the munin source
directory, the last version can always be accessed online at
`http://guide.munin-monitoring.org/`__ thanks to ReadTheDoc__.

It is specially designed for easy contribution and distribution thanks to
`Sphinx`__. That aspect will be handled in :ref:`Contributing`.

__ http://guide.munin-monitoring.org/
__ http://readthedocs.org/
__ http://sphinx-doc.org/

.. _website:

Web
===

The `Munin web site`__ is the other main source of information. It has a wiki
format, but as spammers have become lately very clever, all content is now
added by registered users only.

Information there has the tendency of being rather extensive, but old. This is
mostly due to the fact that it was the first and only way of documenting Munin.
So in case there is conflicting information on the wiki and on the Guide,
better trust the Guide. We are obviously very glad if you can pinpoint the
conflicting infos so we can correct the wrong one.

Still, a very important part is the `FAQ`__ (Frequently Asked Questions), which
contains many answers to a wide array of questions. It is the only part of the
documentation in the wiki that is still regularly updated.

__ http://munin-monitoring.org/wiki/WikiStart
__ http://munin-monitoring.org/wiki/faq

.. _github:

GitHub
======

The `Munin GitHub`__ has slowly become the center of all the community-driven
development. It is a very solid platform, and despites its drawback of
delegation of control, given the importance it has today, no-one can ignore it.
The mere fact that we opened a presence there has increased the amount of small
contributions by an order of magnitude. Given that those are the meat of a
global improvement, it ranked as a success.

Main Repository
---------------

Therefore, we will move more and more services to cloud platforms as GitHub, as
it enables us to focus on delivering software and not caring about so much
infrastructure.

We already moved all code pull requests there, and new issues should be opened
there also. We obviously still accept any contribution by other means, such a
email, but as we couldn't resist the move from SVN to GIT, we are moving from
our Trac to GitHub.

__ https://github.com/munin-monitoring/munin

Contrib Repository
-------------------

The `contrib`__ part is even more live than before. It has very successfully
replaced the old :ref:`MuninExchange <Munin-Exchange>` site. Now, together with the `Plugin
Gallery`__ it offer all the useful features the old site offered, and is much
easier to contribute to. It also ease the integration work, and therefore
shortens the time it takes for your contributions to be reviewed and merged.

__ https://github.com/munin-monitoring/contrib
__ http://gallery.munin-monitoring.org/

.. _mailing-lists:

Mailing Lists
=============

If you don't find a specific answer to your question in the various
documentations, the mailing lists are a very good place to have your questions
shared with other users.

- `subscribe to the munin-users list <mailto:munin-users-request@lists.sourceforge.net?subject=subscribe>`_ (English)

- `subscribe to the munin-users-de <mailto:munin-users-de-request@lists.sourceforge.net?subject=subscribe>`_ (German)

- `subscribe to the munin-users-jp <mailto:munin-users-jp-request@lists.sourceforge.net?subject=subscribe>`_ (Japanese)

Please also consult the list archives. Your Munin issue may have been discussed already.

- `munin-users list archive <https://sourceforge.net/p/munin/mailman/munin-users/>`_ (English)

- `munin-users-de list archive <https://sourceforge.net/p/munin/mailman/munin-users-de/>`_ (German)

- `munin-users-jp list archive <https://sourceforge.net/p/munin/mailman/munin-users-jp>`_ (Japanese)

It happens that they were much more used in the previous years, but nowadays it
is much more common to seek an immediate answer on a specific issue, which is
best handled by IRC_. Therefore the mailing lists do appear very quiet, as most
users go on other channels.


.. _irc:

IRC
===

The most immediate way to get hold of us is to join our IRC channel:

        ``#munin on server irc.oftc.net``

The main timezone of the channel is Europe+America.

If you can explain your problem in a few clear sentences, without too
much copy&paste, IRC is a good way to try to get help. If you do need
to paste log files, configuration snippets, scripts and so on, please
use a pastebin_.

If the channel is all quiet, try again some time later, we do have
lives, families and jobs to deal with also.

You are more than welcome to just hang out, and while we don't mind
the occational intrusion of the real world into the flow, keep it
mostly on topic, and don't paste random links unless they are *really*
spectacular and intelligent.

Note that ``m-r-b`` is our beloved ``munin-relay-bot`` that bridges the
``#munin`` channel on various IRC networks, such as Freenode.

.. _pastebin: https://gist.github.com/

Yourself!
=========

Munin is an open-source project.

As such, it depends on the user community for ongoing support. As you begin to
use Munin, you will rely on others for help, either through the documentation
or through the mailing lists. Consider contributing your knowledge back. Read
the mailing lists and answer questions.

If you learn something which is not in the documentation, write it up and
contribute it. If you add features to the code, contribute them.

.. _planet-munin:

Planet Munin
============

In order to provide some central place to reference munin-related blogs out there, `Planet Munin <http://planet.munin-monitoring.org/>`_ was created.

It aggregates many blogs via RSS, and presents them as just one feed.

To add your blog, just visit us on our :ref:`IRC Channel <irc>`, and ask there.

Note that providing a tagged or a category-filtered feed is the best way to remain on-topic.
