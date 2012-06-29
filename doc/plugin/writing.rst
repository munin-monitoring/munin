.. _plugin-writing:

========================
 Writing a munin plugin
========================

A munin plugin is a small executable. Usually, it is written in some
interpreted language.

In its simplest form, when the plugin is executed with the argument
"config", it outputs metadata needed for generating the graph. If it
is called with no arguments, it outputs the data which is to be
collected, and graphed later.

Plugin output
=============

The minimum plugin output when called with "config" it must output the
graph title.

It should also output a label for at least one datasource.

::

  graph_title Some title for our plugin
  something.label Foobar per second

When the plugin is executed with no arguments, it should output a
value for the datasource labelled in "config". It must not output
values for which there are no matching labels in the configuration
output.

::

  something.value 42

For a complete description of the available fields, see the
:ref:`plugin-reference`.

Example shell plugin
====================

The base of a plugin is a small option parser, ensuring the plugin is
called with the correct argument, if any.

Two main functions are defined: One for printing the configuration to
the standard output, and one for printing the data. In addition, we
have defined a function to generate the data itself, just to keep the
plugin readable.

The "output_usage" function is there just to be polite, it serves no
other function. :)

.. code-block:: bash

  #!/bin/sh

  output_config() {
      echo "graph_title Example graph"
      echo "plugins.label Number of plugins"
  }

  output_values() {
      printf "plugins.value %d\n" $(number_of_plugins)
  }

  number_of_plugins() {
      find /etc/munin/plugins -type l | wc -l
  }

  output_usage() {
      printf >&2 "%s - munin plugin to graph an example value\n" ${0##*/}
      printf >&2 "Usage: %s [config]\n" ${0##*/}
  }

  case $# in
      0)
          output_values
          ;;
      1)
          case $1 in
              config)
                  output_config
                  ;;
              *)
                  output_usage
                  exit 1
                  ;;
          esac
          ;;
      *)
          output_usage
          exit 1
          ;;
  esac

Activating the plugin
=====================

Place the plugin in the /etc/munin/plugins/ directory, and make it
executable.

Then, restart the munin-node.

Debugging the plugin
====================

To see how the plugin works, as the munin node would run it, you can
use the command "munin-run".

If the plugin is called "example", you can run "munin-run example
config" to see the plugin configuration, and "munin-run example" to
see the data.

If you do not get the output you expect, check if your munin plugin
needs more privileges. Normally, it is run as the "munin" user, but
gathering some data may need more access.

If the munin plugin emits errors, they will be visible in
/var/log/munin/munin-node.log
