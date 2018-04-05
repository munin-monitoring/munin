======================================
Advanced Topics for Plugin Development
======================================

When developing plugins for Munin, there are some guidelines that should be observed.


Error Handling
==============

Munin plugins should handle error conditions in a fashion that make them easy to understand and debug.  Use these
guidelines when developing a plugin:

* Output may always contain comments.  Use comment blocks (lines starting with `#`) within the output to give more information
* If an error occurs in the plugin, two things should happen:

 * A non-zero exit code must be issued
 * A descriptive message should be written to STDERR.  On a deployed plugin, this message will appear in munin-node.log.  When invoked via munin-run, it'll appear in the console.


Handling temporary files
========================

Munin plugins often run with elevated privileges.

When creating and using temporary files, it is important to ensure that this is done securely.

Example shell plugin
--------------------

.. code-block:: bash

  #!/bin/sh

  # Allow others to override mktemp command with env.mktemp_command in the plugin config
  mktemp_command="${mktemp_command:-/bin/mktemp}"

  # make a temporary file, exit if something goes wrong, and ensure it is removed after exit
  my_tempfile=$(mktemp_command) || exit 73
  trap 'rm -f "$my_tempfile"' EXIT

  # rest of the plugin…

Example perl plugin
-------------------

For perl, you have better tools available to keep data in memory, but if you need a temporary file
or directory, you can use `File::Temp <https://metacpan.org/pod/File::Temp>`_.

.. code-block:: perl

  #!/usr/bin/perl

  use strict;
  use warnings;

  # make a tempfile, it will be removed on plugin exit
  use File::Temp qw/ tempfile /;
  my ($fh, $filename) = tempfile();


Storing the Plugin's State
==========================

Very few plugins need to access state information from previous executions of this plugin itself.
The :ref:`munin-node` prepares the necessary environment for this task. This includes a separate
writable directory that is owned by the user running the plugin and a file that is unique for each
:ref:`master <master-index>` that is requesting data from this plugin. These two storage locations
serve different purposes and are accessible via environment variables:

* :ref:`MUNIN_PLUGSTATE <plugin-env-MUNIN_PLUGSTATE>`: directory to be used for storing files that should be accessed by other plugins
* :ref:`MUNIN_STATEFILE <plugin-env-MUNIN_STATEFILE>`: single state file to be used by a plugin that wants to track its state from the last time it was requested by the same master

.. note::

  The datatype :ref:`DERIVE <datatype_derive>` is an elegant alternative to using a state file for
  tracking the *rate of change* of a given numeric value.


Portability
===========

Plugins should run on a wide variety of platforms.

Shell Plugins
-------------

Please prefer `/bin/sh` over `/bin/bash` (or other shells) if you do not need advanced features (e.g. arrays).
This allows such plugins to run on embedded platforms and some \*BSD systems that do not contain advanced shells by default.
When using `/bin/sh` as the interpreter, a feature set similar to busybox's `ash` or Debian's `dash` can be expected (i.e. use `shellcheck -s dash PLUGIN` for code quality checks).

The availability of the following tools can be assumed:

  * all the goodies within `coreutils <https://www.gnu.org/software/coreutils>`_
  * awk (e.g. `gawk <https://www.gnu.org/software/gawk>`_)

    * it is recommended to stick to the POSIX set of features (verify via `POSIXLY_CORRECT=1; export POSIXLY_CORRECT`)

  * `find <https://www.gnu.org/software/findutils>`_
  * `grep <https://www.gnu.org/software/grep>`_
  * `sed <https://www.gnu.org/software/sed>`_

In order to avoid external tools (e.g. `bc` or `dc`), the shell's arithmetic substition (e.g. `a=$((b + 3))`) should be used for integer operations and `awk` (e.g. `awk '{print $1/1000}'`) for non-trivial calculations.

Python Plugins
--------------

Python2 is approaching its end-of-life in 2020 and Python3 was released 2008. Thus new plugins should be written in Python3 only.

Core modules (included in CPython) should be prefered over external modules, whenever possible (e.g. use `urllib <https://docs.python.org/3/library/urllib>`_ instead of `requests <http://python-requests.org>`_).
