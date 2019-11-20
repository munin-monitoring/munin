.. _munin-get:

.. program:: munin-get

=========
munin-get
=========

.. note:: The tool "munin-get" is available since Munin v2.0.52.


Description
===========

The munin plugin helper allows to search, download and use munin plugins from external
repositories easily.

A common source of munin plugins is the 
`contrib <https://github.com/munin-monitoring/contrib>`_ repository (maintained by the munin
project).


Example
=======

Download and enable a plugin (by default: from the
`contrib <https://github.com/munin-monitoring/contrib>`_ repository)::

    munin-get update
    munin-get install traffic
    munin-get enable traffic
    service munin-node restart   # for systemd: systemctl restart munin-node

Add a n external repository::

    munin-get add-repository foo http://example.org/foo.git
    munin-get update
    munin-get list
