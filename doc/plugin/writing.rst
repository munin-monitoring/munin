.. _plugin-writing:

========================
 Writing a munin plugin
========================

**Tutorials:**

- :ref:`How to write plugins <howto-write-plugins>`
- :ref:`The Concise guide to plugin authoring <plugin-concise>`
- :ref:`How to write SNMP Munin plugins <howto-write-snmp-plugins>`

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
executable.  Note that most distributions place plugins in a different directory,
and 'activate' them by symlinking htem to /etc/munin/plugins.  New module development
should use a similar approach so that in-process development doesn't get run
by mistake.

Any time a new plugin is placed or symlinked into /etc/munin/plugins, munin-node should be restarted.

Debugging the plugin
====================

Plugins are just small programs or scripts, and just like small programs, are prone to problems
or unexpected behaviour.  When either developing a new plugin, or debugging an already existing one,
use the following information to help track down the problem:

* A plugin may be tested 'by hand' by using the command 'munin-run'.  Note the plugin needs to have been activated before this will work (see above).

* If an error occurs, error messages will be written to STDERR, and exit status will be non-zero.

* If a plugin is already activated, any errors that may happen when the 'munin-node' cron job is executed will be logged, via stderr, to /var/log/munin/munin-node.log
