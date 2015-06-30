.. _munin-html:

.. program:: munin-html

============
 munin-html
============

DESCRIPTION
===========

munin-html is one of the munin master components run from the
:ref:`munin-cron` script.

If :option:`html_strategy` is unset, or set to "cron", munin-html
creates static HTML pages. If set to "cgi", it will not generate
static pages, this is the proper setting when :ref:`munin-httpd` is
used.

OPTIONS
=======

munin-html has one significant option, which configuration file to
use.

Several other options are recognized and ignored as "compatibility
options", since :ref:`munin-cron` passes all options through to the
underlying components, of which munin-html is one.

.. option:: --config <file>

   Use <file> as configuration file. [/etc/munin/munin.conf]

.. option:: --help

   View this message.

.. option:: --debug

   Log debug messages.

.. option:: --screen

   If set, log messages to STDERR on the screen.

.. option:: --version

   View version information.

.. option:: --nofork

   Compatibility. No effect.

.. option:: --service <service>

   Compatibility. No effect.

.. option:: --host <host>

   Compatibility. No effect.

SEE ALSO
========

See :ref:`munin` for an overview over munin.

:ref:`munin-cron`, :ref:`munin-httpd`
