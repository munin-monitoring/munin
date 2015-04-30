.. _plugin-writing-tips:

======================================
 Tips for  writing good munin plugins
======================================

When developing plugins for Munin, there's some guidelines that should be observed.  

Error Handling
==============

Munin plugins should handle error conditions in a fashion that make them easy to understand and debug.  Use these
guidelines when developing a plugin:

* Output may always contain comments.  Use # blocks within the output to give more information
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
