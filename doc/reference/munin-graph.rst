.. _munin-graph:

.. program:: munin-graph

=============
 munin-graph
=============

DESCRIPTION
===========

munin-graph script is one of the munin master components run from the
:ref:`munin-cron` script.

If "graph_strategy" is set to "cron", munin-graph creates static
graphs from all RRD files in the munin database directory.

If graph_strategy is set to "cgi", munin-graph will not create graphs.
This is the proper setting when you run :ref:`munin-httpd`.

OPTIONS
=======

Some options can be negated by prefixing them with "no".
Example: --fork and --nofork

.. option:: --fork

   By default munin-graph forks subprocesses for drawing graphs to
   utilize available cores and I/O bandwidth. Can be negated
   with --nofork [--fork]

.. option:: --n <processes>

   Max number of concurrent processes [6]

.. option:: --force

   Force drawing of graphs that are not usually drawn due to options
   in the config file. Can be negated with --noforce [--noforce]

.. option:: --lazy

   Only redraw graphs when needed. Can be negated with --nolazy
   [--lazy]

.. option:: --help

   View this message.

.. option:: --version

   View version information.

.. option:: --debug

   Log debug messages.

.. option:: --screen

   If set, log messages to STDERR on the screen.

.. option:: --cron

   Behave as expected when run from cron. (Used internally in Munin.)
   Can be negated with --nocron

.. option:: --host <host>

   Limit graphed hosts to <host>. Multiple --host options may be
   supplied.

.. option:: --only-fqn <FQN>

   For internal use with CGI graphing. Graph only a single fully
   qualified named graph,

   For instance: --only-fqn
   root/Backend/dafnes.example.com/diskstats_iops

   Always use with the correct --host option.

.. option:: --config <file>

   Use <file> as configuration file. [/etc/munin/munin.conf]

.. option:: --list-images

   List the filenames of the images created. Can be negated with
   --nolist-images. [--nolist-images]

.. option:: --output-file | -o

   Output graph file. (used for CGI graphing)

.. option:: --log-file | -l

   Output log file. (used for CGI graphing)

.. option:: --day

   Create day-graphs. Can be negated with --noday. [--day]

.. option:: --week

   Create week-graphs. Can be negated with --noweek. [--week]

.. option:: --month

   Create month-graphs. Can be negated with --nomonth. [--month]

.. option:: --year

   Create year-graphs. Can be negated with --noyear. [--year]

.. option:: --sumweek

   Create summarised week-graphs. Can be negated with --nosumweek.
   [--summweek]

.. option:: --sumyear

   Create summarised year-graphs. Can be negated with --nosumyear.
   [--sumyear]

.. option:: --pinpoint <start,stop>

   Create custom-graphs. <start,stop> is the time in the standard unix
   Epoch format. [not active]

.. option:: --size_x <pixels>

   Sets the X size of the graph in pixels [175]

.. option:: --size_y <pixels>

   Sets the Y size of the graph in pixels [400]

.. option:: --lower_limit <lim>

   Sets the lower limit of the graph

.. option:: --upper_limit <lim>

   Sets the upper limit of the graph

.. note::

  :option:`--pinpoint` and :option:`--only-fqn` must not be combined
  with any of :option:`--day`, :option:`--week`, :option:`--month` or
  :option:`--year` (or their negating forms). The result of doing that
  is undefined.

SEE ALSO
========

See :ref:`munin` for an overview over munin.

:ref:`munin-cron`, :ref:`munin-httpd`
