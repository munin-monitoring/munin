Getting Started
================

Installation
------------

Before you can use Munin you need to install it, of course. It is possible that
Munin is already installed at your site, either because it was included in your
operating system distribution or because the system administrator already
installed it. If that is the case, you should obtain information from the
operating system documentation or your system administrator about how to access
Munin.

If you are installing Munin yourself, then refer to Install Chapter for
instructions on installation, and return to this guide when the installation is
complete. Be sure to follow closely the section about setting up the
appropriate configuration files.

If your site administrator has not set things up in the default way, you might
have some more work to do, as the examples that follow will need to be adapted.

Architectural Fundamentals
--------------------------

.. digraph:: architecture

  Master --> Node1
  Master --> Node2
  Node1 --> Plugin1
  Node1 --> Plugin2
  Node2 --> Plugin3
  Node2 --> Plugin4

Munin has a master-nodes architecture. The master is responsible for all central Munin-related tasks, and is usally referred to as the "munin server". The node is a small agent running on each monitored host. We can have agent-less monitoring but this is a special case that will be addressed only later.

Note that an usual setup involves having a node running also on the master host, in order to munin to monitor itself.

Adding a Node
-------------
